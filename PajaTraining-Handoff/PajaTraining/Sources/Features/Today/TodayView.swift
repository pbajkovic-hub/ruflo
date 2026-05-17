import SwiftUI

struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm: TodayViewModel

    init() {
        _vm = StateObject(wrappedValue: TodayViewModel(db: DatabaseStore(), userId: ""))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if vm.isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        recoverySection
                        if let session = vm.session {
                            PrescriptionCardView(session: session)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.top)
            }
            .navigationTitle(todayTitle())
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await vm.load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private var recoverySection: some View {
        let recovery = vm.buildRecoveryInput()
        VStack(spacing: 16) {
            RecoveryRingView(
                state: recovery.state,
                pct: recovery.pct,
                priorBasisDays: vm.priorBasisDays,
                confidence: recovery.confidence
            )

            // One-line action sentence
            if let why = vm.session?.why {
                Text(why)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }

            // Calibrating note
            if recovery.state == .calibrating {
                Text("No prescription until baseline is established.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Confidence badge
            if recovery.confidence == .low {
                Label("Apple Health estimate — Oura not available today",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.pajaAmber)
                    .padding(.horizontal)
            }
        }
    }

    private func todayTitle() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }
}
