import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api.dart';
import 'screens.dart';
import 'notify.dart';
import 'splash.dart';

const orange = Color(0xFFD4730A), deep = Color(0xFF9A4A0C), ink = Color(0xFF0B0B0B), panel = Color(0xFF1A1A1A);

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);
final appNavigator = GlobalKey<NavigatorState>();
const _lockGold = Color(0xFFFFC61A);   // same gold as the splash screen
const _lockWhite = Color(0xFFF5F5F5);

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: 'flutter_app.env');
    try { await Notify.init(); } catch (_) {}
    themeMode.value = (await store.read(key: 'theme')) == 'light' ? ThemeMode.light : ThemeMode.dark;
    FlutterError.onError = (d) { FlutterError.presentError(d); Telemetry.crash(d.exception, d.stack, screen: d.context?.toDescription() ?? d.library ?? ''); };
    Telemetry.session();
    runApp(const CSaveApp());
  }, (e, st) => Telemetry.crash(e, st));
}

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  return ThemeData(
    brightness: b,
    scaffoldBackgroundColor: dark ? ink : const Color(0xFFFAF6F0),
    colorScheme: ColorScheme.fromSeed(seedColor: orange, brightness: b, primary: orange),
    cardColor: dark ? panel : Colors.white,
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: dark ? panel : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
  );
}

class CSaveApp extends StatelessWidget {
  const CSaveApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (_, mode, __) => MaterialApp(
          title: 'CSave',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: mode,
          navigatorKey: appNavigator,
          builder: (context, child) => AppLock(child: child!),
          home: const Splash(next: Entry()),
        ),
      );
}

Future<void> toggleTheme() async {
  themeMode.value = themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  await store.write(key: 'theme', value: themeMode.value == ThemeMode.dark ? 'dark' : 'light');
}

/// Locks the screen when the app goes to the background (so the balance is hidden in the app switcher).
/// On return:
///  - fingerprint on: the member unlocks with the fingerprint. If it fails they can try again or use the password.
///  - fingerprint off: the normal password is asked for.
///  Every return locks the app immediately. The member stays signed in, so a cancelled prompt never logs them out.
class AppLock extends StatefulWidget {
  final Widget child;
  const AppLock({super.key, required this.child});
  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  bool locked = false, usePassword = false, busy = false, hasBio = false;
  DateTime? pausedAt;
  String? err;
  final pw = TextEditingController();
  String memberName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Api.onSessionExpired = () {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Your session expired. Please sign in again.')));
      setState(() => locked = false);
      appNavigator.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Entry()), (_) => false);
    };
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); pw.dispose(); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) async {
    // Only lock on paused (background). inactive fires for the notification shade.
    if (s == AppLifecycleState.paused) {
      if (await store.read(key: 'token') != null) { pausedAt ??= DateTime.now(); if (mounted) setState(() { locked = true; usePassword = false; err = null; }); _loadName(); }
    }
    if (s == AppLifecycleState.resumed && locked) {
      hasBio = await Bio.enabled;
      unlock();
    }
  }

  Future<void> _loadName() async {
    try {
      final me = await Api.call('GET', '/api/me');
      final n = (me['name'] ?? '').toString();
      if (mounted && n.isNotEmpty) setState(() => memberName = n);
    } catch (_) {}
  }

  void _open() { if (mounted) setState(() { locked = false; usePassword = false; pausedAt = null; err = null; busy = false; pw.clear(); }); }

  Future<void> unlock() async {
    if (busy) return;
    hasBio = await Bio.enabled;
    if (hasBio) {
      if (await Bio.prompt('Unlock CSave')) { _open(); return; }
      if (mounted) setState(() { usePassword = true; err = 'Fingerprint cancelled. Enter your password to continue.'; });   // cancel goes straight to the password
      return;
    }
    if (mounted) setState(() { usePassword = true; err = null; });   // no fingerprint: ask for the password and KEEP the session
  }

  Future<void> unlockWithPassword() async {
    final email = await store.read(key: 'email');
    if (email == null) { await _signOut(); return; }
    setState(() { busy = true; err = null; });
    try {
      final signedIn = await Api.login(email, pw.text);
      if (!signedIn) { await _signOut(); return; }   // staff also need an emailed code: full sign-in
      _open();
    } catch (e) {
      if (mounted) setState(() => err = friendly(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _signOut() async {
    await Api.clearAccount();
    _open();
    appNavigator.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Splash(next: Entry())), (_) => false);
  }

  Widget _goldButton(String text, VoidCallback? onTap) => SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _lockGold,
            foregroundColor: const Color(0xFF080808),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          ),
          onPressed: onTap,
          child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      );

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (locked)
          Positioned.fill(
            child: Material(
              color: const Color(0xFF080808),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(children: [
                    const SizedBox(height: 32),
                    Image.asset('assets/logo.png', width: 150, height: 150),
                    const SizedBox(height: 16),
                    Text(memberName.toUpperCase(), style: const TextStyle(color: _lockWhite, fontSize: 22, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (usePassword) ...[
                      const Text('Enter your password to continue', textAlign: TextAlign.center, style: TextStyle(color: _lockWhite, fontSize: 18)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: pw,
                        obscureText: true,
                        style: const TextStyle(color: _lockWhite),
                        onSubmitted: (_) => unlockWithPassword(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: _lockGold),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _lockGold)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _lockGold, width: 2)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _goldButton(busy ? 'Checking...' : 'Unlock', busy ? null : unlockWithPassword),
                      if (hasBio)
                        TextButton(
                          onPressed: () => setState(() { usePassword = false; err = null; }),
                          child: const Text('Verify Fingerprint', style: TextStyle(color: _lockGold)),
                        ),
                    ] else if (hasBio) ...[
                      const Icon(Icons.fingerprint, size: 96, color: _lockGold),
                      const SizedBox(height: 14),
                      const Text('Click to log in with Fingerprint', textAlign: TextAlign.center, style: TextStyle(color: _lockWhite, fontSize: 18)),
                      const SizedBox(height: 18),
                      _goldButton('Verify Fingerprint', busy ? null : unlock),
                    ],
                    if (err != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(err!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                      ),
                    const Spacer(),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      TextButton(onPressed: _signOut, child: const Text('Logout', style: TextStyle(color: _lockGold, fontSize: 16))),
                      if (!usePassword) ...[
                        const Text('|', style: TextStyle(color: _lockGold)),
                        TextButton(
                          onPressed: () => setState(() { usePassword = true; err = null; }),
                          child: const Text('Login with Password', style: TextStyle(color: _lockGold, fontSize: 16)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ),
          ),
      ]);
}

/// Members must agree before the money coach or help chat sends their data to the AI provider.
/// Returns true when they have agreed (now or before). Saying no leaves the rest of the app working.
bool _aiAgreed = false;
Future<bool> ensureAiConsent(BuildContext context) async {
  if (_aiAgreed) return true;
  try {
    final me = await Api.call('GET', '/api/me');
    if (me['aiConsent'] == true) { _aiAgreed = true; return true; }
  } catch (_) { return false; }
  if (!context.mounted) return false;
  bool agree = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('How we use AI'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('The money coach and the Help chat use an AI service run by another company. Its servers may be outside Nigeria.\n\n'
            'To answer you we send them your first name and what you type. For the coach we also send your budget, spending categories, goals and savings plan balances.\n\n'
            'We never send your PIN, password, ID number or bank details.\n\n'
            'You can say no and still use the rest of CSave, and you can always tap "Talk to a person". You can withdraw your agreement any time by asking customer service.'),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: agree, onChanged: (v) => set(() => agree = v ?? false), controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I agree to this.')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No thanks')),
        FilledButton(onPressed: agree ? () => Navigator.pop(c, true) : null, child: const Text('Agree')),
      ],
    )),
  );
  if (ok != true) return false;
  try { await Api.call('POST', '/api/me/ai-consent', {'agree': true}); _aiAgreed = true; return true; } catch (_) { return false; }
}

class Entry extends StatelessWidget {
  const Entry({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: store.read(key: 'token'),
        builder: (c, s) => s.connectionState != ConnectionState.done
            ? const Scaffold()
            : s.data == null ? const LoginScreen() : const Shell(),
      );
}
