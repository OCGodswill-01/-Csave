Fingerprint setup (Android), after running `flutter create .` inside /app:
1. android/app/src/main/AndroidManifest.xml  -> add inside <manifest>:
   <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
2. MainActivity.kt must extend FlutterFragmentActivity:
   import io.flutter.embedding.android.FlutterFragmentActivity
   class MainActivity : FlutterFragmentActivity()
3. android/app/build.gradle -> minSdkVersion 23 (or higher)
iOS: add NSFaceIDUsageDescription to ios/Runner/Info.plist.

Alarms and notifications (Phase 4) - no API key needed:
1. AndroidManifest.xml, inside <manifest>:
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
   <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
2. Inside <application>:
   <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
   <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
     <intent-filter>
       <action android:name="android.intent.action.BOOT_COMPLETED"/>
       <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
     </intent-filter>
   </receiver>
3. android/app/build.gradle: in compileOptions add  coreLibraryDesugaringEnabled true
   and in dependencies add  coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'
Alarms use inexact mode, so they can arrive a few minutes late in battery saver.
