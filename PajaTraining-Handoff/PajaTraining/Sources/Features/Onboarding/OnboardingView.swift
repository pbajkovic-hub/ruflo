import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm: OnboardingViewModel

    init() {
        // ViewModel created lazily after env is available; placeholder init here.
        _vm = StateObject(wrappedValue: OnboardingViewModel(db: DatabaseStore(), userId: ""))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case .ouraToken:  OuraTokenStep(vm: vm)
                case .healthKit:  HealthKitStep(vm: vm)
                case .split:      SplitStep(vm: vm)
                case .trainingDays: TrainingDaysStep(vm: vm, onComplete: {
                    Task {
                        await vm.finish()
                        await appState.completeOnboarding()
                    }
                })
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            // Reinitialize with real appState values once environment is available.
        }
    }
}

// MARK: - Step 1: Oura Token

private struct OuraTokenStep: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Connect Oura")
                .font(.title2).bold()
            Text("Paste your Oura Personal Access Token. Find it at cloud.ouraring.com → Developer Settings → Personal Access Tokens.")
                .foregroundStyle(.secondary)
            SecureField("Paste token here…", text: $vm.ouraToken)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if let err = vm.errorMessage {
                Text(err).foregroundStyle(.red).font(.caption)
            }
            Spacer()
            Button { Task { await vm.validateToken() } } label: {
                Group {
                    if vm.isLoading { ProgressView() } else { Text("Continue") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isLoading || vm.ouraToken.isEmpty)
        }
        .padding()
    }
}

// MARK: - Step 2: HealthKit

private struct HealthKitStep: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Connect Apple Health")
                .font(.title2).bold()
            Text("Paja Training reads HRV, resting heart rate, sleep, and workout data from Apple Health to fill gaps when Oura data is missing.")
                .foregroundStyle(.secondary)
            Image(systemName: "heart.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            Spacer()
            Button { Task { await vm.requestHealthKit() } } label: {
                Text("Grant Apple Health Access")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button("Skip for now") { vm.step = .split }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Step 3: Split selection

private struct SplitStep: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your Program")
                .font(.title2).bold()
            Text("Choose your training split. Both are built-in and will adapt to your recovery.")
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                SplitCard(title: "Push / Pull / Legs",
                          subtitle: "3-day rotation, deload every 4 weeks",
                          isSelected: vm.selectedSplit == .ppl) {
                    vm.selectedSplit = .ppl
                }
                SplitCard(title: "Upper / Lower",
                          subtitle: "2-day rotation, deload every 5 weeks",
                          isSelected: vm.selectedSplit == .upperLower) {
                    vm.selectedSplit = .upperLower
                }
            }
            Spacer()
            Button { vm.step = .trainingDays } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

private struct SplitCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.pajaGreen)
                }
            }
            .padding()
            .background(isSelected ? Color.pajaGreen.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.pajaGreen : .clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Step 4: Training days

private struct TrainingDaysStep: View {
    @ObservedObject var vm: OnboardingViewModel
    let onComplete: () -> Void
    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Training Days")
                .font(.title2).bold()
            Text("Which days do you typically train? The app logs sessions on these days.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(0..<7) { i in
                    let selected = vm.trainingDays.contains(i)
                    Button {
                        if selected { vm.trainingDays.remove(i) } else { vm.trainingDays.insert(i) }
                    } label: {
                        Text(days[i])
                            .font(.caption).bold()
                            .frame(width: 40, height: 40)
                            .background(selected ? Color.pajaGreen : Color(.secondarySystemBackground))
                            .foregroundStyle(selected ? .white : .primary)
                            .clipShape(Circle())
                    }
                }
            }
            Spacer()
            Button(action: onComplete) {
                Group {
                    if vm.isLoading { ProgressView() } else { Text("Start Training") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isLoading || vm.trainingDays.isEmpty)
            if let err = vm.errorMessage {
                Text(err).foregroundStyle(.red).font(.caption)
            }
        }
        .padding()
    }
}
