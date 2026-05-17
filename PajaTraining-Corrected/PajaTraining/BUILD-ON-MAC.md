# BUILD-ON-MAC — cold-start runbook to get Paja Training v1 on the iPhone

**Audience:** a Claude Code session running on a **Mac** (or an iOS developer).
You are picking this up cold. The "brain" in `Sources/` is **complete,
corrected and unit-tested off-device** — do **not** rewrite it. Your job is
the iOS shell *around* it: Xcode project, persistence, the 3 wiring contracts,
the SwiftUI screens, then install on the owner's iPhone.

**Before you start, read in this order:** `README.md` → `../00-DESIGN-REVIEW.md`
(esp. §4 scope, §design-directions) → `../01-BUILD-PLAN.md` → `WIRING-SPEC.md`
→ `Sources/Data/DB/schema_v1.sql` → `Tests/BrainTests.swift`. Treat
`OWNER-CHECKLIST.md` (handoff root) as the list of things only the owner
supplies (Oura token, program numbers) — don't block on them; stub and move on.

**Hard rules**
- The deterministic engine is the product. No LLM in v1 (design Phase 4).
- `Sources/Engine/*`, `Sources/Data/Ingestion/*`, `Sources/Data/Resolve/*`,
  `Sources/Data/DB/schema_v1.sql` are **frozen contracts** — consume them as
  written. If you believe one is wrong, stop and surface it, don't silently
  change it (they were corrected in a dedicated pass; `Tests/BrainTests.swift`
  pins the five fixes).
- The shipped web oracle `training-app/src/lib/paja.ts` (TypeScript, in the
  separate `claude projects` repo) is the **behavioral reference**. When in
  doubt about engine behavior, match it. It is the Step 8 parity target.

The web "Oura-style screen" reference is a separate, design-gated follow-up;
its absence does **not** block this runbook. Build the screens from the
§design-directions spec in `00-DESIGN-REVIEW.md` plus Step 5 below.

---

## Step 0 — Prerequisites (owner clears these — see OWNER-CHECKLIST.md)

macOS + Xcode 15+ (iOS 17 SDK) · a real iPhone · an Apple ID for signing
(free personal team is enough for personal use — 7-day re-sign; $99/yr Apple
Developer only if reliable Background refresh / iCloud is wanted) · an Oura
Personal Access Token · confirmation of the owner's real working weights (P1).
Verify Xcode is present: `xcodebuild -version`. If absent, stop and report.

## Step 1 — Xcode project + capabilities

Create a single-target SwiftUI app, then **add the existing `Sources/` files to
the target** (do not recreate them):

- App name `PajaTraining`, bundle id e.g. `com.<owner>.pajatraining`,
  **iOS 17.0** deployment target, SwiftUI lifecycle (`@main` App + `WindowGroup`).
- Generate the project so the engine files are reproducibly included — prefer a
  checked-in **`project.yml` (XcodeGen)** or **Swift Package + thin app target**;
  if you hand-create the `.xcodeproj`, commit it.
- Add Swift Package dependency **GRDB.swift** (`https://github.com/groue/GRDB.swift`).
- Capabilities / entitlements:
  - **HealthKit** (entitlement `com.apple.developer.healthkit`); Info.plist
    `NSHealthShareUsageDescription` (read-only — the reader requests no share
    types). No `NSHealthUpdateUsageDescription` needed.
  - **iCloud** — pick ONE sync mechanism and configure it:
    `com.apple.developer.icloud-container-identifiers` + an iCloud-synced
    SQLite file in the app's iCloud container **or** CloudKit private DB
    mirroring. (Design intent: cross-device, no backend. iCloud-synced GRDB
    file is the lower-risk path for v1.)
  - **Background Modes → Background fetch / Background processing** (for the
    Oura poll on app-open + background refresh). Add `BGTaskScheduler` task id.
- Bundle `Sources/Data/DB/schema_v1.sql` as a resource in the app target.
- Build empty shell to green before proceeding: `xcodebuild -scheme PajaTraining
  -destination 'generic/platform=iOS' build`.

## Step 2 — GRDB models + migration (one per `schema_v1.sql` table)

Create `Sources/Data/Models/` record types — each `Codable`,
`FetchableRecord`, `PersistableRecord`, `databaseTableName` matching the SQL.
**One model per table — all of these, none skipped:**

| Table | Model | Notes |
|-------|-------|-------|
| `users` | `UserRecord` | seed exactly one row (UUID, `display_name`, `timezone`, `created_at`) on first launch |
| `connections` | `ConnectionRecord` | `provider`/`status`/`keychain_ref`; `UNIQUE(user_id,provider)` |
| `exercises` | `ExerciseRecord` | built-ins have `user_id = NULL`; respect `ux_exercises_builtin_name` (insert built-ins idempotently by name) |
| `program` | `ProgramRecord` | `split` ∈ `ppl`/`upper_lower`, `template_key` = `ppl.v1`/`ul.v1` |
| `program_instance` | `ProgramInstanceRecord` | holds `rotation_index`, `week_in_block` — Step 4 mutates these |
| `lift_progress` | `LiftProgressRecord` | `(user_id,exercise_id)` unique; `working_kg`,`target_reps`,`last_outcome` |
| `sessions` | `SessionRecord` | soft-delete via `deleted_at`; never hard-delete |
| `session_exercises` | `SessionExerciseRecord` | order via `order_index` |
| `sets` | `SetRecord` | target vs done reps/kg, `is_warmup`,`is_backoff`,`completed` |
| `goals` | `GoalRecord` | |
| `goal_progress` | `GoalProgressRecord` | |
| `weekly_logs` | `WeeklyLogRecord` | `UNIQUE(user_id,week_start_date)` (Monday local) |
| `daily_logs` | `DailyLogRecord` | raw, `UNIQUE(user_id,log_date,source)`; `raw_payload` kept verbatim |
| `resolved_daily_metrics` | `ResolvedDailyRecord` | PK `(user_id,log_date)`; rebuilt by Step 4 |
| `body_composition` | `BodyCompositionRecord` | weekly; HealthKit fills only weight/body-fat/lean/BMI, rest NULL |
| `schema_version` | (migration bookkeeping) | use GRDB `DatabaseMigrator` registering migration **"v1"** that executes `schema_v1.sql` verbatim |

- DB access via GRDB `DatabasePool`; store the file in the iCloud container
  chosen in Step 1. Run the migrator at launch; assert
  `SELECT version FROM schema_version` == 1.
- Seed: the single `users` row + the built-in `exercises` (every distinct slot
  name across `Sources/Engine/Programs/ProgramTemplates.swift`, `user_id NULL`,
  `is_main_lift` per the slot, category per the slot).

## Step 3 — Persistence + secrets (implement the frozen protocols)

The engine consumes abstractions you must satisfy with GRDB:

- **`DailyLogStore`** (defined in `Sources/Data/Ingestion/OuraClient.swift`):
  implement a GRDB-backed conformer.
  - `existingOura(date:) -> (recordId:String?, updatedAt:String?)?` → query
    `daily_logs WHERE log_date=? AND source='oura'`, return
    `(source_record_id, source_updated_at)` or nil.
  - `upsertOura(_ log: OuraDailyLog)` → upsert the `daily_logs` row
    (`source='oura'`), mapping every `OuraDailyLog` field 1:1
    (`readinessScore→readiness_score`, … , `rawPayload→raw_payload`,
    `sourceUpdatedAt→source_updated_at`). Last-write-wins is already enforced
    upstream in `OuraClient.sync`; just persist. After an Oura upsert, mark the
    day dirty so Step 4 rebuilds `resolved_daily_metrics`.
- **Keychain wrapper**: store the Oura Personal Access Token in the iOS
  Keychain (not SQLite — schema comment line 15 is explicit). Write a
  `connections` row (`provider='oura'`, `keychain_ref`=the account key,
  `status='connected'`). Map `OuraError.tokenInvalid → status='token_invalid'`,
  `.membershipLapsed → 'membership_lapsed'`; surface both as Onboarding/Today
  re-auth states. Construct `OuraClient(token:store:)` with the token read from
  Keychain.
- **Apple Health persistence**: call `HealthKitReader.dailyLog(...)` →
  `AppleHealthDailyLog` → upsert a `daily_logs` row with `source='apple_health'`
  (same table, the other half of the `UNIQUE(user_id,log_date,source)` pair).
  `HealthKitReader.bodyComposition(...)` → upsert `body_composition`
  (`source='apple_health'`; skeletal-muscle/visceral/TBW/BMR/InBody/segmental
  stay NULL — that's expected per `WIRING-SPEC.md` §5).

## Step 4 — Implement the 3 wiring contracts (`WIRING-SPEC.md` §1–3)

These are *consumed* by the frozen engine but **not implemented** anywhere.
Implement each in the persistence/coordinator layer, exactly per the spec:

1. **Deload trigger → `AdaptiveEngine.prescribe(isDeloadWeek:)`**
   `isDeloadWeek = (program_instance.week_in_block % template.deloadEveryNWeeks == 0)`.
   `template.deloadEveryNWeeks`: `ppl.v1`=4, `ul.v1`=5 (from
   `ProgramTemplates.swift`). Increment `week_in_block` by 1 each time a full
   split rotation completes (`rotation_index` wraps to 0); reset `week_in_block`
   to 1 after a deload week completes. Persist on `program_instance`.
2. **`priorBasisDays` → `ResolvedMetricsBuilder.resolve(priorBasisDays:)`**
   Count distinct prior `log_date`s (strictly before the target date) where
   `resolved_daily_metrics.recovery_pct IS NOT NULL` **or** a usable basis
   existed (Oura readiness present, or Apple HRV+RHR present with a valid
   baseline). Never count no-data days. The Calibrating gate holds until
   `priorBasisDays >= ResolvedMetricsBuilder.calibrationDays` (**14**).
3. **Timezone / day-boundary policy**
   Oura `day` owns the day for Oura rows — store verbatim, never re-bucket.
   For Apple Health, compute `[dayStart, dayEnd)` in `users.timezone` (local
   calendar day, period-end owns the day) and pass to
   `HealthKitReader.dailyLog`. Sleep is queried from `dayStart − 12h` inside the
   reader — accept the documented overlap, do **not** also attribute it to the
   previous day. `resolved_daily_metrics.log_date` = local date in
   `users.timezone`.

**Resolve coordinator** (the glue Step 4 produces): for a date, gather the
`daily_logs` rows (oura + apple_health) → `[RawDay]`; compute the trailing
baseline via `ResolvedMetricsBuilder.baseline(from: last ~30 ResolvedDaily)`;
compute `priorBasisDays`; call `resolve(...)`; persist `ResolvedDaily` →
`resolved_daily_metrics`. Rebuild the day whenever `OuraClient` upserts a
revision (revision-aware upsert is already correct in `OuraClient`).

## Step 5 — SwiftUI screens (`Sources/Features/`)

Apply the **5 design directions** verbatim from `00-DESIGN-REVIEW.md`
§design-directions (3-color vocabulary used *only* for readiness; "one big
thing" Today; prescription card is the centerpiece; 3-tier progressive
disclosure; designed Calibrating). Three tabs only (Today / Train / Trends),
settings behind an avatar. Build **every** screen below:

- **Onboarding** (`Features/Onboarding/`, ≤4 screens): paste Oura token →
  grant Apple Health (`HealthKitReader.requestAuthorization()`) → pick split
  (PPL / Upper-Lower) → set training days. Creates `connections`, `program`
  (`template_key`), `program_instance` (rotation 0, week_in_block 1), and
  captures starting working weights into `lift_progress` (use the owner's
  confirmed P1 numbers; until confirmed, a "enter your working weight" capture
  on first occurrence of each lift — never invent loads).
- **Today** (`Features/Today/`): build `RecoveryInput` from the day's
  `ResolvedDaily` (`state`,`pct`,`confidence`); pick
  `TemplateDay = template.rotation[program_instance.rotation_index % rotation.count]`;
  build the `[String: WorkingSet]` table from `lift_progress` joined to
  `exercises.name`; compute `isDeloadWeek` (Step 4 §1); call
  `AdaptiveEngine().prescribe(...)`. Render: one recovery ring, one color, one
  number, the `PrescribedSession.why` sentence, the **adaptive prescription
  card** (exercises → sets → reps → kg). Render a slot whose `kg == 0`
  (bodyweight, e.g. Hanging Leg Raise `intensityPct 0.0`) as **"bodyweight"**,
  not "0 kg" (`WIRING-SPEC.md` §5). Tap → adjusted-program detail; biometrics
  behind "advanced".
- **Calibrating** (`Features/Calibrating/` or a Today state): when
  `recoveryState == .calibrating`, show a ring **outline that fills with
  progress**, no number, copy "learning your baseline — day N". Gate unlocks at
  `priorBasisDays >= 14`. NOTE: design copy says "Day N of 21" but the code gate
  is **14** — show progress toward 14 and flag this number to the owner as a
  one-line decision (keep 14, or change `calibrationDays`); do not silently
  diverge from the engine constant.
- **Train** (`Features/Train/`): fast set logging — last-session prefill (from
  prior `sets`), +/- steppers, "same as last set", rest timer, plate math.
  Persist `sessions` → `session_exercises` → `sets`. On completion: set
  `sessions.recovery_state/recovery_pct/prescription_why`, set
  `lift_progress.last_outcome` (`hit`/`missed`/`skipped`), then for each lift
  call `ProgressionEngine().next(working:lastOutcome:wasGreen:highConfidence:isMainLift:)`
  — `wasGreen = (resolved.recoveryState == .green)`,
  `highConfidence = (resolved.confidence == .high)` — and write the returned
  `workingKg` back to `lift_progress`. Then advance `program_instance.rotation_index`
  (Step 4 §1 increments `week_in_block` on wrap).
- **Trends** (`Features/Trends/`): recovery / sleep / strength volume / est.
  1RM / body-composition over 7-30-90 days, from `resolved_daily_metrics`,
  `sets`, `weekly_logs`, `body_composition`. Body composition is weekly — never
  demand it daily.

Apple Watch companion is **deferred post-v1** (`README.md`) — do not build it
in v1; leave `Sources/WatchApp/` unbuilt.

## Step 6 — Wire brain → UI (coordinator)

One coordinator/service object owns the flow:
poll Oura (`OuraClient.sync(from:to:)`, last ~7–14 days, on app-open +
`BGTaskScheduler`) → `HealthKitReader.dailyLog/bodyComposition` →
`daily_logs` → **Step 4 resolve coordinator** → `resolved_daily_metrics` →
Today builds `RecoveryInput` + working table → `AdaptiveEngine.prescribe` →
Today UI; Train completion → `ProgressionEngine.next` → `lift_progress` +
rotation advance. Keep the engine pure (no I/O inside `Sources/Engine`).

## Step 7 — Install on the owner's iPhone

- Set the signing team (free personal team OK for personal use — note the
  **7-day** re-sign limit; $99/yr removes it and makes Background/iCloud
  reliable). Set a unique bundle id.
- `xcodebuild ... -destination 'platform=iOS,name=<device>'` or run from Xcode
  onto the connected iPhone. Trust the developer profile on the device.
- Launch → complete Onboarding (enter the real Oura PAT, grant HealthKit, pick
  split, set days). Confirm a real Oura poll populates `daily_logs` and
  `resolved_daily_metrics`.

## Step 8 — Acceptance (must pass before "it's on the phone")

1. **Port `Tests/BrainTests.swift`** into the Xcode unit-test target; `xcodebuild
   test` green (it pins: revision rebuild on sleep-only revision; Oura bands at
   69/70/84/85; no progression on estimated green; Calibrating gate day 13 vs
   14).
2. **Parity gate vs the web oracle `training-app/src/lib/paja.ts`** — same
   inputs, same outputs:
   - Real Oura readiness **71 → amber** (progression held), not green.
   - `priorBasisDays < 14` → **Calibrating**, no number emitted.
   - A `hit` on a **low-confidence (estimated) green** does **not** bump
     `working_kg`; a `hit` on an Oura (high-confidence) green bumps by 2.5 kg
     (main) / 1.25 kg (accessory).
   - Bodyweight slot renders **"bodyweight"**, not "0 kg".
3. **Device smoke** (`01-BUILD-PLAN.md` §Verification): onboarding; Oura-wins
   vs Apple-Watch-wins precedence on `resolved_daily_metrics`; forced
   missing-watch day → labeled state, no fake score; inject red/amber/green →
   Today prescription changes correctly with a "why" for **both** PPL and
   Upper/Lower; log a session via prefill+steppers, est-1RM/volume update
   Trends; add a weekly InBody entry; revision re-poll updates without
   duplicates; iCloud sync to a second device with no backend.

Report any engine behavior that cannot be matched to the oracle as a finding —
do not patch `Sources/Engine` to make a test pass.

---

### Build order summary (one pass)
0 prereqs → 1 Xcode shell green → 2 GRDB models + migration → 3 DailyLogStore +
Keychain + HealthKit persistence → 4 the 3 wiring contracts + resolve
coordinator → 5 screens (Onboarding, Today, Calibrating, Train, Trends) →
6 coordinator wiring → 7 install on iPhone → 8 tests + oracle parity + device
smoke. Then it is on the phone.
