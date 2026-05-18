# Paja Training App — Design Review & Revised Direction

**Status:** Standalone decision document. Supersedes the earlier draft at `~/.claude/plans/look-at-paja-training-abundant-aurora.md`.
**Date:** 2026-05-17 — **D1/D3/D5 resolved; v1 is personal-use, Apple-only.**
**Audience:** The product owner (plain-language sections) + the engineer who will build it (sections marked *For the developer*).
**Basis:** A four-angle critical review (Oura API audit, competitive benchmark, product/UX critique, architecture critique), grounded in the official Oura API v2 spec.

### Resolved decisions (2026-05-17)
- **Scope:** personal use for now (one person — the owner), structured so it can grow later.
- **D1 — Programs:** 2–3 proven program templates + the adaptive recovery layer (no custom builder in v1). Exact templates TBD by what the owner trains.
- **D3 — Nutrition:** out of v1; added later via the Apple Health bridge.
- **D5 — Wearables:** **WHOOP dropped.** Sources = **Oura + Apple Health, per-metric "most-data-wins."** Owner has an Apple Watch but sometimes forgets it, so Oura (finger-worn, more consistent) is the primary recovery source; Apple Health fills gaps; missing-data is a designed state, never a fake score.
- **NEW — Body composition:** weekly **InBody-style body-composition** entry (body fat %, muscle mass, etc.), imported/downloaded, **weekly cadence, not daily**.
- **Recovery number:** for personal v1, Oura's validated Readiness/Sleep scores are used directly when present; Apple Health raw signals are the fallback with a clearly-labeled lower-confidence "recovery trend" + calibration period.

---

## 1. Executive verdict

**The original "WHOOP-clone database" framing should not be built.** Recovery/strain/sleep is commodity (Oura/Athlytic already nail it). The design also reimplemented large parts of what the Oura API gives free, and it was a *database, not a product*. The direction is now locked to the one thing worth building (below). Engineering risk ≈ zero; product/positioning risk is what this doc manages.

## 2. The product worth building

Every competitor leaves the same gap: recovery apps treat strength training as a "strain" blob; lifting loggers have zero recovery awareness; Fitbod ignores HRV/sleep. **Nobody joins periodized strength programming with recovery in one adaptive loop.**

**Positioning (one sentence):**
> *"The only training app where your periodized strength program adapts to your recovery — and tells you exactly what to lift today, not just whether to rest."*

Recovery/strain/sleep is a **bought input** (Oura + Apple Health), not a marketed feature. The differentiator is the **adaptive strength engine**.

## 3. Buy, don't build — the Oura "delete list"

*For the developer.* Oura API v2 already provides these — consume, don't reimplement:

| Originally designed to build | Use this Oura endpoint instead |
|---|---|
| "Sleep Coach" / recommended bedtime | `sleep_time` (also returns `not_enough_nights` → solves cold-start) |
| Behavior journal tables | `enhanced_tag` |
| Deload / recovery-first inputs | `rest_mode_period`, `daily_resilience`, `daily_stress` |
| Recovery score from scratch | `daily_readiness.score` + contributors |
| Custom HRV computation | `sleep.average_hrv` + `sleep.hrv` series |
| Cardio-fitness baselines | `vO2_max`, `daily_cardiovascular_age` |

## 4. v1 scope

### In scope
1. **Adaptive strength engine** — periodized program; each day outputs a concrete prescription adjusted by recovery + accumulated load. *The product.*
2. **The daily loop:**
   - **Morning:** one screen, one recovery number, one color, one action sentence tied to *today's actual lift*.
   - **Train:** fast set logging — last-session prefill, +/- steppers, "same as last set", rest timer, plate math. Apple Watch companion (start/stop, log a set, glance recovery) — phones live in lockers.
   - **Evening:** wind-down nudge from Oura `sleep_time` (don't compute it).
3. **Onboarding + calibration mode** — first ~14–21 days show "Calibrating — day N of 21", **never a fake score**. Onboarding ≤ 4 screens (connect Oura, connect Apple Health, pick a goal, set training days).
4. **One trends screen** — recovery / sleep / strength volume / est. 1RM, 7/30/90-day.
5. **Weekly body composition (InBody)** — *new.* A weekly entry of body-composition metrics (weight, body-fat %, skeletal-muscle mass, etc.), imported from the owner's InBody download/export or read from Apple Health where available. Surfaced on the weekly view + Trends. **Weekly cadence — explicitly not a daily metric.**
6. **Notification strategy** — one guaranteed daily push (morning recovery + action), one conditional evening push. Nothing else by default.
7. **Information architecture** — three tabs: **Today / Train / Trends.** Settings/connections behind an avatar. Raw physiology (HRV ms by stage, per-zone strain) hidden — it's plumbing.

### Explicitly NOT in v1
Recovery/strain/sleep as marketed features; the AI coach; the 7 `coach_*` tables / `behavior_insights` / `assessments`; a Postgres backend / server stack; multi-user accounts/billing; **WHOOP integration**; anything in the §3 delete list; nutrition.

## 5. Architecture — cheapest correct personal v1

*For the developer.*

**Topology:** **on-device only.** iOS-native app + **SQLite** as system of record + **HealthKit** + **iCloud** to sync across the owner's iPhone/Watch. **No backend, no serverless function, no Postgres** for personal use.

- **Oura:** for one's own data, Oura supports a **Personal Access Token** (generated in Oura's developer settings — confirm). The app polls the Oura API directly from the device with that token on app-open + iOS background refresh. **No OAuth flow, no webhooks, no callback server needed for personal v1.** (OAuth + webhooks + a thin serverless callback are *productization* concerns, deferred.)
- **Apple Health:** on-device HealthKit read; the only place watch/nutrition/body data is read.
- **Rewrite-proofing (do anyway, cheap):** `user_id` on every table (one seeded row); store the Oura token in the iOS Keychain via a single `connections` record, never hard-coded; a **`resolved_daily_metrics`** layer with explicit per-metric precedence — **Oura wins sleep/HRV/readiness; Apple Watch wins workouts/active-energy; "most-data-wins" when one source is missing that day.** Deterministic and rebuildable (Oura revises records late).

## 6. Oura integration — corrected spec (personal v1)

*For the developer.*

**Ingestion:** poll with a Personal Access Token (webhook-primary is deferred to productization). Poll last ~7–14 days on app-open + background refresh; `next_token`-paginate; back off on `429`.

**Field-mapping fixes (still apply):**
- `daily_sleep` has **no physiology** — only a score + contributors. Real sleep data is in `sleep` (`PublicModifiedSleepModel`). *(This is the "sleep score appears twice" redundancy the owner spotted — keep one canonical score from `daily_sleep.score`, take physiology from `sleep`, delete any self-computed `sleep_performance_pct`.)*
- `score` is **nullable / not required** — handle null; no NOT NULL column.
- `sleep` returns **multiple rows/day** (`type` ∈ sleep/long_sleep/late_nap/rest/deleted) — filter `type`, handle `deleted`.
- `heartrate` has **no HRV**; its `average_heart_rate` differs from the Oura app's number — don't surface raw.
- Use `daily_readiness` **contributors** (+ `temperature_deviation`) for the deload decision, not just the score.
- Error states: `401` → re-enter token; `403` → "Oura membership lapsed" state; `429` → backoff.
- **Revision-aware upsert:** key `(user_id, source, date, source_record_id)`, last-write-wins, store source version, rebuild `resolved_daily_metrics` for that date.

## Design directions (v1 look & feel)

From current WHOOP/Oura/fitness-app design research. Visual references are linked so they can be opened directly.

1. **"One big thing" Today screen** — one full-screen recovery ring, one color, one number, one action sentence tied to today's lift; nothing else above the fold. *Ref:* Oura new Today tab; new WHOOP home screen.
2. **One three-color vocabulary everywhere** — green = ready, amber = middle, red = strain/risk; used *only* for readiness state, on every screen, never decoratively. *Ref:* WHOOP design breakdown (925studios).
3. **The adaptive "today's prescription" card** — the differentiator made visual: *"Recovery 58% → 5/3/1 squat, work sets capped 80%, back-off dropped"* + one-line why. The centerpiece, not buried. *Ref:* Freeletics-style instant day-adjust (Stormotion).
4. **Three-tier progressive disclosure** — glance (number) → tap (today's adjusted program + reason) → deep dive (biometrics, hidden behind "advanced"). Three tabs only. *Ref:* Mobbin Health/Fitness; Dribbble fitness UI.
5. **Designed "Calibrating" state** — a ring outline that fills as days accrue ("Day 6 of 21 — learning your baseline"); no number until baseline. *Ref:* Oura new app design; DesignRush health/wellness.

Reference links: WHOOP home screen `whoop.com/us/en/thelocker/the-all-new-whoop-home-screen/` · WHOOP breakdown `925studios.co/blog/whoop-design-breakdown` · Oura new app `ouraring.com/blog/new-oura-app-experience/` & `/blog/new-app-design/` · Stormotion `stormotion.io/blog/fitness-app-ux/` · Mobbin `mobbin.com/explore/mobile/app-categories/health-fitness` · Dribbble `dribbble.com/tags/fitness-app-ui` · DesignRush `designrush.com/best-designs/apps/health-wellness`.

## 7. Critical findings log (current)

### 🔴 Resolve before building
1. **Product not designed** — the daily loop, calibration, set-logging UX, notifications are still undefined (§4). This is the real work.
2. **No multi-source merge rule** — `resolved_daily_metrics` with per-metric precedence + "most-data-wins" is required for correctness (§5).
3. **Revision-aware ingestion** — naive unique-key upsert corrupts on Oura revisions (§6).

### 🟠 Important
4. **No program/template entity** — add `program` / `template` / `program_instance`. Core domain miss.
5. Soft-delete + audit on `sessions`/`sets` (irreplaceable history).
6. Timezone/day-boundary policy (period-end owns the day, matches Oura).
7. InBody import format must be confirmed (CSV export vs. Apple Health vs. manual entry).

### 🟡 Minor (defer)
Park all `coach_*`, `behavior_insights`, `assessments`. `raw_payload` retention policy. Streaks mechanic post-v1.

## 8. Open decisions

| # | Decision | Status |
|---|----------|--------|
| Scope / D1 / D3 / D5 | — | ✅ Resolved 2026-05-17 (see top) |
| P1 | Which exact 2–3 program templates? | Open — depends on what the owner trains (5/3/1? linear? PPL?) |
| P2 | InBody data path: CSV export, Apple Health, or manual weekly entry? | Open — affects the body-composition importer |
| D2 | Pricing / free vs paid | Deferred to productization |
| D4 | GDPR / legal entity / consent | Deferred to productization (no backend = minimal surface now) |

## 9. Recommended next steps

1. Answer **P1** (which programs you train) and **P2** (how InBody data comes out).
2. **Design the product before more schema:** wireframe the three moments (morning / train / evening), the Calibrating state, and the set-logging interaction, using the 5 design directions above.
3. Phased build: (1) on-device app + Apple Health + manual program logging + weekly InBody entry; (2) Oura personal-token polling + `resolved_daily_metrics` + adaptive prescription; (3) productization later (backend, OAuth, webhooks, accounts, compliance); (4) AI coach (explains program changes only).

## Appendix — data model guidance

- **Keep:** `goals`/`goal_progress`, `sessions`/`session_exercises`/`sets`, `exercises`, `daily_logs` (raw, 1/user/day/source, `raw_payload`), `weekly_logs`.
- **Add (core):** `program`, `template`/`routine`, `program_instance`; `resolved_daily_metrics` (merge layer, per-metric precedence + most-data-wins); `users`; `connections` (Oura token in Keychain).
- **Add (new):** `body_composition` — `id, user_id, measured_on (date), source ('inbody_csv'|'inbody_manual'|'apple_health'|'manual'), weight_kg, body_fat_pct, skeletal_muscle_mass_kg, lean_body_mass_kg, total_body_water_l, visceral_fat_level, bmr_kcal, bmi, inbody_score, segmental_lean (json), raw_payload, notes, created_at`. **Weekly cadence**; surfaced on Trends + `weekly_logs`; never required daily.
- **Defer (out of v1):** all 7 `coach_*`, `behavior_insights`, `assessments`, `journal_*` (use Oura `enhanced_tag` later), `health_baselines`/`health_alerts`, monthly aggregates, OAuth/webhook infrastructure.
- **Drop for v1:** the Postgres dialect — ship the on-device SQLite schema only until productization.

*End of document.*
