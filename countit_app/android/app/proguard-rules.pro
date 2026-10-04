# R8 rules for the release build (COU-135). Flutter adds its own rules
# (flutter_proguard_rules.pro) and the plugins ship consumer rules; these only
# cover what R8 reports as missing for this app's plugins.

# Flutter embedding references Play Core (deferred components), which the app
# does not use or bundle.
-dontwarn com.google.android.play.core.**

# flutter_secure_storage -> Tink: compile-only annotations not present at runtime.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# Keep line numbers for crash reports, but hide the original source file name.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
