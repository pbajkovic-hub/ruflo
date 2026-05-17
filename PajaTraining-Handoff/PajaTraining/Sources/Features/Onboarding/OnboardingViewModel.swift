import Foundation
import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step { case ouraToken, healthKit, split, trainingDays }

    @Published var step: Step = .ouraToken
    @Published var ouraToken: String = ""
    @Published var selectedSplit: SplitType = .ppl
    @Published var trainingDays: Set<Int> = [1, 3, 5]  // Mon, Wed, Fri
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db: DatabaseStore
    private let userId: String

    init(db: DatabaseStore, userId: String) {
        self.db = db
        self.userId = userId
    }

    func validateToken() async {
        guard !ouraToken.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please paste your Oura Personal Access Token."
            return
        }
        isLoading = true
        errorMessage = nil
        // Quick validation: try a minimal Oura API call
        do {
            let testStore = GRDBDailyLogStore(db: db, userId: userId)
            let client = OuraClient(token: ouraToken, store: testStore)
            let today = isoDate(Date())
            let yesterday = isoDate(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
            try await client.sync(from: yesterday, to: today)
            try KeychainStore.saveOuraToken(ouraToken)
            step = .healthKit
        } catch OuraError.tokenInvalid {
            errorMessage = "Token not recognized. Check it in Oura → Developer Settings."
        } catch OuraError.membershipLapsed {
            errorMessage = "Oura membership lapsed — no data available."
        } catch {
            // Token might be valid but network failed — allow continuing
            try? KeychainStore.saveOuraToken(ouraToken)
            step = .healthKit
        }
        isLoading = false
    }

    func requestHealthKit() async {
        #if canImport(HealthKit)
        let reader = HealthKitReader()
        try? await reader.requestAuthorization()
        #endif
        step = .split
    }

    func finish() async {
        isLoading = true
        do {
            let template = selectedSplit == .ppl ? ProgramTemplates.ppl : ProgramTemplates.upperLower
            let programId = UUID().uuidString
            let instanceId = UUID().uuidString
            let now = iso8601Now()

            try await db.write { db in
                var prog = ProgramRecord(
                    id: programId,
                    userId: self.userId,
                    split: self.selectedSplit.rawValue,
                    templateKey: template.key,
                    createdAt: now
                )
                try prog.insert(db)

                var inst = ProgramInstanceRecord(
                    id: instanceId,
                    userId: self.userId,
                    programId: programId,
                    status: "active",
                    rotationIndex: 0,
                    weekInBlock: 1,
                    startedAt: now
                )
                try inst.insert(db)

                // Record oura connection row (token is in Keychain).
                var conn = ConnectionRecord(
                    id: UUID().uuidString,
                    userId: self.userId,
                    provider: "oura",
                    status: "connected",
                    keychainRef: "oura-pat",
                    lastSyncAt: nil
                )
                try conn.save(db)
            }
        } catch {
            errorMessage = "Setup failed: \(error.localizedDescription)"
            isLoading = false
            return
        }
        isLoading = false
    }
}
