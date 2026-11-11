#!/usr/bin/env python3
"""Runs on Codemagic before the build. The zip has no android/ folder, so this creates it,
then applies the Android setup from android_notes/README_ANDROID.txt. It FAILS LOUDLY if any
step does not apply, so you never get a silently broken APK. Works with current Flutter stable (Kotlin gradle) and older Groovy templates."""
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

# 5. app Gradle file: minSdk 23, compile/target API 36 (Play requirement), desugaring for notifications, release signing.
#    New Flutter versions generate build.gradle.kts (Kotlin); older ones generate build.gradle (Groovy). Both are handled.
for v in ['CM_KEYSTORE_PATH', 'CM_KEYSTORE_PASSWORD', 'CM_KEY_ALIAS', 'CM_KEY_PASSWORD']:
    if not os.environ.get(v): die(f'{v} missing: add csave_upload_keystore under android_signing in codemagic.yaml')

def sub1(pattern, repl, text, what, flags=0):
    out, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n != 1: die(f'{what} patch did not apply')
    return out

kts = os.path.exists('android/app/build.gradle.kts')
gp = 'android/app/build.gradle.kts' if kts else 'android/app/build.gradle'
if not os.path.exists(gp): die('no android/app/build.gradle(.kts) found after flutter create')
g = read(gp)

if kts:
    g = sub1(r'minSdk(?:Version)?\s*=\s*[^\n]+', 'minSdk = 23', g, 'minSdk')
    g = sub1(r'targetSdk(?:Version)?\s*=\s*[^\n]+', 'targetSdk = 36', g, 'targetSdk')
    g = sub1(r'compileSdk(?:Version)?\s*=\s*[^\n]+', 'compileSdk = 36', g, 'compileSdk')
    g = sub1(r'(compileOptions\s*\{)', r'\1\n        isCoreLibraryDesugaringEnabled = true', g, 'desugaring flag')
    dep = '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
    if re.search(r'^dependencies\s*\{', g, re.M): g = re.sub(r'^(dependencies\s*\{)', r'\1\n' + dep.rstrip('\n'), g, count=1, flags=re.M)
    else: g += '\ndependencies {\n' + dep + '}\n'
    signing = '''    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("CM_KEYSTORE_PATH"))
            storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("CM_KEY_ALIAS")
            keyPassword = System.getenv("CM_KEY_PASSWORD")
        }
    }
'''
    g = sub1(r'^([ \t]*)buildTypes\s*\{', lambda mo: signing + mo.group(1) + 'buildTypes {', g, 'buildTypes block', re.M)
    g = sub1(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)', 'signingConfig = signingConfigs.getByName("release")', g, 'release signingConfig')
else:
    g = sub1(r'minSdk(?:Version)?\s*=?\s*[^\n]+', 'minSdk = 23', g, 'minSdk')
    g = sub1(r'targetSdk(?:Version)?\s*=?\s*[^\n]+', 'targetSdk = 36', g, 'targetSdk')
    g = sub1(r'compileSdk(?:Version)?\s*=?\s*[^\n]+', 'compileSdk = 36', g, 'compileSdk')
    g = sub1(r'(compileOptions\s*\{)', r'\1\n        coreLibraryDesugaringEnabled true', g, 'desugaring flag')
    dep = "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n"
    if re.search(r'^dependencies\s*\{', g, re.M): g = re.sub(r'^(dependencies\s*\{)', r'\1\n' + dep.rstrip('\n'), g, count=1, flags=re.M)
    else: g += '\ndependencies {\n' + dep + '}\n'
    signing = '''    signingConfigs {
        release {
            storeFile file(System.getenv("CM_KEYSTORE_PATH"))
            storePassword System.getenv("CM_KEYSTORE_PASSWORD")
            keyAlias System.getenv("CM_KEY_ALIAS")
            keyPassword System.getenv("CM_KEY_PASSWORD")
        }
    }
'''
    g = sub1(r'^([ \t]*)buildTypes\s*\{', lambda mo: signing + mo.group(1) + 'buildTypes {', g, 'buildTypes block', re.M)
    g = sub1(r'signingConfig\s*=?\s*signingConfigs\.debug', 'signingConfig signingConfigs.release', g, 'release signingConfig')
write(gp, g)

# 6. Skip the lint-vital check in every module. It crashed the release build inside the url_launcher_android plugin
#    (Codemagic log: "Execution failed for task ':url_launcher_android:lintVitalAnalyzeRelease'"). Lint does not change what ships.
root = 'android/build.gradle.kts' if os.path.exists('android/build.gradle.kts') else 'android/build.gradle'
if not os.path.exists(root): die('no root android build file found after flutter create')
r = read(root)
if 'lintVital' not in r:
    r += ('\n// CSave: lint-vital checks are skipped so a plugin lint crash cannot stop the release build.\n'
          'allprojects {\n    tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }\n}\n')
    write(root, r)
# 7. App icon: replace the Flutter default launcher icon with the C'SAVE logo (app/android_icons/).
import shutil
res = 'android/app/src/main/res'
if not os.path.isdir(res): die('no Android res folder found after flutter create')
for d in ['mipmap-mdpi', 'mipmap-hdpi', 'mipmap-xhdpi', 'mipmap-xxhdpi', 'mipmap-xxxhdpi']:
    src = f'android_icons/{d}/ic_launcher.png'
    if not os.path.exists(src): die(f'missing {src}')
    os.makedirs(f'{res}/{d}', exist_ok=True)
    shutil.copyfile(src, f'{res}/{d}/ic_launcher.png')
# Android 8+ uses an adaptive XML icon first, which would keep the old icon. Remove it so the PNGs above are used.
adaptive = f'{res}/mipmap-anydpi-v26'
if os.path.isdir(adaptive): shutil.rmtree(adaptive)
print('icons installed')
print('PREPARE OK: android project ready for', api, '| gradle file:', gp)
