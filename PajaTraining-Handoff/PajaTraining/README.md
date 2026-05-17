# Paja Training — v1 source

Personal-use iOS app: a periodized strength program (PPL + upper/lower) that adapts
to recovery (Oura + Apple Health) and tells you exactly what to lift today.

Design rationale: `../Paja-Training-App-Design-Review.md`
Build plan: `~/.claude/plans/look-at-paja-training-abundant-aurora.md`

## ⚠️ Build prerequisites (cannot be built on Windows)

This is a native SwiftUI app. To build/run it you need:

- **macOS + Xcode 15+** (iOS 17 SDK)
- An **iPhone** (HealthKit does not work in the Simulator for real data)
- An **Apple Developer account** (HealthKit + iCloud capabilities, on-device install)
- Swift Package dependency: **GRDB.swift** (added in Xcode → Package Dependencies)
- An **Oura Personal Access Token** (oura, developer settings) entered in-app

The Swift source here is portable and complete; it is opened as an Xcode project
on a Mac. Nothing in this folder runs on Windows.

## Structure

```
Sources/
  Data/DB/schema_v1.sql        SQLite schema (GRDB migration v1)
  Data/Models/CoreModels.swift Record types
  Engine/Programs/             PPL + upper/lower template definitions
  Engine/AdaptiveEngine.swift  The deterministic prescription engine (the product)
  Data/Ingestion/              Oura + HealthKit (next)
  Data/Resolve/                resolved-metrics merge layer (next)
  Features/                    SwiftUI screens: Today/Train/Trends/Calibrating (next)
  WatchApp/                    minimal companion (next)
```

## Status

**The logic core ("brain") is complete and reviewable without a Mac:**

- [x] SQLite schema (`schema_v1.sql`)
- [x] Program templates — PPL + Upper/Lower (`ProgramTemplates.swift`)
- [x] Adaptive engine + progression (`AdaptiveEngine.swift`) — the product
- [x] Oura client — token polling, §6 field fixes, revision-aware upsert (`OuraClient.swift`)
- [x] HealthKit reader (`HealthKitReader.swift`)
- [x] Resolved-metrics merge layer + Calibrating gate (`ResolvedMetrics.swift`)

**Remaining — needs a Mac/Xcode to build & verify:**

- [ ] GRDB record types + concrete `DailyLogStore` (persistence wiring)
- [ ] SwiftUI screens (Today / Train / Trends / Calibrating / Onboarding)
- [ ] Apple Watch companion
- [ ] Xcode project + capabilities (HealthKit, iCloud, Background refresh)

The brain (engine + ingestion + merge) is portable Swift and can be unit-tested
off-device. The UI and persistence wiring are best assembled in Xcode on macOS.
