# Flutter embedding — keep all Flutter engine classes from obfuscation.
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.**

# Health plugin (dev.fluttercommunity.plus.health)
# The plugin casts the Activity to its internal types at runtime.
-keep class dev.fluttercommunity.plus.health.** { *; }
-dontwarn dev.fluttercommunity.plus.health.**

# Google Fit / Health Connect APIs
-keep class com.google.android.gms.fitness.** { *; }
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# Health Connect (AndroidX)
-keep class androidx.health.connect.** { *; }
-dontwarn androidx.health.connect.**

# Keep the app's MainActivity (already kept by manifest, but explicit is safer)
-keep class com.icanbefitter.icanbefitter.MainActivity { *; }

# ── Firebase Crashlytics (added 2026-04-18) ──────────────────────
# Keep Crashlytics APIs + all annotations so obfuscated stack traces
# still symbolicate correctly. Firebase provides these canonical
# keep rules — see https://firebase.google.com/docs/crashlytics/get-started.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.common.internal.safeparcel.SafeParcelable { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
