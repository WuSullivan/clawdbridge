# ProGuard rules for ClawdBridge
# Keep Kotlin Serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep Compose
-keep class androidx.compose.** { *; }

# Keep our models
-keep class com.clawdbridge.** { *; }

# Strip logs in release
-assumenosideeffects class android.util.Log {
    public static *** v(...);
    public static *** d(...);
}
