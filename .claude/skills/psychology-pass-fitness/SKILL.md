---
name: psychology-pass-fitness
description: >-
  ICANBEFITTER-customized persuasion + behavior-change psychology lens. A fork of the
  universal `psychology-pass` skill, tuned for THIS app's two persuasion stages — acquisition
  (Mission Brief, PaywallSheet, App Store listing, shareable cards) AND in-app retention
  (streak/rank cards, push-notification copy, empty states, AI-coach replies, promotion &
  graduation screens, plan-expired upsells). It reviews existing copy/UX OR guides new copy,
  naming what builds trust + habit, what psychologically BACKFIRES or reads as a dark pattern,
  and the concrete copy/layout fix — grounded in named principles (narrative transportation,
  Hero/Guide, peak-end, Hick's Law, halo, self-efficacy, AND identity-based habits, loss
  aversion, endowed progress, goal-gradient, variable reward, fresh-start effect, implementation
  intentions, commitment/consistency, B=MAP). Brand-aware: it judges against the Wardroom/Navy
  brand soul ("Become a Lt", "Recruit/Bridge/dispatch") and flags drift to generic "wellness
  SaaS" tone as a failure. Use WHENEVER you create, write, restructure, critique, or review any
  user-facing surface in this app — a screen, card, headline, CTA, nudge, push, paywall, or
  empty state — even if the user never says "psychology". For non-app brands, use the universal
  `psychology-pass` instead.
---

# Psychology Pass — ICANBEFITTER (fitness)

A reusable lens that runs any user-facing artifact in this app — a screen, a card, a
headline, a CTA, a push notification, a paywall, an empty state — through the psychology
of how a person decides to **trust**, and how they build (or break) a **daily habit**.
The goal isn't to bolt on manipulation: it's to make a true, good fitness program *land*
and *stick* — emotion before facts, the recruit as the hero, one clear next action, and a
loop that rewards showing up.

This is a **fork of the universal `psychology-pass`** skill. It inherits the acquisition
principles verbatim and **adds** the behavior-change layer, the Wardroom brand-soul
guardrail, the fitness-specific ethical line, and a surface→principle taxonomy. Apply it
proactively — if you're shaping or judging anything a user will read or tap, run the pass.

## The core insight: TWO stages, not one

The universal skill assumes one job — a *stranger* deciding to *trust* (About/landing/sales
pages). ICANBEFITTER has **two** persuasion stages, and most of the app is the second one:

| Stage | When | Surfaces | Dominant psychology |
|---|---|---|---|
| **Acquisition** | pre-install / pre-upgrade; a stranger or a free user deciding | Mission Brief, PaywallSheet, App Store listing, shareable cards, referral copy | the universal principles (transportation, Hero/Guide, peak-end, halo, Hick's Law) |
| **Retention** | post-install; a known user deciding to *show up again today* | streak/rank cards, push copy, empty states, AI-coach replies, promotion/graduation, plan-expired | the **behavior-change** principles (identity habits, loss aversion, goal-gradient, variable reward, B=MAP) |

Name the stage first. A retention nudge judged by acquisition rules (or vice-versa) gets the wrong fix.

## How to run a pass

1. **Load the brand soul.** Skim `lib/shared/widgets/wardroom/CLAUDE.md` (palette + voice),
   `lib/core/copy/wardroom_copy.dart` (canonical copy), and the root `CLAUDE.md` §1/§3
   (identity, the "Become a Lt" ladder). Judge against *this* brand — disciplined naval-officer
   culture aimed at a Tier-1 Indian IT desk worker (22–35) building muscle — not a generic template.
2. **Name the artifact's job + its reader + its STAGE** (acquisition vs retention). Persuasion
   is relative to *this* person's fears and goals at *this* moment.
3. **Run the principles** (below) over it — the acquisition set, the behavior-change set, or both.
   For each: present? placed right? or missing/backfiring?
4. **Check the brand-soul guardrail and the ethical line** (every pass — these are pass/fail gates).
5. **Output a Psychology Pass** in the fixed format at the bottom.

Keep judgments specific and copy/layout-level ("change the streak banner meta to lead with the
freeze count," not "add motivation"). Explain the *why* so the fix is portable.

---

## Part A — Acquisition principles (inherited; instantiated for us)

Each is **name — mechanism → how to apply here.**

**Story & emotion (the engine — lead with it)**
- **Narrative transportation** — an absorbed reader drops their guard → open the Mission Brief with a vivid *scene* (the founder's own before/after), not a feature list.
- **Specificity** — one concrete detail out-persuades any abstraction → "5 AM in a Bangalore PG, no gym, just push-ups" beats "disciplined".
- **Emotional arc** — setup → scar → resolution is what's remembered.

**Make the reader the hero (Hero/Guide)**
- The **recruit is the hero**; the founder/coach ("Bridge") is the **guide**. Reframe "I built this" → "I built this *so you can make Lieutenant*". The "Become a Lt" promise is the hero's transformation, not the app's feature.

**Self-efficacy (Bandura)**
- A relatable, ordinary-origin, *coping* model ("I was skinny and weak — I just never stopped") makes the user think "then I can too." Show the **process and the scars**, not only the trophy. Critical for a deskbound beginner who doubts they can do it.

**Trust & authority (Cialdini + halo) — AFTER the emotional work**
- **Halo** — the first impression (the founder's authentic photo on the Mission Brief, a clean confident opening) colors everything after. Authenticity > stock perfection.
- **Social proof ("people like you")** — testimonials from *other Tier-1 IT desk workers* lower risk; place near the CTA, after the peak. **Never fabricate** counts or quotes (see ethics).
- **Authority** — weave the founder's credibility into the story; never bullet-brag.
- **Scarcity** usually does **not** belong (reads manipulative) — except a *true* cohort/seat limit, stated honestly.

**Likability via honesty (Pratfall)** — admit one real, bounded scar *after* competence ("lost a year to ego-lifting and got injured"), never a disqualification.

**Attention & memory** — **Peak-end** (engineer one undeniable peak: the "who this is for / make Lt" beat), **Primacy/recency** (spend the first and last beats on emotion), **Hick's Law** (one primary CTA — PaywallSheet's single `UPGRADE TO PRO` is correct), **Zeigarnik** (an honest open loop pulls down the page), **Processing fluency** (short lines, whitespace, clear hierarchy *feel* truer).

---

## Part B — Behavior-change / retention principles (NEW — the fitness delta)

Each is **name — mechanism → how to apply + the real surface/file.**

- **Identity-based habits** (Clear; self-signaling) — *every logged workout is a vote for the person you're becoming.* The 11-rung rank ladder IS this engine. Copy should reinforce *identity* ("Petty Officers don't skip leg day") over *task* ("log your workout"). Surfaces: `rank_ladder_screen.dart`, `promotion_celebration_screen.dart`, push copy.
- **Loss aversion** (Kahneman–Tversky) — losing a streak hurts ~2× the joy of earning it; the streak's *value to the user is the fear of losing it.* Frame the at-risk nudge around what's *protected*, not a generic "work out". Surface: `streak_warning_banner.dart`, `streak-guardian-daily`. Keep it factual, never shaming (ethics).
- **Endowed progress** (Nunes–Drèze) — people accelerate when they feel *already started.* SD2 earned *at induction* (an empty gate that's already filled) is textbook-correct; preserve it. Don't reset a returning user to zero — show retained progress. Surface: induction, rank pill.
- **Goal-gradient** (Hull; Kivetz) — effort rises as the goal nears. *Always show how close the next thing is* — "1 workout from your next freeze", "2 weeks to Petty Officer". Surfaces: `streak_explainer_sheet.dart`, rank ladder gate text, `WardBar`/`WardPhaseDots`.
- **Variable reward** (operant; Hooked) — an *unpredictable* reward beats a fixed one. PR detection + the surprise promotion celebration are this; protect the surprise (don't pre-announce every PR). Surfaces: `pr-detection`, `promotion_celebration_screen.dart`, workout receipt.
- **Peak-end (session level)** — overall judgment of a *workout* is set by its peak and its **end**. The post-workout **receipt card** IS the session's ending — design it as a peak (a win to share), not an afterthought. Surface: `workout_receipt_card.dart`.
- **Fresh-start effect** (Dai–Milkman) — temporal landmarks (Monday, a new phase, month start) reset motivation. Time re-engagement + new-phase copy to landmarks. Surfaces: `graduation_screen.dart`, `re-engagement`, Phase unlock.
- **Implementation intentions** (Gollwitzer) — "I'll train at TIME in PLACE" beats "I'll train." Anchor the workout-window nudge to the user's *median* workout hour (the banner already clamps 18–23h off median). Surface: `workout-window-closing`, `streak_warning_banner.shouldShow`.
- **Commitment & consistency** (Cialdini) — an *active, public-feeling* commitment increases follow-through. The "REPORT FOR DUTY" enlistment tap and muster are commitment devices — keep them effortful-but-quick, not skippable noise. Surfaces: `plan_screen.dart`, `muster_screen.dart`.
- **B = MAP** (Fogg: Behavior = Motivation × Ability × Prompt) — when motivation dips, **shrink the action** and keep the **prompt** timely. The plan-expired card's "Re-do Week 4" door and the AI coach's "log just one set" are correct low-ability paths. Don't demand a full workout from a wavering user — ask for one set. Surfaces: `plan_expired_card.dart`, AI-coach quick prompts.

---

## Brand-soul guardrail (ICANBEFITTER) — a pass/fail gate

The universal skill says "don't let it drift into a generic template if the brand's soul is
something more." Here that soul is concrete and **load-bearing**:

- **The Wardroom/Navy lexicon is not decoration.** "Recruit · Bridge · dispatch · orders ·
  enlistment · muster · deployment · REPORT FOR DUTY · stand by" is the semantic frame that
  makes the rank ladder believable and aspirational. **Drift to generic wellness SaaS is a
  FAILURE**, even if it'd "convert": "Hey there! 👋 Ready to crush your goals?" ✗ →
  "Bridge here, Recruit. Standing by for orders." ✓ (see `coach_replies.dart`).
- **Tone calibration: disciplined officer, not abusive drill sergeant.** Aspirational naval
  culture — respect, mastery, identity — NOT boot-camp hazing or shame. "Standing by for
  orders, Recruit" ✓; "DROP AND GIVE ME 20, MAGGOT" ✗.
- **Founder-as-guide is the moat.** The Mission Brief founder photo/voice is the halo + the
  Hero/Guide anchor. The recruit is the hero; the founder is Obi-Wan, not Superman.
- **Visual coherence is the trust signal.** Campaign Gold `#D4B270`, DM Sans body, Fraunces
  emphasis, JB Mono numerals, the rank insignia. Off-palette/off-font copy *feels* less true
  (processing fluency) — flag it. Palette SoT: `lib/shared/widgets/wardroom/CLAUDE.md`.
- **The identity arc is the spine.** Every surface should nudge "you are becoming an officer,"
  not merely "use the app." If a screen could belong to any fitness app, it's drifting.

## Ethical line — dark patterns to flag (fitness-specific)

The creed is *make true work land, don't manipulate.* In a daily-nudge app this must be enforced
harder. **Flag any of these as a backfire, not a win:**

- **Fake scarcity / urgency** — countdown timers that reset, "offer ends today" that doesn't. A
  *true* limit stated honestly is fine.
- **Shame / fear of self-worth** — streak/relapse copy must attack the *missed action*, never the
  *person*. "Your 12-day streak is at risk" ✓; "You always quit, don't you?" ✗.
- **Confirmshaming** the dismiss — the paywall's neutral `MAYBE LATER` ✓; "No, I don't want to get
  fit" ✗.
- **Fabricated progress or social proof** — derive-only honesty (ADR-0012): never show a PR, rank,
  or "X people upgraded today" the user/data didn't actually earn. A faked number poisons the whole halo.
- **Free-tier rage-bait** — Phase 1 is *always free* and must feel complete; don't cripple it to
  force an upgrade. The paywall sells the *next* phase's value, it doesn't punish the free user.
- **DPDP / India sensitivity** — honest consent, frictionless delete-account, no subscription roach-motel.

If a proposed nudge needs a dark pattern to work, the underlying offer is too weak — fix the offer.

## Surface → principle taxonomy (where each lever lives)

| Surface | File | Stage | Primary levers |
|---|---|---|---|
| Mission Brief | `lib/features/onboarding/screens/mission_brief_screen.dart` | Acq | transportation, halo, Hero/Guide, self-efficacy, peak-end |
| Enlistment / plan | `lib/features/onboarding/screens/plan_screen.dart` | Acq→Ret | commitment/consistency ("REPORT FOR DUTY") |
| PaywallSheet | `lib/shared/widgets/paywall_sheet.dart` | Acq | Hick's Law (1 CTA ✓), peak-end subtitle, social proof gap, honest scarcity |
| Phase-2 paywall variant | `lib/shared/widgets/paywall_sheet_phase_variant.dart` | Acq | fresh-start, endowed progress ("you crushed Phase 1") |
| Plan-expired card | `lib/features/train/widgets/plan_expired_card.dart` | Ret | B=MAP (low-ability "Re-do Week 4" door), Hick's (3 doors — watch overload) |
| Streak-at-risk banner | `lib/shared/widgets/streak_warning_banner.dart` | Ret | loss aversion, implementation intentions, goal-gradient (freeze count) |
| Streak explainer | `lib/features/home/widgets/streak_explainer_sheet.dart` | Ret | goal-gradient ("days to next rank"), endowed progress |
| Rank ladder / pill | `lib/features/profile/screens/rank_ladder_screen.dart`, `ward_rank_pill.dart` | Ret | identity habits, goal-gradient |
| Promotion celebration | `lib/features/profile/screens/promotion_celebration_screen.dart` | Ret | variable reward, identity, peak-end |
| Graduation (Phase 2) | `lib/features/train/screens/graduation_screen.dart` | Ret | fresh-start, peak-end, endowed progress |
| Workout receipt | `lib/features/train/widgets/workout_receipt_card.dart` | Ret + Acq(viral) | peak-end (session), shareable social proof |
| AI-coach replies | `lib/features/ai_coach/copy/coach_replies.dart` (+ server `_shared/coach_replies.ts`) | Ret | brand voice, B=MAP, honest gating |
| Empty states | `lib/features/train/screens/train/empty_states.dart`, `lib/shared/widgets/empty_state.dart` | Ret | self-efficacy, one clear next action |
| Push nudges | `supabase/functions/{morning-alert,streak-guardian-daily,workout-window-closing,re-engagement,...}` | Ret | implementation intentions, fresh-start, loss aversion |
| Expiry banner | `lib/shared/widgets/subscription_expiry_banner.dart` | Acq(win-back) | loss aversion, honest urgency (real dates) |

## Section-ordering heuristics

**Acquisition page** (Mission Brief / App Store / paywall hero) — psychology-optimal default:
1. Hook + authentic visual (founder photo) — emotion, not credentials.
2. Origin / struggle — specific, relatable.
3. The scar — bounded vulnerability *after* competence.
4. The PEAK — "who this is for / you can make Lt".
5. Authority + social proof — *after* the peak.
6. The offer as the recruit's tool — benefit-framed.
7. Close echoing the peak + ONE primary CTA.

**Retention loop** (any nudge / session / card) — design the loop, not just the line:
1. **Cue** — a *timely, contextual* prompt (implementation intention; anchored to the user's median time / a fresh-start landmark).
2. **Ability** — make the asked action *small* (B=MAP; "one set" beats "full workout" for a wavering user).
3. **Reward** — immediate, sometimes *variable*, and celebratory (peak-end; the receipt / PR / promotion).
4. **Identity** — reinforce who they're becoming ("another vote for the officer").
5. **Visible progress** — show how close the next rank / freeze / phase is (goal-gradient).

## Do / Don't

**Do** — name the stage first; lead acquisition with soul, retention with the loop; make every
line imply "…so *you* (the recruit) can…"; engineer one peak + a strong end; show how close the
next milestone is; keep the Wardroom voice; give a wavering user a *tiny* next action; admit one
real scar (acquisition).

**Don't** — judge a nudge by acquisition rules (or vice-versa); drift to generic wellness tone;
stack competing CTAs; use fake scarcity, confirmshaming, or shame-of-self; fabricate progress or
social proof; cripple the free tier to force upgrade; bury the human under a résumé; reset a
returning user to zero.

## Output format

Always return the pass as:

**🧠 Psychology Pass — [artifact] · [stage: acquisition / retention]**

1. **What's working** — bullets, each tagged with the principle and *why* it lands.
2. **What's missing / backfiring** — bullets, each tagged with the principle + the specific issue (cite the line/file).
3. **Concrete fixes** — specific copy/layout changes (reword X → Y; move Z below the peak; cut to one CTA; anchor the nudge to median workout time).
4. **Brand-soul + ethics check** — Wardroom voice intact? (✓/⚠/✗) · any dark pattern? (name it or "none").
5. **Verdict** — a quick ✓/⚠/✗ checklist across the key principles for this stage (acquisition: transportation · Hero/Guide · peak-end · Hick's · halo; retention: cue-timeliness · ability/B=MAP · reward · identity · goal-gradient) and the **single highest-leverage fix** to make first.

Scale depth to the artifact: a one-line push gets a few bullets; a full screen gets the whole
pass. Be a sharp, honest partner — name what's weak plainly, tie it to the user's psychology AND
the brand's soul. See `references/surface-taxonomy.md` for a worked example pass.
