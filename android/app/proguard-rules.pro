# flutter_local_notifications guarda los avisos programados con Gson. Con R8
# en modo completo, sin estas reglas programar un aviso falla en release
# ("Missing type parameter") aunque en debug funcione.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }
