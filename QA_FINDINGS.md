# QA Findings & Issues

## Critical Issue: Health Plugin ClassCastException
**Error:** `java.lang.ClassCastException: com.icanbefitter.icanbefitter.MainActivity cannot be cast to b.l`
**Location:** Log line 03-30 13:55:10.419
**Impact:** Google Fit / Health Connect integration will NOT work
**Root Cause:** Health plugin expects FlutterFragmentActivity but app uses FlutterActivity

### Impact on App
- Health sync (Step counter, Sleep, Heart Rate) will fail silently
- Profile → Health Sync section will not function
- Weight tracking from device will not work
- Home screen step counter will show 0

### Fix Required
Check `android/app/src/main/kotlin/com/icanbefitter/icanbefitter/MainActivity.kt`:
- Change from `FlutterActivity()` to `FlutterFragmentActivity()`
- OR upgrade health plugin to version compatible with FlutterActivity

### Severity
🔴 **HIGH** - Breaks core health integration feature

---

## Performance Issue: Long Startup Time
**Duration:** 49 seconds (cold start)
**Timeline:**
- 13:54:47 - Intent started
- 13:55:35 - Activity displayed
- 13:55:35 - Fully drawn

**Expected:** < 3 seconds

### Analysis
- Process creation: 11049 started at 13:54:53 (6 seconds after intent)
- LibFlutter loaded: 13:55:01
- Impeller rendering backend initialized: 13:55:06
- UI fully rendered: 13:55:35

### Probable Causes
- Cold start JIT compilation
- Large APK size (100.3MB) - may indicate heavy dependency bloat
- Hive box initialization on first launch
- Asset loading (bundled exercise_library.json + food_database.json)

### Recommendation
- Profile with profiling tool
- Consider lazy-loading of database assets
- Check for unnecessary large dependencies
- Pre-compile assets if possible

---

## Permission Issues
**AVC Denied:** `avc: denied { read } for name="max_map_count"`
- Minor system permission issue
- Does not affect app functionality
- May appear in logs but doesn't prevent execution

---

## App Status
✅ App is running and responsive
✅ ImeTracker shows UI interactions being processed
⏳ Full testing in progress
