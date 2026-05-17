import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }
            TrainView()
                .tabItem {
                    Label("Train", systemImage: "dumbbell.fill")
                }
            TrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
        }
        .tint(Color.pajaGreen)
    }
}

extension Color {
    static let pajaGreen  = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let pajaAmber  = Color(red: 1.00, green: 0.75, blue: 0.00)
    static let pajaRed    = Color(red: 0.96, green: 0.26, blue: 0.21)

    static func recovery(_ state: RecoveryState) -> Color {
        switch state {
        case .green:       return .pajaGreen
        case .amber:       return .pajaAmber
        case .red:         return .pajaRed
        case .calibrating: return .secondary
        case .unknown:     return .secondary
        }
    }
}
