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
