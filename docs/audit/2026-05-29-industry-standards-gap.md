# Industry-Standards Gap Analysis — ICANBEFITTER (2026-05-29)

> Two halves: (1) **Engineering / quality bar** (assessed from the repo + this audit) and
> (2) **Product / feature parity** vs MyFitnessPal, HealthifyMe, Cult.fit, Fittr, plus global
> trackers (Hevy/Strong, Strava). Each row tagged **must-have / nice-to-have / differentiator**.
> "Verify internally" = product claim that needs a quick code check before action.

---

## PART 1 — Engineering / Quality Bar

| Dimension | Industry bar | Where we are | Tag | Gap / action |
|---|---|---|---|---|
| Crash-free sessions | ≥ 99.5% sessions, ≥ 99.9% crash-free users; velocity + ANR alerting | `client_errors` telemetry exists; Crashlytics **alert routing is scaffold-only** (L49, `firebase-alerts.json` TODO). No published crash-free target. | must-have | Define target; wire Crashlytics velocity/ANR alerts to a real channel. |
| Test coverage & pyramid | Healthy pyramid, broad unit base | **Strong** — 218 contract / 146 unit / 32 e2e / 24 integ / 15 widget; pyramid audited (`scripts/audit_test_pyramid.dart`). Above the solo-founder norm. | differentiator | Maintain; add the 2 behavioral tests this audit creates (restore round-trip, proactive EF). |
| Observability / alerting | Proactive alerting on error spikes, payment health, cron health | **Just shipped** (migration 076 alert crons); thresholds are placeholders (Phase 2 tuning due 2026-06-03). `cron_call_log` live. | must-have | Tune thresholds; close EF-2 (`weekly-recalc` not telemetered → invisible to `alert_edge_function_health`). |
| CI/CD | Automated test + build gates on every push | pre-commit + 40+ gate scripts; GitHub Actions `test.yml`; device-CI runner + 4 Patrol flows documented. | parity | Confirm CI builds web + APK artifacts, not just tests. |
| Store-readiness | Data-safety form, privacy policy, DPDP/GDPR, working live payments | DPDP delete-account live (v3); RLS lockdown; privacy surfaces exist. **Blocker: `.env.prod` carries `rzp_test_` (I14)** — live payments not provably wired. | must-have | Flip to `rzp_live_*` (founder-only); complete Play data-safety form; verify UPI-autopay mandate. |
| Security / DPDP | RLS everywhere, no SSRF, input limits, service-role scoping | **Strong** — RLS sweep (052-055), SSRF allowlist (OI-28), 5K/10K input caps, pseudonymized deletion (049). | differentiator | Maintain; keep L23 service-role-scope discipline on new EFs. |
| Performance / cold-start | < 2s cold start; lazy/parallel init | No perf budget; L33 flags sequential Hive box opens (~150-300ms win available). | nice-to-have | Add a cold-start budget + parallelize box opens (post-launch). |
| Accessibility | WCAG-ish: semantics, contrast, dynamic type | Not prioritized (L44 deferred). | nice-to-have | Needed for global/iOS + Play quality; defer to post-PMF. |

**Engineering verdict:** quality discipline (tests, security, gates) is **above** the bar for a solo-founder pre-launch app. The real gaps are **operational** (crash/alert routing not wired to a channel, alert thresholds unpinned) and one **launch blocker** (`rzp_test_` in prod). Neither is a code-correctness issue.

---

## PART 2 — Product / Feature Parity

### Nutrition
| Feature | Have it? | Benchmark | Tag | Notes |
|---|---|---|---|---|
| Barcode food scanning | verify internally | MFP Premium, HealthifyMe scan packaged Indian goods | must-have | `mobile_scanner` is a dependency — confirm whether it's wired to food logging or only exercise/other. Biggest daily-flow credibility item. |
| AI photo meal scan | yes (partial) | HealthifyMe "Snap" trained on 150K Indian items | must-have | We have scan; benchmark accuracy vs Indian-food leaders. |
| Indian food DB depth | partial (1431) | HealthifyMe 100K+ Indian items | must-have | 1431 is thin for daily logging (regional/restaurant/packaged). Depth drives retention. |
| Recipes / meal planning | no | MFP recipes + grocery lists | nice-to-have | Plan generator is workout-only. |
| Intermittent-fasting timer | no | MFP, HealthifyMe | nice-to-have | Cheap; popular with desk workers. |

### Workout / Training
| Feature | Have it? | Benchmark | Tag | Notes |
|---|---|---|---|---|
| Exercise demos + form cues | verify internally | Hevy 1,000+ with demos | must-have | Confirm each of 258 exercises has a demo/animation. Muscle-gain ICP needs form trust. |
| Rest timer / supersets / 1RM / volume graphs | verify internally | Hevy/Strong table-stakes | must-have | Serious lifters compare the training screen to Hevy. If missing, we lose them. |
| Rest-day / active-recovery in plan | verify internally | Cult, HealthifyMe | nice-to-have | Confirm 12-week phase schedules recovery. |
| Live/guided classes | no | Cult.fit | n/a | Out of scope — tracker not studio. Skip. |

### Tracking & Devices
| Feature | Have it? | Benchmark | Tag | Notes |
|---|---|---|---|---|
| Wearable breadth (Garmin, Fitbit) | partial | All majors sync Garmin/Fitbit | must-have | We have Google Fit / Health Connect only; target demo owns Garmin/Fitbit. |
| Step counting surfaced | partial | MFP/HealthifyMe | must-have | Should arrive via Health Connect — verify it's surfaced. |
| Sleep tracking | no | HealthifyMe + wearables | nice-to-have | Expected for "holistic" positioning. |
| Apple Health / iOS | no | All competitors | must-have (roadmap) | Caps premium-paying segment; already roadmapped. |
| Data export | verify internally | MFP exports | nice-to-have | DPDP-friendly goodwill. |

### Engagement / Retention
| Feature | Have it? | Benchmark | Tag | Notes |
|---|---|---|---|---|
| Permanent rank ladder + celebrations | yes | MFP badges/streak celebrations | differentiator | Stronger narrative than any competitor — **lean in.** (NB: EF-1 in this audit means promotion push is currently inert — fix first.) |
| Home-screen widget | no | Common reopen lever | must-have | "Rank progress + quick-log" widget = high-ROI daily reopen. |
| Smart notification cadence | partial | MFP personalized nudges | must-have | Confirm cadence is personalized, not generic. |
| Community / "divisions" social | no | Fittr's moat; Strava social | nice-to-have | Navy-division social layer fits the theme; high differentiation upside. |
| Transformation challenges | no | Fittr 12-16 wk challenges | nice-to-have | Maps natively onto our 12-week "deployments". |

### Monetization
| Feature | Have it? | Benchmark | Tag | Notes |
|---|---|---|---|---|
| Mid-tier price wedge | yes | HealthifyMe AI ₹208/mo; coached ₹1,500+; Fittr ₹1,853+ | differentiator | ₹349/mo AI-coached sits defensibly between AI-only and coached tiers; ₹2,999/yr sharp. |
| UPI + UPI-autopay mandate | verify internally | Razorpay supports UPI recurring | must-have | Indians subscribe via UPI-autopay, not cards. Confirm the mandate flow is live. |
| Free-tier credibility | partial | MFP free = full logging; Hevy free = unlimited logging | must-have | Ensure core tracking stays free forever (AI trial expiry shouldn't kill logging). |

### Platform / India-specific
| Feature | Have it? | Benchmark | Tag | Notes |
|---|---|---|---|---|
| Offline-first | yes | Most are cloud-dependent | differentiator | Real India edge (data-cost + patchy network) — **market it.** |
| AI coach personalization | yes | HealthifyMe Ria; MFP adding AI | differentiator | On-trend; differentiate via Indian context + rank persona. |
| Vernacular (Hindi + regional) | no | HealthifyMe 11 Indian languages | must-have | Major tier-2/3 reach gap; Hindi-first unlocks a large segment. |
| Veg/non-veg + regional cuisine | partial | HealthifyMe deep Indian DB | must-have | Veg-default + regional thali presets expected. |

---

## Top gaps to close (product) — prioritized
1. **Barcode scanning** wired to food logging (if not already) — top table-stakes daily flow.
2. **Indian food DB depth** — expand beyond 1431 (regional / restaurant / packaged).
3. **Lifter training tools** (rest timer, supersets, 1RM, volume graphs) + confirm exercise demos — your muscle-gain ICP judges us against Hevy here.
4. **Wearable breadth** (Garmin + Fitbit) beyond Health Connect.
5. **Home-screen widget + smarter notifications** — cheap daily-reopen ROI; pair with rank ladder.
6. **Vernacular (Hindi first)** — HealthifyMe's 11-language lead is a real moat.
7. **UPI-autopay** subscription mandate verified live.
8. **Navy-"division" social / 12-week challenge layer** — borrow Fittr's virality; maps onto deployments (defer but high upside).

**Lean into:** permanent rank ladder + military narrative (uncontested), offline-first (genuine India edge), and the ₹349 AI-coached mid-tier price wedge.

> NOTE: the product gaps above are **roadmap inputs, not bugs** — they are out of scope for this
> audit's remediation batch (A3), which fixes only the verified code-correctness findings. They
> belong in product planning. Tracked here so they aren't lost.
