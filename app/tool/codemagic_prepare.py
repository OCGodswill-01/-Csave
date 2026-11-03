#!/usr/bin/env python3
"""Runs on Codemagic before the build. The zip has no android/ folder, so this creates it,
then applies the Android setup from android_notes/README_ANDROID.txt. It FAILS LOUDLY if any
step does not apply, so you never get a silently broken APK. Pinned for Flutter 3.24.5 (Groovy gradle)."""
import os, re, subprocess, sys, glob

def die(msg): print('PREPARE FAILED:', msg); sys.exit(1)
def read(p): return open(p, encoding='utf-8').read()
def write(p, s): open(p, 'w', encoding='utf-8').write(s)

# 1. public app settings (flutter_app.env is git-ignored, so it is built here from Codemagic variables)
api = os.environ.get('API_BASE_URL', '').strip().rstrip('/')
if not api.startswith('https://'): die('API_BASE_URL must be set in Codemagic and start with https:// (release Android blocks plain http).')
write('flutter_app.env', f"API_BASE_URL={api}\nTELEMETRY_KEY={os.environ.get('TELEMETRY_KEY', '').strip()}\n")

# 2. generate the Android project (permanent app id: com.abiacsave.app, matches the live Play Store listing)
subprocess.run(['flutter', 'create', '.', '--org', 'com.abiacsave', '--project-name', 'app', '--platforms=android'], check=True)

# 3. AndroidManifest
mp = 'android/app/src/main/AndroidManifest.xml'; m = read(mp)
perms = ''.join(f'    <uses-permission android:name="android.permission.{p}"/>\n' for p in ['INTERNET', 'USE_BIOMETRIC', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED'])
if '<application' not in m: die('manifest has no <application>')
m = m.replace('<application', perms + '    <application', 1)
receivers = '''        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
            </intent-filter>
        </receiver>
'''
if '</application>' not in m: die('manifest has no </application>')
m = m.replace('</application>', receivers + '    </application>', 1)
m, n = re.subn(r'android:label="[^"]*"', 'android:label="C\'SAVE"', m, count=1)
if n != 1: die('could not set app label')
write(mp, m)

# 4. MainActivity must extend FlutterFragmentActivity (fingerprint)
acts = glob.glob('android/app/src/main/kotlin/**/MainActivity.kt', recursive=True)
if len(acts) != 1: die(f'expected one MainActivity.kt, found {acts}')
k = read(acts[0])
k = k.replace('import io.flutter.embedding.android.FlutterActivity', 'import io.flutter.embedding.android.FlutterFragmentActivity')
k, n = re.subn(r':\s*FlutterActivity\(\)', ': FlutterFragmentActivity()', k)
if n != 1: die('MainActivity patch did not apply')
write(acts[0], k)

# 5. app/build.gradle: minSdk 23, desugaring for notifications
gp = 'android/app/build.gradle'
if not os.path.exists(gp): die('android/app/build.gradle missing: Flutter version changed template (Kotlin DSL). Keep flutter: 3.24.5 in codemagic.yaml.')
g = read(gp)
g, n = re.subn(r'minSdk(?:Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 23', g)
if n != 1: die('minSdk patch did not apply')
g, n = re.subn(r'(compileOptions\s*\{)', r'\1\n        coreLibraryDesugaringEnabled true', g, count=1)
if n != 1: die('compileOptions patch did not apply')
dep = "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'\n"
if re.search(r'^dependencies\s*\{', g, re.M): g = re.sub(r'^(dependencies\s*\{)', r'\1\n' + dep.rstrip('\n'), g, count=1, flags=re.M)
else: g += '\ndependencies {\n' + dep + '}\n'
write(gp, g)

# 6. release signing: Codemagic's android_signing injects these variables; the keystore never lives in git
for v in ['CM_KEYSTORE_PATH', 'CM_KEYSTORE_PASSWORD', 'CM_KEY_ALIAS', 'CM_KEY_PASSWORD']:
    if not os.environ.get(v): die(f'{v} missing: add csave_upload_keystore under android_signing in codemagic.yaml')
g = read(gp)
signing = """    signingConfigs {
        release {
            storeFile file(System.getenv("CM_KEYSTORE_PATH"))
            storePassword System.getenv("CM_KEYSTORE_PASSWORD")
            keyAlias System.getenv("CM_KEY_ALIAS")
            keyPassword System.getenv("CM_KEY_PASSWORD")
        }
    }
"""
g, n = re.subn(r'^([ \t]*)buildTypes\s*\{', lambda mo: signing + mo.group(1) + 'buildTypes {', g, count=1, flags=re.M)
if n != 1: die('buildTypes block not found for signing')
g, n = re.subn(r'signingConfig\s*=?\s*signingConfigs\.debug', 'signingConfig signingConfigs.release', g)
if n != 1: die('release signingConfig patch did not apply')
write(gp, g)
print('PREPARE OK: android project ready for', api)
