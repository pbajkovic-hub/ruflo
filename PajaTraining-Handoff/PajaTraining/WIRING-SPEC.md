# Wiring Spec — contracts the brain expects but does NOT implement

The brain (engine + ingestion + merge) is correct and testable off-device, but
three inputs are *consumed* by it and must be produced by the caller/persistence
layer (built on macOS). This spec defines them so the Mac developer wires them
correctly. It also records two signature/behaviour changes made during the
correctness pass.

## 1. Deload trigger (feeds `AdaptiveEngine.prescribe(isDeloadWeek:)`)

The engine only *responds* to `isDeloadWeek`; nothing computes it. Rule:

```
isDeloadWeek = (program_instance.week_in_block % template.deloadEveryNWeeks == 0)
```

`program_instance.week_in_block` increments by 1 each time a full split rotation
completes (rotation_index wraps to 0). `deloadEveryNWeeks` is on the template
(`ppl.v1` = 4, `ul.v1` = 5). Reset `week_in_block` to 1 after a deload week
completes.

## 2. `priorBasisDays` (feeds `ResolvedMetricsBuilder.resolve`)

The Calibrating gate is entirely driven by this. Definition:

> the count of **distinct prior `log_date`s** (strictly before `date`) whose
> `resolved_daily_metrics.recovery_pct IS NOT NULL` **or** that had a usable
> recovery basis (Oura readiness present, or Apple HRV+RHR present with a valid
> baseline).

Compute it from `resolved_daily_metrics` before calling `resolve(date:…)`. The
gate shows Calibrating until `priorBasisDays >= ResolvedMetricsBuilder.calibrationDays` (14).
Never count days with no source data.

## 3. Timezone / day-boundary policy

`users.timezone` exists but nothing applies it. Policy (matches Oura):

- **The Oura `day` field owns the day** for Oura-sourced rows — store it
  verbatim, do not re-bucket.
- For Apple Health, the caller passes `[dayStart, dayEnd)` to
  `HealthKitReader.dailyLog` computed in `users.timezone` (local calendar day;
  period-end owns the day). Sleep is queried from `dayStart − 12h` to capture
  the prior night — accept the documented overlap; do not double-count by also
  attributing it to the previous day.
- `resolved_daily_metrics.log_date` is the local calendar date in
  `users.timezone`.

## 4. Signature change — `ProgressionEngine.next`

Added `highConfidence: Bool` (the green came from **Oura Readiness**, not the
low-confidence Apple-Health estimate). Call site must pass
`highConfidence = (resolvedDaily.confidence == .high)`. Working weight is never
bumped off an estimated green.

## 5. Screen-layer notes (not blocking the brain)

- Bodyweight slots have `intensityPct == 0.0` → engine prescribes `kg == 0`.
  Render this as **"bodyweight"**, not "0 kg".
- Oura ISO-8601 timestamps are compared lexically for the revision max
  (`Swift.max`). Oura returns a consistent offset per collection so this is
  safe for revision detection; if a mixed-offset case ever appears the worst
  case is one extra harmless upsert. Normalise to UTC if you want strictness.
- P2 (InBody via Apple Health): only `weight / body-fat % / lean mass / BMI`
  come from HealthKit. `skeletal_muscle_mass_kg`, `visceral_fat_level`,
  `total_body_water_l`, `bmr_kcal`, `inbody_score`, `segmental_lean_json`
  have no standard HealthKit type — leave NULL; a manual supplement form is a
  post-v1 add, not blocking.
