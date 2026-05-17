# Paja Training App — v1 Build Plan

## Context

This supersedes the prior design review (full reasoning lives in `C:\Users\38160\Documents\Paja-Training-App-Design-Review.md`). All shaping decisions are resolved: v1 is a **personal-use, iOS-only, on-device app** whose one differentiator is **a periodized strength program (push/pull/legs + upper/lower) that adapts to recovery and tells the owner exactly what to lift today**. Recovery/sleep is a *bought input* from Oura + Apple Health, not a built feature. The owner wants the adaptation to feel AI-controlled and comprehensive; weekly InBody body-composition is tracked. This plan turns that into an executable build. **No code is written yet — execution is a later step.**

## What v1 delivers (locked)

- 3-screen iOS app: **Today / Train / Trends**, plus a designed **Calibrating** state.
- Adaptive strength engine generating + auto-adjusting PPL and upper/lower programs from recovery + accumulated load.
- Oura (Personal Access Token, polled on-device) + Apple Health, merged "most-data-wins"; missing-data is a designed state, never a fake score.
- Weekly InBody body-composition entry.
- On-device only: SQLite + HealthKit + iCloud sync. **No backend, no OAuth, no webhooks, no AI/LLM in v1** (the conversational AI coach is a deferred phase; v1's "AI" is the deterministic adaptive engine).

## Recommended approach

**Stack:** SwiftUI (iOS 17+), SQLite via **GRDB.swift**, **HealthKit** for Apple Health, **iCloud** (CloudKit private DB or iCloud-synced SQLite file) for cross-device sync, Oura API v2 polled directly with a Personal Access Token stored in **Keychain**. Single-target app, no server.

**Data model** (on-device SQLite — see design-doc Appendix for full columns):
- Training core: `users` (1 seeded row, `user_id` on every table for future multi-user), `exercises`, `program`, `template`/`routine`, `program_instance`, `sessions`, `session_exercises`, `sets`, `goals`/`goal_progress`, `weekly_logs`.
- Ingestion: `connections` (Oura token ref), `daily_logs` (raw, 1/user/day/source, `raw_payload`), **`resolved_daily_metrics`** (per-metric precedence: Oura wins sleep/HRV/readiness; Apple Watch wins workouts/active-energy; most-data-wins when a source is missing; deterministic + rebuildable for late Oura revisions).
- `body_composition` (weekly cadence).
- Deferred (do NOT create in v1): all `coach_*`, `behavior_insights`, `assessments`, `journal_*`, monthly aggregates.

**Adaptive engine (the product):** deterministic rules, not an LLM. Inputs: today's resolved recovery (Oura Readiness when present; labeled lower-confidence Apple-Health fallback otherwise), accumulated weekly load/volume, the active `program_instance` (PPL or upper/lower split). Output: today's concrete prescription (exercises, sets, target load/reps) with a one-line "why". Rule bands: red → cap intensity/volume or swap to recovery; amber → trim back-off sets / cap RPE; green → full or progression. Progression model per template (e.g., load/rep step on success). All thresholds calibrated against the owner's own rolling baseline; no prescription during the Calibrating window.

**Oura integration (corrected per design-doc §6):** poll last ~7–14 days on app-open + iOS background refresh with the Personal Access Token. Take physiology from `sleep` (filter `type`, handle `deleted`, multiple rows/day), one canonical sleep score from `daily_sleep.score`, readiness + contributors + `temperature_deviation` from `daily_readiness`. Handle nullable `score`, `429` backoff, `401`/`403` states. Revision-aware upsert keyed `(user_id, source, date, source_record_id)`, then rebuild `resolved_daily_metrics`.

**Screens (apply the 5 design directions from design-doc):**
- **Today:** one recovery ring, one color (green/amber/red used only for readiness), one action sentence tied to today's actual lift; the adaptive prescription card is the centerpiece.
- **Train:** fast set logging — last-session prefill, +/- steppers, "same as last set", rest timer, plate math. Apple Watch companion (start/stop, log set, glance recovery).
- **Trends:** recovery / sleep / volume / est-1RM / body-composition, 7-30-90 day.
- **Calibrating:** ring outline fills over ~14–21 days ("Day N of 21 — learning your baseline"), no number until baseline.
- Onboarding ≤ 4 screens: paste Oura token → grant Apple Health → pick split (PPL / upper-lower) → set training days.

**Build phases:**
1. App skeleton + data model + manual program logging (PPL + upper/lower templates) + weekly InBody entry + Apple Health read + Trends.
2. Oura token polling + `resolved_daily_metrics` merge + the adaptive prescription engine + the Today/Calibrating moments + iCloud sync.
3. (Deferred) productization: backend, OAuth, webhooks, accounts, GDPR.
4. (Deferred) conversational LLM coach that *explains* program changes — not in v1.

## Critical files/modules to create (greenfield — proposed structure)

- `PajaTraining/App/` — app entry, root `TabView` (Today/Train/Trends).
- `PajaTraining/Data/DB/` — GRDB setup, migrations, `schema_version`; iCloud sync glue.
- `PajaTraining/Data/Models/` — record types for the tables above.
- `PajaTraining/Data/Ingestion/OuraClient.swift` — token polling, field mapping, revision-aware upsert.
- `PajaTraining/Data/Ingestion/HealthKitReader.swift` — Apple Health reads.
- `PajaTraining/Data/Resolve/ResolvedMetrics.swift` — the merge/precedence layer.
- `PajaTraining/Engine/AdaptiveEngine.swift` — the deterministic prescription rules + progression per template.
- `PajaTraining/Engine/Programs/` — PPL + upper/lower template definitions.
- `PajaTraining/Features/Today|Train|Trends|Calibrating|Onboarding/` — SwiftUI screens.
- `PajaTraining/Features/BodyComposition/` — weekly InBody entry + import.
- `PajaTraining/WatchApp/` — minimal companion.

## Assumptions / open items folded in

- **P2 (InBody import path):** v1 = manual weekly entry form + read body-fat%/weight/lean-mass from Apple Health where the InBody app writes them; optional CSV import is a later add. (Owner to confirm if a CSV/file export exists; not a blocker.)
- "AI controls all aspects" is delivered in two layers: the **deterministic adaptive engine in v1** (feels like AI-driven programming), and a **conversational LLM coach later** (deferred — highest cost/risk per the review).
- Exact progression numbers per template (load/rep increments, deload cadence) finalized during Phase 1 against the owner's actual training history.

## Verification (end-to-end, when built)

1. Run on iOS Simulator + a physical iPhone; complete onboarding (token + Apple Health + split + days).
2. **Ingestion:** with a real Oura Personal Access Token, confirm `daily_logs` populates and `resolved_daily_metrics` shows Oura-wins for sleep/HRV and Apple-Watch-wins for a logged workout; force a missing-watch day and confirm graceful labeled state (no fake score).
3. **Calibrating:** fresh install shows the day-counter state, emits no recovery number before baseline.
4. **Adaptive engine:** inject red / amber / green recovery and confirm the Today prescription changes correctly for both a PPL and an upper/lower instance, each with a "why" line.
5. **Train:** log a session via prefill + steppers; confirm sets persist and est-1RM/volume update Trends; verify the Watch companion logs a set.
6. **Body composition:** add a weekly InBody entry; confirm it appears on Trends/weekly and is never demanded daily.
7. **iCloud:** install on a second device, confirm data syncs with no backend.
8. Revision test: re-poll a date Oura has revised; confirm revision-aware upsert updates `resolved_daily_metrics` without duplicates.

*Plan only. Nothing built yet — execution follows approval.*
