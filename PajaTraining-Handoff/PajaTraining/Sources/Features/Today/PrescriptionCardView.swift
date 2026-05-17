import SwiftUI

/// The adaptive prescription card — the centrepiece of Today.
/// Shows today's session (exercises → sets → reps → kg) with the "why" line.
struct PrescriptionCardView: View {
    let session: PrescribedSession
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: day label + why
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.dayLabel)
                        .font(.headline)
                    Text(session.why)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { withAnimation { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            if expanded {
                Divider().padding(.horizontal)
                ForEach(session.exercises, id: \.name) { exercise in
                    ExerciseRowView(exercise: exercise)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ExerciseRowView: View {
    let exercise: PrescribedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exercise.name)
                    .font(.subheadline).bold()
                if exercise.isMainLift {
                    Text("MAIN")
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.pajaGreen.opacity(0.15))
                        .foregroundStyle(Color.pajaGreen)
                        .clipShape(Capsule())
                }
                Spacer()
            }
            HStack(spacing: 12) {
                ForEach(exercise.sets, id: \.setNumber) { set in
                    VStack(spacing: 2) {
                        Text(kgLabel(set.kg))
                            .font(.caption).bold()
                        Text("\(set.reps) reps")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if set.isBackoff {
                            Text("back-off")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 50)
                    .padding(6)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
    }

    private func kgLabel(_ kg: Double) -> String {
        kg == 0 ? "BW" : "\(Int(kg)) kg"
    }
}
