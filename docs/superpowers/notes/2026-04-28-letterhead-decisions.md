# Letterhead Decisions — APK Test #5 Plan D

**2026-04-28**

D-1 is a **no-op on `feat/apk-test-5-batch`**. The U7 commits (`257a5ff..bfd89ae` introducing `WardTabHeader`) live only on `feat/apk-test-4-batch` and were never merged into `main` or onto Test #5's base. Verified via:

```
git branch --contains bfd89ae
  feat/apk-test-4-batch
```

No revert needed. Plan D continues with D-2 (FreezeBadge), D-3 (WardStatusStrip), D-4 (extend WardLetterhead with `leadingAvatar`).
