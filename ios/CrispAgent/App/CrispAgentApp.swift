import SwiftUI

@main
struct CrispAgentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.models)
                .environmentObject(appState.skills)
                .environmentObject(appState.runtime)
                .environmentObject(appState.chat)
        }
    }
}

