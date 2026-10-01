# Surface Taxonomy + Worked Examples — psychology-pass-fitness

Companion to `../SKILL.md`. The SKILL has the summary surface→principle table; this file
adds (1) a per-surface "what to check first" quick reference and (2) two **worked example
passes** that demonstrate the skill produces concrete, brand-aware output. The worked
examples were produced by applying the skill to the live code — they double as the skill's
acceptance validation.

---

## Per-surface quick reference (what to check FIRST)

**Acquisition**
- **Mission Brief** — Is the *opening* a scene + the founder's real photo (transportation + halo), or does it lead with credentials/values? Is the recruit the hero and the founder the guide?
- **PaywallSheet** — One primary CTA (✓ it is)? Is the subtitle tied to the *gating feature* (peak-end)? Is there ANY peer social proof near the price? Is the default/fallback copy on-voice?
- **App Store listing** — First screenshot + first line carry primacy + halo; is the "Become a Lt" hook in the first sentence?
- **Shareable cards** — Do they carry the brand mark + an honest stat? (peak-end of a session → viral social proof).

**Retention**
- **Streak banner** — Loss-aversion framed (not shame)? Cue anchored to the user's *median* time? Does it show how close the next rank/freeze is (goal-gradient)?
- **Rank ladder / promotion** — Identity language ("officers don't…") over task language? Is the *next* gate's distance visible? Is the promotion a surprise-able peak (variable reward)?
- **Plan-expired card** — Is there a *low-ability* door (B=MAP) for a wavering user, or only "upgrade"? Too many doors (Hick's)?
- **Empty states** — One clear next action + a self-efficacy nudge, or a dead end?
- **Push nudges** — Timed to a landmark/median (implementation intentions + fresh-start)? On-voice? Honest (no fake urgency)?
- **AI-coach replies** — Wardroom voice intact ("Recruit/Bridge")? Does a gated reply sell the *next* value honestly, without shaming the free user?

---

## Worked example 1 — PaywallSheet · stage: ACQUISITION

Source: `lib/shared/widgets/paywall_sheet.dart`.

**🧠 Psychology Pass — PaywallSheet · acquisition**

1. **What's working**
   - **Hick's Law ✓** — one primary CTA `UPGRADE TO PRO` (:451); the secondary actions `MAYBE LATER · RESTORE` (:466/:482) are correctly de-emphasized as small mono text. No competing buttons.
   - **Peak-end / endowed progress ✓** — the feature-specific `_featureSubtitle` (:74) tailors the hook to the gate; "You crushed Phase 1. Unlock progressive phases…" (:77) is endowed-progress + identity, well placed.
   - **No confirmshaming ✓** — dismiss is the neutral `MAYBE LATER` (:466), not "No, I don't want to get fit". Ethical.
   - **Honest pricing ✓** — reads `AppConstants` not hardcoded (:287–288) and computes `savings %` live from the two prices (:295), so the discount claim can't drift.
   - **Processing fluency ✓** — Wardroom letterhead + single gold rule + a tight check-glyph benefit list read as trustworthy.

2. **What's missing / backfiring**
   - **Social proof MISSING (Cialdini/halo)** — nothing "people like you" anywhere near the ₹2,999 decision. For a Tier-1 IT desk worker, one honest peer signal lowers risk most.
   - **Benefit list is a flat 9-item wall (:61–71)** — peak-end says order matters; 9 undifferentiated bullets dilute and add Hick's load. The bullet matching `widget.feature` (the reason they're here) should lead.
   - **Generic default subtitle (brand-soul ✗)** — `default: 'Upgrade to PRO and unlock your full potential.'` (:101) is exactly the "generic wellness SaaS" drift the brand-soul gate bans.
   - **Benefit copy is feature-listy, not identity-framed (Hero/Guide)** — "Unlimited AI Coach with deep personalised coaching" states a feature, not "…so you can…".

3. **Concrete fixes**
   - Add ONE honest peer line above the CTA, e.g. a real count or a one-sentence recruit quote (only if true — see ethics). Place after the benefits, before `UPGRADE TO PRO`.
   - Reorder `_proBenefits` so the gating feature's benefit renders first (pass `widget.feature` into the list build).
   - Reword the default subtitle in Wardroom voice: *"Phase 1 was your enlistment. PRO is the commission — the rest of the climb to Lieutenant."*
   - Reframe 2–3 top benefits "…so you can…": "Unlimited AI Coach — *so you never train a session unsure of your next move.*"

4. **Brand-soul + ethics check** — voice ⚠ (default subtitle + benefit copy drift generic; fixable). Dark pattern: **none** (honest live-computed pricing, neutral dismiss, real savings math).

5. **Verdict** — transportation ⚠ · Hero/Guide ⚠ · peak-end ⚠ · Hick's ✓ · halo ⚠. **Highest-leverage fix:** add one *honest* peer social-proof line near the CTA — it's the single biggest gap on a paywall for this persona.

---

## Worked example 2 — StreakWarningBanner · stage: RETENTION

Source: `lib/shared/widgets/streak_warning_banner.dart`.

**🧠 Psychology Pass — StreakWarningBanner · retention**

1. **What's working**
   - **Loss aversion ✓** — title `"$streakDays-day streak at risk"` (:91) frames around the *protected asset*, factual, not a personal attack. Textbook.
   - **Implementation intentions ✓ (strong)** — `shouldShow` anchors the cue to `medianWorkoutHour + 3` clamped to 18–23h (:44–48), so it fires in the user's real evening window, not a generic blast.
   - **Honest urgency ✓** — `"${hours}H LEFT"` is a true countdown to midnight (:56), not a fake reset timer.
   - **B=MAP / Hick's ✓** — one small clear action `TRAIN NOW` (:122).
   - **Goal-gradient (partial) ✓** — the meta line surfaces freeze availability (:57–59).

2. **What's missing / backfiring**
   - **Goal-gradient under-used** — it shows freezes but NOT how close the *next rank* is. "12-day streak at risk" + "2 days to Petty Officer" is far stronger; the rank ladder is the app's best lever and it's absent from its most-seen nudge.
   - **Identity reinforcement MISSING** — pure task ("train now"); no identity vote ("officers don't break the chain"). (Watch density — the banner is compact.)
   - **No-freeze branch is mildly hectoring** — `"NO FREEZES — DON'T MISS TODAY"` (:59); the all-caps imperative edges toward scold. It attacks the action (ok) but the tone can soften.
   - **Brand voice ⚠** — "streak at risk / TRAIN NOW" is generic fitness; no Wardroom flavor.

3. **Concrete fixes**
   - Inject a goal-gradient token when within ~3 of a rank gate: append `· {N} TO {NEXT_RANK}` to the meta line (data already in `rank_service`).
   - Soften the no-freeze meta: `"NO FREEZES LEFT · PROTECT THE STREAK"` — keeps loss aversion, drops the scold.
   - Optional on-brand flavor at acceptable density: title → `"DEPLOYMENT AT RISK"`, CTA → keep `TRAIN NOW` for clarity (high-urgency moment favors clarity over flavor).

4. **Brand-soul + ethics check** — voice ⚠ (generic, fixable). Dark pattern: **none** — loss aversion is honest and the countdown is a real clock, not manufactured scarcity.

5. **Verdict** — cue-timeliness ✓ · ability/B=MAP ✓ · reward n/a · identity ✗ · goal-gradient ⚠. **Highest-leverage fix:** add the "X to next rank" goal-gradient line — the app's most powerful retention lever, currently missing from its most-shown nudge.

---

*Both passes are concrete (cite file:line), brand-aware (judge against the Wardroom soul and
flag generic drift), and ethics-screened (named "none" where clean) — confirming the skill
produces the intended output on real surfaces.*
