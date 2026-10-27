# Returning-user re-entry — research findings (2026-09-10)

**Why this exists:** founder asked how other workout apps handle a user who completes a phase,
disappears for weeks, then returns — and what we should do. Two research passes; this is the
durable record so the question is not re-researched.

⚠️ **Provenance and trust.** Gathered by a research subagent with web access. Per
`feedback_audit_verifier_cannot_trust_own_subagent.md` every external citation here is a
**HYPOTHESIS until independently read**. The agent graded its own evidence (documented / reported /
inferred / none) and self-corrected twice — including reporting *"no good evidence found"* on a
question where a 103-study meta-analysis existed it had not reached. Treat unverified rows
accordingly. Nothing here has been checked against the primary papers by the main thread.

⚠️ **Do NOT cite the "88% of lapsed fitness-app users feel shame — UCL 2025" statistic.** The agent
read the Wiley press release directly and confirmed **no such figure appears**. It circulates
online. It is not in the study.

---

## 1. The category finding

**Of 21 apps checked, exactly ONE — StrongLifts — has a documented automatic return-after-absence
load adjustment.** Two hand the decision to the user (Freeletics, RP Hypertrophy), one prevents the
failure state structurally (Apple's 90-day ring pause), one diagnoses without prescribing (Garmin),
and the rest do nothing.

Shipping this well puts us ahead of the category rather than catching up.

| App | On return (2-12wk) | Evidence |
|---|---|---|
| **StrongLifts** | Detects ≥1 week idle → "Welcome Back" card, deload button, recommended % with an **adjustable slider**, and *"you can simply ignore the card"* | DOCUMENTED, agent read it directly |
| Freeletics | 10d-1mo → offers easier session; **>1mo → offers a CHOICE** between easier and originally planned | DOCUMENTED (snippet — Zendesk 403) |
| RP Hypertrophy | Manual: *"Plan a new mesocycle"*. No auto-detection found. **Closest structural analogue to our 4-week phase** | DOCUMENTED (snippet — 403) |
| Apple Fitness | Pre-declared pause up to 90 days, streak intact. Asks no reason | DOCUMENTED, read directly |
| Garmin | Labels *"You've taken an extended break, and your fitness level is decreasing"* — **offers no action** | DOCUMENTED, read directly |
| Centr | "Centr Begin" — user must self-select | DOCUMENTED |
| Strava | Weekly streak, **no grace period**; only repairable by uploading the real missed activity | DOCUMENTED |
| Fitbod | ⚠️ **CONTESTED** — two extractions of the same bot-blocked page disagree on auto vs manual | UNRESOLVED |
| JEFIT | Its own Load Progression Engine explainer is **entirely silent** on gaps | DOCUMENTED ABSENCE |
| Juggernaut AI, Alpha Progression, Caliber, Future, Tempo, Peloton, Nike TC, Oura, Hevy, Strong, Boostcamp, Whoop | **No evidence found** (several searched hard; Strong inferred date-agnostic by architecture) | none |

⚠️ Two systematic limits: three help centres are Zendesk-hosted and 403 direct fetch, and **Reddit
was not fetchable at all**, so user-report evidence is thin throughout.

## 2. The reframe that changes the feature

**The evidence-backed risk on return is INJURY, not lost gains.** CSCCa/NSCA consensus cites NCCSIR
data that *"almost 60% of non-contact injuries occur during these periods in which the athlete is
transitioning back into training following a period of inactivity."*

So a re-entry block is **safety and load recalibration**, not "you lost your gains." That framing is
true, flattering, and sidesteps the shame trigger — which matters (see §4).

**Corollary, and it contradicts the obvious move:** do NOT justify the ramp as "they need a deload."
They have effectively had one. Coleman et al. (2024) found an *unnecessary* 1-week deload in trained
lifters *"appears to negatively influence measures of lower body muscle strength."*

## 3. Detraining is slower than intuition says

- Bickel et al. (2011): strength *"largely retained… with only a slight reduction at the final time
  point"* after **32 weeks** of complete cessation.
- Halonen et al. (2024): untrained adults **aged 32±5 — our exact demographic** — took a 10-week
  mid-programme break and **regained pre-break level in 5 weeks**, with no final difference vs
  continuous training.
- Bosquet et al. 2013 meta-analysis (103 of 284 studies): work capacity decays worst
  (**SMD −0.62**), maximal force −0.46, **peak power best retained at −0.20**. Dose-response with
  duration. **Effect LARGER in inactive people than recreational athletes.**
- Bjørnsen 2019 @ 20wk: muscle size back to baseline, **~60% of the strength gain retained**.
- Kubo 2012 (n=9, one tendon, isometric): tendon stiffness took **3 months to build, 1 month to
  lose** — the inverse of muscle. ⚠️ Thin, but the only direct human time-course data found.

**Three consequences:**
1. **Beginners lose MORE, not less** — reverses the usual reasoning. Be more conservative with them.
2. **Work capacity is what they'll actually notice** — sets feeling harder, not top-end strength
   gone. Say that in copy; it pre-empts the misread that makes people quit again.
3. **Gate the ramp on ELAPSED TIME, not week-1 performance.** Neural strength returns before tendon
   stiffness does; a strong first session is not evidence of readiness.

## 4. The welcome-back moment

**The one rigorous finding.** Silverman & Barasch (2023), *J Consumer Research* 49(6):1095-1117,
seven studies: a broken streak's demotivating effect is **amplified when users blame themselves**
and **attenuated when the streak can be "repaired."** Peer-reviewed support for forgive-over-reset,
and for supplying an external attribution ("travelling / injured / busy").

**Calibrate the ceremony down.** Duolingo's published data: ~**5%** of users resurrect after 30+
days, and they retain **~20% worse than brand-new users**. A warm card and a good first session
beats an elaborate re-onboarding flow.

**Anti-patterns:** Garmin's label-without-action. Duolingo's guilt copy (*"You made Duo sad 😢"*)
drew public backlash — it is a criticised counter-example, not a model.

**Ask vs decide: genuinely unsettled.** No A/B or retention data in fitness found across ten vendor
and research sources. Freeletics and Centr ask; Duolingo decides; Apple lets users pre-declare.

## 5. Free vs paid

- **No documented case** of any app giving returning free vs paid users a different *training*
  experience, and **no example of anyone paywalling a re-entry plan**.
- Platform-sanctioned asymmetry is **price, not programming** (Apple Win-Back Offers, Google Play
  winback SKUs).
- **Recommendation: never gate the re-entry ramp.** It is a safety feature. Charging for the safe
  version of something already sold is the clearest dark-pattern read available. Gate *depth* (AI
  re-planning, analytics) if needed; never the lighter first week.

## 6. Recommended shape, by absence length

| Away | Action |
|---|---|
| **< 2 weeks** | Resume untouched. No prompt, no deload, no regeneration. **Do NOT drop them into the week-4 deload.** |
| **2-4 weeks** | Resume the phase, ramp week 1. Suggested reduction that is **adjustable and ignorable** (the StrongLifts pattern). |
| **4-8 weeks** | Offer a **fresh 4-week phase, week 1 = calibration**. The fresh-start effect (Dai/Milkman/Riis 2014) says a clean landmark is motivationally better than resuming a stale one. |
| **8+ weeks** | Fresh phase + full 2-week re-entry. Re-baseline from logged data; never present stale 1RMs as current. Tell them ~5 weeks to prior loads — reassuring and evidence-based. |

**By experience:** experienced → autoregulate on RIR (their RIR accuracy is materially better,
velocity-RPE r = −0.88 vs −0.77 in novices). Beginners → prescribe fixed conservative caps and let
logged performance recalibrate; their RIR self-report is unreliable.

**The IRV cap** — the one concrete, computable guideline found: `IRV = Sets × Reps × %1RM(decimal)`,
**capped at 30** for the first two weeks back, from CSCCa/NSCA consensus. ⚠️ The agent notes the
50/30/20/10 schedule alongside it is **expert consensus, not experimentally derived**.

## 7. What the evidence does NOT settle

1. **The load-reduction percentage.** Published guidance spans **10% to 60%** with no experiment
   adjudicating. ⇒ **Re-baseline from logged data rather than picking a number.** This is the single
   most confident "not settled" finding.
2. **Ask vs decide** — no fitness A/B data found.
3. **What Fitbod actually does** — unresolved, and it is the most-cited app in the category.
4. **Whether 4 weeks is the right re-entry unit** — the CSCCa ramp aligns with our phase length by
   coincidence; it was designed for collegiate conditioning volume and heat/rhabdo safety, **not
   validated for hypertrophy programming**.
5. Whether the "what-the-hell effect" transfers to workout streaks — the eating-relapse literature
   is solid; no fitness-app test exists. The application is the agent's inference.
6. Streak Freeze / Streak Repair effect sizes — Duolingo published Wager and Amulet, not these two.

---

## 8. How this lands against OUR code (main-thread verified, 2026-09-10)

These are facts read from source by the main thread, not agent claims.

⚠️ **Two of these rows were still WRONG, and the lesson is about input-set width, not sourcing.**
Both cited real lines that really said what was quoted — but neither check asked *is this code
reachable?* One sat behind a default-OFF flag; the other was read as a per-session ramp when its
only caller runs once per phase. **Reading the line is not reading the call site.** Corrected
2026-09-10 by plan-review round 3; see `docs/plan-reviews/regen-wave-unit2-round3.md` §F4.

| Ours | Research says | Gap |
|---|---|---|
| `detraining.dart` decays **weight**: ≤7d none · 8-21d −7.5% · 22-35d −17.5% · **>35d −50%**. Default **ON**, but ⚠️ **unreachable for a FREE user** — ⑦(a) sits inside `ProgressionResolver.resolve()`, which returns `{}` for `phase <= 1` (`progression_resolver.dart:55`), and ⑦(b) is flag-OFF | Weight/strength is the **best-retained** quality; **work capacity** decays worst | Two gaps, not one. For PRO: we cut the variable that survived and leave the one that didn't — points at cutting **sets/frequency**, not load. For FREE: **no decay fires anywhere**, so they resume at their exact pre-absence load |
| −50% at >35d | Published range 10-60%, unsettled; prefer **re-baselining from logged data** | Ours is at the aggressive end of a range nobody has validated |
| ⚠️ **CORRECTED 2026-09-10 (round 3, F4).** `:307`/`:318` are inside `_gradedSuggestion`, reachable only under `gradedProgressionEnabled` — **default OFF**. What ships is the fixed rule at `:203-215`, run **once per PHASE** (`resolve()` has one caller, `plan_generator.dart:235`); `suggestedWeight` is constant across the phase's weeks (`periodization_engine.dart:112-115`) | Gate on **elapsed time**; a good week-1 session is not readiness (tendon) | The original row had this **backwards**. From −50% the suggestion recovers at **+2.5–5 kg per 4-week phase** — ~10 phases to undo 100→50 kg. The ramp is an order of magnitude **too slow**, not too fast, so users override it and the prescription becomes noise |
| `sessionDetrainingCutEnabled` **OFF (ship-dark)** — no welcome-back banner, no reduced prefill | The welcome-back moment is where the retention damage is attenuated | Generation says 50%, the workout screen prefills the **old undecayed** weight. Two halves of one feature disagree **in production** |
| **LIVE:** free user returning gets **`redoWeek4`**, sourcing `planEnd - 6d` (`workout_schedule_write_service.dart:183`) = the trailing **deload** week. **SHIP-DARK:** `holdWeek` (`:266-270`) already sources `planStart + 14..20` = **week 3 (PEAK)**, deload only every 4th hold | **Do not deload a returning user**; an unnecessary deload may *reduce* strength (Coleman 2024) | The live path is counterproductive; **the fix is written and flag-gated** — remedy is OI-60's flip, not new work. `holdWeek`'s own comment calls redoWeek4's behaviour "the bug" |

**Nothing here is decided.** Recorded so the next session starts from evidence rather than
re-running two research passes.
