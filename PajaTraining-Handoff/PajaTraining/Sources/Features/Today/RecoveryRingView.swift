import SwiftUI

/// The "one big thing" on Today: a ring showing recovery state.
/// During calibration, the ring outline fills proportionally to progress.
struct RecoveryRingView: View {
    let state: RecoveryState
    let pct: Int?
    let priorBasisDays: Int
    let confidence: RecoveryInput.Confidence

    private var progress: Double {
        switch state {
        case .calibrating:
            return Double(priorBasisDays) / Double(ResolvedMetricsBuilder.calibrationDays)
        default:
            return Double(pct ?? 0) / 100.0
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 18)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.recovery(state),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)

            VStack(spacing: 4) {
                if state == .calibrating {
                    Text("Day \(priorBasisDays) of \(ResolvedMetricsBuilder.calibrationDays)")
                        .font(.title3).bold()
                    Text("Learning your\nbaseline")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else if let p = pct {
                    Text("\(p)%")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.recovery(state))
                    if confidence == .low {
                        Label("Estimated", systemImage: "waveform.path.ecg")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "questionmark")
                        .font(.title).foregroundStyle(.secondary)
                    Text("No data").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 200, height: 200)
    }
}
