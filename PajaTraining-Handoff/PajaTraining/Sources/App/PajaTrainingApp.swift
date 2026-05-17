import SwiftUI
import BackgroundTasks

@main
struct PajaTrainingApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task { await appState.bootstrap() }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isBootstrapping {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            } else if appState.needsOnboarding {
                OnboardingView()
            } else {
                RootTabView()
            }
        }
        .animation(.easeInOut, value: appState.needsOnboarding)
    }
}
