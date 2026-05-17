import SwiftUI

struct TrainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm: TrainViewModel
    // Today's prescribed session is passed in from TodayViewModel if navigated directly,
    // or loaded independently here.
    @State private var todayVm: TodayViewModel?
    @State private var showDone = false

    init() {
        _vm = StateObject(wrappedValue: TrainViewModel(db: DatabaseStore(), userId: ""))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.loggedSets.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { finishButton }
        }
        .task { await loadSession() }
        .alert("Session Complete!", isPresented: $showDone) {
            Button("OK") { }
        }
    }

    private var exerciseList: some View {
        ScrollView {
            VStack(spacing: 16) {
                RestTimerView()
                    .padding(.horizontal)
                ForEach(vm.loggedSets.keys.sorted(), id: \.self) { name in
                    ExerciseCardView(
                        exerciseName: name,
                        sets: vm.loggedSets[name] ?? [],
                        onToggle: { id in vm.toggleSet(exerciseName: name, setId: id) },
                        onRepsUp: { id in vm.adjustReps(exerciseName: name, setId: id, delta: 1) },
                        onRepsDown: { id in vm.adjustReps(exerciseName: name, setId: id, delta: -1) },
                        onKgUp: { id in vm.adjustKg(exerciseName: name, setId: id, delta: 2.5) },
                        onKgDown: { id in vm.adjustKg(exerciseName: name, setId: id, delta: -2.5) }
                    )
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No session today")
                .font(.title3)
            Text("Check Today tab for your prescription.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var finishButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !vm.loggedSets.isEmpty {
                Button("Finish") {
                    Task {
                        try? await vm.finishSession()
                        showDone = true
                    }
                }
                .fontWeight(.semibold)
            }
        }
    }

    private func loadSession() async {
        let tv = TodayViewModel(db: appState.db, userId: appState.userId)
        await tv.load()
        todayVm = tv
        await vm.load(prescribed: tv.session, resolved: tv.resolved)
    }
}

// MARK: - Exercise card

private struct ExerciseCardView: View {
    let exerciseName: String
    let sets: [TrainViewModel.LoggedSet]
    let onToggle: (String) -> Void
    let onRepsUp: (String) -> Void
    let onRepsDown: (String) -> Void
    let onKgUp: (String) -> Void
    let onKgDown: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(exerciseName)
                .font(.headline)
                .padding()
            Divider()
            ForEach(sets) { set in
                SetRowView(
                    set: set,
                    onToggle: { onToggle(set.id) },
                    onRepsUp: { onRepsUp(set.id) },
                    onRepsDown: { onRepsDown(set.id) },
                    onKgUp: { onKgUp(set.id) },
                    onKgDown: { onKgDown(set.id) }
                )
                Divider()
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct SetRowView: View {
    let set: TrainViewModel.LoggedSet
    let onToggle: () -> Void
    let onRepsUp: () -> Void
    let onRepsDown: () -> Void
    let onKgUp: () -> Void
    let onKgDown: () -> Void

    var kgLabel: String { set.doneKg == 0 ? "BW" : "\(Int(set.doneKg)) kg" }

    var body: some View {
        HStack(spacing: 12) {
            // Set number
            Text("Set \(set.setNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40)

            // Reps stepper
            HStack(spacing: 4) {
                Button(action: onRepsDown) { Image(systemName: "minus.circle") }
                Text("\(set.doneReps)").frame(width: 28).font(.body.bold())
                Button(action: onRepsUp) { Image(systemName: "plus.circle") }
            }

            // Kg stepper (skip for bodyweight)
            if set.targetKg > 0 {
                HStack(spacing: 4) {
                    Button(action: onKgDown) { Image(systemName: "minus.circle") }
                    Text(kgLabel).frame(width: 52).font(.body.bold())
                    Button(action: onKgUp) { Image(systemName: "plus.circle") }
                }
            } else {
                Text("Bodyweight").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()
            // Done toggle
            Button(action: onToggle) {
                Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.completed ? Color.pajaGreen : Color(.systemGray3))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .opacity(set.completed ? 0.6 : 1.0)
    }
}
