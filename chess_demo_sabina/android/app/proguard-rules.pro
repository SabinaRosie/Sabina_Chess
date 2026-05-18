# Flutter WebRTC - keep native classes
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Core (used by Flutter deferred components)
-dontwarn com.google.android.play.core.**

# OkHttp and eSewa Crypto dependencies
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
