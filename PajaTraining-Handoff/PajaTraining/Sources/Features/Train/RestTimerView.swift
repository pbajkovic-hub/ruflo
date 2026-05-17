import SwiftUI

struct RestTimerView: View {
    @State private var elapsed: Int = 0
    @State private var timer: Timer?
    @State private var running = false
    var defaultSeconds: Int = 120

    var body: some View {
        HStack(spacing: 16) {
            Text(timeString(elapsed))
                .font(.system(.title3, design: .monospaced).bold())
                .foregroundStyle(elapsed > defaultSeconds ? .pajaAmber : .primary)
            Button { running ? stop() : start() } label: {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            Button { reset() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private func start() {
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed += 1
        }
    }

    private func stop() {
        running = false
        timer?.invalidate()
        timer = nil
    }

    private func reset() {
        stop()
        elapsed = 0
    }

    private func timeString(_ secs: Int) -> String {
        String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
