import SwiftUI

/// Weekly body composition entry form (InBody supplement — weekly, not daily).
struct BodyCompositionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var weightKg: String = ""
    @State private var bodyFatPct: String = ""
    @State private var leanMassKg: String = ""
    @State private var isSaving = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Weekly InBody Entry") {
                    LabeledContent("Weight (kg)") {
                        TextField("e.g. 82.5", text: $weightKg)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Body Fat (%)") {
                        TextField("e.g. 18.2", text: $bodyFatPct)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Lean Mass (kg)") {
                        TextField("e.g. 67.5", text: $leanMassKg)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Text("Deeper InBody metrics (skeletal muscle, visceral fat, body water) aren't available via Apple Health. Add them here manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Body Composition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
            .alert("Saved!", isPresented: $saved) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func save() async {
        isSaving = true
        let now = iso8601Now()
        let today = isoDate(Date())
        let record = BodyCompositionRecord(
            id: UUID().uuidString,
            userId: appState.userId,
            measuredOn: today,
            source: "inbody_manual",
            weightKg: Double(weightKg),
            bodyFatPct: Double(bodyFatPct),
            skeletalMuscleMassKg: nil,
            leanBodyMassKg: Double(leanMassKg),
            totalBodyWaterL: nil,
            visceralFatLevel: nil,
            bmrKcal: nil,
            bmi: nil,
            inbodyScore: nil,
            segmentalLeanJson: nil,
            rawPayload: nil,
            notes: nil,
            createdAt: now
        )
        _ = try? await appState.db.write { db in
            var r = record; try r.save(db)
        }
        isSaving = false
        saved = true
    }
}
