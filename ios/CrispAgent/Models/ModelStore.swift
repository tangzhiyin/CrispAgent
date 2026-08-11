import Foundation

private struct DownloadTaskMetadata {
    let modelID: String
    let sourceIndex: Int

    init?(description: String?) {
        guard let description else { return nil }
        let pieces = description.split(separator: "|", omittingEmptySubsequences: false)
        guard pieces.count == 2, let sourceIndex = Int(pieces[1]) else { return nil }
        self.modelID = String(pieces[0])
        self.sourceIndex = sourceIndex
    }

    init(modelID: String, sourceIndex: Int) {
        self.modelID = modelID
        self.sourceIndex = sourceIndex
    }

    var description: String {
        "\(modelID)|\(sourceIndex)"
    }
}

@MainActor
final class ModelStore: NSObject, ObservableObject, @preconcurrency URLSessionDownloadDelegate {
    static let backgroundSessionIdentifier = "com.crisp.CrispAgent.model-downloads.v1"
    static weak var shared: ModelStore?

    @Published private(set) var statuses: [String: ModelInstallStatus] = [:]
    @Published private(set) var storageErrorMessage: String?
    @Published var selectedModelID: String {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: Keys.selectedModelID) }
    }
    @Published var backendPreference: InferenceBackendPreference {
        didSet { UserDefaults.standard.set(backendPreference.rawValue, forKey: Keys.backend) }
    }

    var isModelInUse: ((String) -> Bool)?

    private enum Keys {
        static let selectedModelID = "models.selectedModelID"
        static let backend = "models.backend"
    }

    private lazy var backgroundSession: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.backgroundSessionIdentifier
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true

        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }()

    private var tasksByModelID: [String: URLSessionDownloadTask] = [:]
    private var intentionallyPausing = Set<String>()
    private var intentionallyCancelling = Set<String>()
    private var pendingVerifications = 0
    private var sessionEventsDidFinish = false

    override init() {
        let storedModelID = UserDefaults.standard.string(forKey: Keys.selectedModelID)
        self.selectedModelID = storedModelID ?? LocalModelDescriptor.defaultModel.id

        let storedBackend = UserDefaults.standard.string(forKey: Keys.backend)
        self.backendPreference = InferenceBackendPreference(rawValue: storedBackend ?? "")
            ?? .automatic

        super.init()
        Self.shared = self
        scanInstalledModels()
        recoverStagedModels()
        activateBackgroundSession()
    }

    var selectedModel: LocalModelDescriptor {
        LocalModelDescriptor.model(withID: selectedModelID)
            ?? LocalModelDescriptor.defaultModel
    }

    var physicalMemoryGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    }

    func status(for model: LocalModelDescriptor) -> ModelInstallStatus {
        statuses[model.id] ?? .notInstalled
    }

    func installedURL(for model: LocalModelDescriptor) -> URL? {
        guard let url = try? modelFileURL(for: model) else {
            return nil
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func select(_ model: LocalModelDescriptor) throws {
        guard installedURL(for: model) != nil else {
            throw ModelStoreError.notInstalled
        }
        selectedModelID = model.id
    }

    func startDownload(_ model: LocalModelDescriptor) throws {
        guard installedURL(for: model) == nil else {
            throw ModelStoreError.alreadyInstalled
        }
        guard !statuses.values.contains(where: {
            $0.phase == .downloading || $0.phase == .verifying
        }) else {
            throw ModelStoreError.anotherDownloadInProgress
        }
        try checkAvailableStorage(for: model)

        let resumeURL = try resumeDataURL(for: model)
        let resumeData = try? Data(contentsOf: resumeURL)
        try? FileManager.default.removeItem(at: resumeURL)
        startTask(model: model, sourceIndex: 0, resumeData: resumeData)
    }

    func pauseDownload(_ model: LocalModelDescriptor) {
        guard let task = tasksByModelID[model.id] else { return }
        intentionallyPausing.insert(model.id)

        task.cancel { [weak self] resumeData in
            Task { @MainActor in
                guard let self else { return }
                self.tasksByModelID[model.id] = nil

                if let resumeData {
                    do {
                        try resumeData.write(
                            to: self.resumeDataURL(for: model),
                            options: .atomic
                        )
                    } catch {
                        self.fail(modelID: model.id, error: error)
                        return
                    }
                }

                var status = self.status(for: model)
                status.phase = .paused
                status.message = nil
                self.statuses[model.id] = status
            }
        }
    }

    func cancelDownload(_ model: LocalModelDescriptor) {
        if let task = tasksByModelID[model.id] {
            intentionallyCancelling.insert(model.id)
            task.cancel()
        }
        tasksByModelID[model.id] = nil
        if let resumeURL = try? resumeDataURL(for: model) {
            try? FileManager.default.removeItem(at: resumeURL)
        }
        statuses[model.id] = .notInstalled

    }

    func deleteInstalledModel(_ model: LocalModelDescriptor) throws {
        if isModelInUse?(model.id) == true {
            throw ModelStoreError.modelInUse
        }

        let directory = try modelDirectoryURL(for: model)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ModelStoreError.notInstalled
        }
        try FileManager.default.removeItem(at: directory)
        statuses[model.id] = .notInstalled
    }

    func activateBackgroundSession() {
        backgroundSession.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                for case let task as URLSessionDownloadTask in tasks {
                    guard let metadata = DownloadTaskMetadata(
                        description: task.taskDescription
                    ), let model = LocalModelDescriptor.model(withID: metadata.modelID)
                    else {
                        task.cancel()
                        continue
                    }

                    self.tasksByModelID[model.id] = task
                    self.statuses[model.id] = ModelInstallStatus(
                        phase: .downloading,
                        progress: task.progress.fractionCompleted,
                        completedBytes: task.countOfBytesReceived,
                        totalBytes: task.countOfBytesExpectedToReceive > 0
                            ? task.countOfBytesExpectedToReceive
                            : model.expectedBytes
                    )
                }
            }
        }
    }

    private func startTask(
        model: LocalModelDescriptor,
        sourceIndex: Int,
        resumeData: Data?
    ) {
        guard sourceIndex < model.downloadURLs.count else {
            fail(
                modelID: model.id,
                error: URLError(.resourceUnavailable)
            )
            return
        }

        let task: URLSessionDownloadTask
        if let resumeData {
            task = backgroundSession.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: model.downloadURLs[sourceIndex])
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 120
            task = backgroundSession.downloadTask(with: request)
        }

        task.taskDescription = DownloadTaskMetadata(
            modelID: model.id,
            sourceIndex: sourceIndex
        ).description
        tasksByModelID[model.id] = task
        statuses[model.id] = ModelInstallStatus(
            phase: .downloading,
            progress: 0,
            completedBytes: 0,
            totalBytes: model.expectedBytes
        )
        task.resume()
    }

    private func scanInstalledModels() {
        for model in LocalModelDescriptor.all {
            do {
                let modelURL = try modelFileURL(for: model)
                if FileManager.default.fileExists(atPath: modelURL.path) {
                    statuses[model.id] = .installed(bytes: model.expectedBytes)
                    continue
                }

                let resumeURL = try resumeDataURL(for: model)
                if FileManager.default.fileExists(atPath: resumeURL.path) {
                    statuses[model.id] = ModelInstallStatus(
                        phase: .paused,
                        progress: 0,
                        completedBytes: 0,
                        totalBytes: model.expectedBytes,
                        message: "发现可继续的下载"
                    )
                } else {
                    statuses[model.id] = .notInstalled
                }
            } catch {
                storageErrorMessage = error.localizedDescription
                statuses[model.id] = ModelInstallStatus(
                    phase: .failed,
                    progress: 0,
                    completedBytes: 0,
                    totalBytes: model.expectedBytes,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func checkAvailableStorage(for model: LocalModelDescriptor) throws {
        let root = try AppDirectories.applicationSupport()
        let values = try root.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let available = values.volumeAvailableCapacityForImportantUsage else {
            return
        }

        let required = Int64(Double(model.expectedBytes) * 1.15)
        if available < required {
            throw ModelStoreError.insufficientStorage(
                required: required,
                available: available
            )
        }
    }

    private func modelDirectoryURL(for model: LocalModelDescriptor) throws -> URL {
        try AppDirectories.models()
            .appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent(model.revision, isDirectory: true)
    }

    private func modelFileURL(for model: LocalModelDescriptor) throws -> URL {
        try modelDirectoryURL(for: model)
            .appendingPathComponent(model.fileName, isDirectory: false)
    }

    private func resumeDataURL(for model: LocalModelDescriptor) throws -> URL {
        try AppDirectories.modelDownloads()
            .appendingPathComponent("\(model.id).resume")
    }

    private func stagedModelURL(for model: LocalModelDescriptor) throws -> URL {
        try AppDirectories.modelDownloads()
            .appendingPathComponent("\(model.id).part")
    }

    private func finishDownload(
        model: LocalModelDescriptor,
        stagedURL: URL
    ) {
        if intentionallyCancelling.contains(model.id) {
            try? FileManager.default.removeItem(at: stagedURL)
            statuses[model.id] = .notInstalled
            return
        }
        pendingVerifications += 1
        tasksByModelID[model.id] = nil
        statuses[model.id] = ModelInstallStatus(
            phase: .verifying,
            progress: 1,
            completedBytes: model.expectedBytes,
            totalBytes: model.expectedBytes,
            message: "正在校验 SHA-256…"
        )

        Task.detached(priority: .utility) {
            do {
                try ModelIntegrityVerifier.verify(
                    fileURL: stagedURL,
                    expectedBytes: model.expectedBytes,
                    expectedSHA256: model.sha256
                )
                try await self.installVerifiedModel(model, stagedURL: stagedURL)
            } catch {
                try? FileManager.default.removeItem(at: stagedURL)
                await self.fail(modelID: model.id, error: error)
            }
            await self.verificationDidComplete()
        }
    }

    private func recoverStagedModels() {
        for model in LocalModelDescriptor.all {
            guard let stagedURL = try? stagedModelURL(for: model),
                  FileManager.default.fileExists(atPath: stagedURL.path)
            else {
                continue
            }

            if installedURL(for: model) != nil {
                try? FileManager.default.removeItem(at: stagedURL)
            } else {
                finishDownload(model: model, stagedURL: stagedURL)
            }
        }
    }

    private func verificationDidComplete() {
        pendingVerifications = max(0, pendingVerifications - 1)
        finishBackgroundEventsIfPossible()
    }

    private func finishBackgroundEventsIfPossible() {
        guard sessionEventsDidFinish, pendingVerifications == 0 else {
            return
        }
        sessionEventsDidFinish = false
        BackgroundSessionCoordinator.markEventsFinished()
    }

    private func installVerifiedModel(
        _ model: LocalModelDescriptor,
        stagedURL: URL
    ) throws {
        let directory = try modelDirectoryURL(for: model)
        try AppDirectories.createDirectory(directory)
        let destination = try modelFileURL(for: model)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: stagedURL)
        } else {
            try FileManager.default.moveItem(at: stagedURL, to: destination)
        }
        try AppDirectories.excludeFromBackup(directory)
        try? FileManager.default.removeItem(at: resumeDataURL(for: model))

        statuses[model.id] = .installed(bytes: model.expectedBytes)
        if installedURL(for: selectedModel) == nil {
            selectedModelID = model.id
        }
    }

    private func handleDownloadFailure(
        model: LocalModelDescriptor,
        sourceIndex: Int,
        error: Error,
        resumeData: Data?
    ) {
        tasksByModelID[model.id] = nil

        if let resumeData {
            do {
                try resumeData.write(
                    to: resumeDataURL(for: model),
                    options: .atomic
                )
            } catch {
                fail(modelID: model.id, error: error)
                return
            }
        }

        let nextSource = sourceIndex + 1
        if resumeData == nil, nextSource < model.downloadURLs.count {
            startTask(model: model, sourceIndex: nextSource, resumeData: nil)
            return
        }

        fail(modelID: model.id, error: error)
    }

    private func fail(modelID: String, error: Error) {
        var status = statuses[modelID] ?? .notInstalled
        status.phase = .failed
        status.message = error.localizedDescription
        statuses[modelID] = status
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let metadata = DownloadTaskMetadata(
            description: downloadTask.taskDescription
        ), let model = LocalModelDescriptor.model(withID: metadata.modelID)
        else {
            downloadTask.cancel()
            return
        }

        let total = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : model.expectedBytes
        let progress = min(1, Double(totalBytesWritten) / Double(max(1, total)))

        Task { @MainActor [weak self] in
            guard let self,
                  !self.intentionallyCancelling.contains(model.id),
                  !self.intentionallyPausing.contains(model.id) else {
                return
            }
            self.statuses[model.id] = ModelInstallStatus(
                phase: .downloading,
                progress: progress,
                completedBytes: totalBytesWritten,
                totalBytes: total,
                message: nil
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let metadata = DownloadTaskMetadata(
            description: downloadTask.taskDescription
        ), let model = LocalModelDescriptor.model(withID: metadata.modelID)
        else {
            return
        }

        do {
            let stagedURL = try stagedModelURL(for: model)
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                try FileManager.default.removeItem(at: stagedURL)
            }
            try FileManager.default.moveItem(at: location, to: stagedURL)

            Task { @MainActor [weak self] in
                self?.finishDownload(
                    model: model,
                    stagedURL: stagedURL
                )
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.fail(modelID: model.id, error: error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let metadata = DownloadTaskMetadata(description: task.taskDescription),
              let model = LocalModelDescriptor.model(withID: metadata.modelID)
        else {
            return
        }

        let resumeData = error.flatMap {
            ($0 as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.intentionallyPausing.remove(model.id) != nil
                || self.intentionallyCancelling.remove(model.id) != nil {
                return
            }
            guard let error else { return }
            self.handleDownloadFailure(
                model: model,
                sourceIndex: metadata.sourceIndex,
                error: error,
                resumeData: resumeData
            )
        }
    }

    nonisolated func urlSessionDidFinishEvents(
        forBackgroundURLSession session: URLSession
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                BackgroundSessionCoordinator.markEventsFinished()
                return
            }
            self.sessionEventsDidFinish = true
            self.finishBackgroundEventsIfPossible()
        }
    }
}
