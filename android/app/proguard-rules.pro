# Правила для R8 — сокращателя кода в релизных сборках Android.
#
# Почему файл появился. В боевых сборках приложение падало при каждой
# перепланировке уведомлений:
#
#   PlatformException: TypeToken must be created with a type argument
#   ... java.lang.IllegalStateException ... FlutterLocalNotificationsPlugin.cancelAll
#
# Плагин уведомлений хранит запланированные напоминания через Gson, а Gson
# восстанавливает тип по обобщённой подписи класса. R8 эти подписи выбрасывает
# как «лишние», и Gson остаётся без типа. На отладочной сборке всё работает —
# там сокращателя нет, поэтому вылезло только у пользователей.

# Обобщённые подписи и аннотации — то самое, чего не хватало Gson.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Gson: сам TypeToken и всё, что от него наследуют.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Плагин локальных уведомлений: его классы Gson читает по имени.
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Flutter и Play Core: обычные предупреждения о необязательных зависимостях,
# из-за которых сборка иначе падает на этапе R8.
-dontwarn com.google.android.play.core.**
