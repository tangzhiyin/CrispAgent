import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == ModelStore.backgroundSessionIdentifier else {
            completionHandler()
            return
        }

        BackgroundSessionCoordinator.completionHandler = completionHandler
        ModelStore.shared?.activateBackgroundSession()
    }
}

@MainActor
enum BackgroundSessionCoordinator {
    static var completionHandler: (() -> Void)? {
        didSet { finishIfPossible() }
    }
    private static var eventsAreFinished = false

    static func markEventsFinished() {
        eventsAreFinished = true
        finishIfPossible()
    }

    private static func finishIfPossible() {
        guard eventsAreFinished, let handler = completionHandler else {
            return
        }
        eventsAreFinished = false
        completionHandler = nil
        handler()
    }
}
