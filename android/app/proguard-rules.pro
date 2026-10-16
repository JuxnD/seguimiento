# flutter_local_notifications guarda los avisos programados con Gson. Con R8
# en modo completo, sin estas reglas programar un aviso falla en release
# ("Missing type parameter") aunque en debug funcione.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Plan 058: ML Kit de texto. Sólo se usa el reconocedor latino (incluido en
# el APK); el plugin referencia los de chino, japonés, coreano y devanagari,
# que no se agregan.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
