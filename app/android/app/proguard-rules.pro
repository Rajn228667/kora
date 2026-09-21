# KORA release keeps — required before re-enabling isMinifyEnabled.

# Flutter engine + embedding
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# flutter_secure_storage — crashes on launch when stripped
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# video_player / ExoPlayer
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# local_auth / BiometricPrompt
-keep class androidx.biometric.** { *; }
-keep class androidx.fragment.** { *; }

# geolocator / permission_handler
-keep class com.baseflow.** { *; }

# Kotlin + coroutines metadata
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Keep all Flutter plugin registrants
-keep class **GeneratedPluginRegistrant { *; }
