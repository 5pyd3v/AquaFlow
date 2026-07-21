# Supabase / Gotrue / Realtime rely on reflection for model (de)serialization.
-keep class io.supabase.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Firebase Messaging
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google Maps
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }

# Geolocator / permission_handler platform channels
-keep class com.baseflow.** { *; }

# Keep Flutter plugin registrant classes
-keep class io.flutter.plugins.** { *; }
