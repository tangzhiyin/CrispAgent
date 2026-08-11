import SwiftUI

enum RootTab: Hashable {
    case chat
    case models
    case skills
    case settings
}

struct RootView: View {
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var selectedTab: RootTab = .chat

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView(selectedTab: $selectedTab)
                .tabItem {
                    Label("聊天", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(RootTab.chat)

            ModelLibraryView()
                .tabItem {
                    Label("模型", systemImage: "square.stack.3d.up")
                }
                .tag(RootTab.models)

            SkillLibraryView()
                .tabItem {
                    Label("Skills", systemImage: "wand.and.stars")
                }
                .tag(RootTab.skills)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
        }
        .tint(.accentColor)
        .fullScreenCover(
            isPresented: Binding(
                get: { !onboardingCompleted },
                set: { presented in
                    if !presented {
                        onboardingCompleted = true
                    }
                }
            )
        ) {
            OnboardingView {
                selectedTab = .models
                onboardingCompleted = true
            }
        }
    }
}

