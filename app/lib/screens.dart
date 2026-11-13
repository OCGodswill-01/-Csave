import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'autosave.dart';
import 'budget.dart';
import 'coach.dart';
import 'promo.dart';
import 'support.dart';
import 'wallet.dart';
import 'main.dart';
import 'payment_watch.dart';

// ---------------- LOGIN ----------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final email = TextEditingController(), pass = TextEditingController();
  String? err; bool busy = false, bioReady = false, hide = true;

  @override
  void initState() { super.initState(); _checkBio(); }
  Future<void> _checkBio() async {
    final ok = await Bio.enabled && await Bio.available() && await store.read(key: 'bioPass') != null;
    if (mounted) setState(() => bioReady = ok);
  }

  Future<void> _go() async {
    setState(() { busy = true; err = null; });
    try {
      final ok = await Api.login(email.text.trim(), pass.text);
      if (!ok && !await _otp(email.text.trim())) { if (mounted) setState(() => busy = false); return; }
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Shell()));
    } catch (e) { if (mounted) setState(() => err = friendly(e)); }
    if (mounted) setState(() => busy = false);
  }

  /// Staff accounts confirm with a 6-digit code sent to their email.
  Future<bool> _otp(String em) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (x) => AlertDialog(
      title: const Text('Enter your code'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('We emailed you a 6-digit code. It works for 10 minutes.'),
        TextField(controller: c, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Code'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Verify'))]));
    if (ok != true) return false;
    try { await Api.verifyOtp(em, c.text.trim()); return true; } catch (e) { if (mounted) setState(() => err = friendly(e)); return false; }
  }

  Future<void> _fingerprint() async {
    if (!await Bio.prompt('Sign in to CSave')) return;
    try {
      final em = (await store.read(key: 'email'))!;
      final ok = await Api.login(em, (await store.read(key: 'bioPass'))!);
      if (!ok && !await _otp(em)) return;
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Shell()));
    } catch (e) {
      // 401 here means the stored password is no longer right (it was changed or reset). Forget it NOW, so the fingerprint
      // can never keep retrying a wrong password and lock the account.
      if (e is ApiError && e.status == 401) {
        await store.delete(key: 'bioPass');
        await Bio.setEnabled(false);
        if (mounted) setState(() { bioReady = false; err = 'Your password has changed. Sign in with your password, then turn the fingerprint on again in Profile.'; });
      } else if (mounted) { setState(() => err = friendly(e)); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final grad = dark
        ? const [Color(0xFF0B0B0B), Color(0xFF2A1D08), Color(0xFF6B3A0C)]
        : const [Color(0xFFFFF8EE), Color(0xFFFFEBD0), Color(0xFFFFD2A0)];
    final soft = Theme.of(context).colorScheme.onSurface.withOpacity(.65);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: grad, begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(22, 4, 22, 24), children: [
            Align(alignment: Alignment.centerRight, child: IconButton(
              tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
              onPressed: toggleTheme, icon: Icon(dark ? Icons.light_mode : Icons.dark_mode, color: orange))),
            Center(child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.asset('assets/logo.png', height: 96))),
            const SizedBox(height: 14),
            const Center(child: Text('CSave', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800))),
            const SizedBox(height: 6),
            Center(child: Text('contribute with purpose. Build with discipline.\nMove towards your dream',
                textAlign: TextAlign.center, style: TextStyle(color: orange.withOpacity(.95), fontSize: 14, height: 1.4))),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: (dark ? Colors.white : Colors.white).withOpacity(dark ? .06 : .65),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: orange.withOpacity(.25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Welcome back', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                Text('Sign in to your account', style: TextStyle(color: soft, fontSize: 16)),
                const SizedBox(height: 20),
                const Text('Email address'),
                const SizedBox(height: 6),
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'you@example.com')),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Password'),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotScreen())),
                    child: const Text('Forgot password?', style: TextStyle(color: orange))),
                ]),
                const SizedBox(height: 6),
                TextField(
                  controller: pass, obscureText: hide,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide))),
                ),
                if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF9A00), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: busy ? null : _go, child: const Text('Sign In', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                const SizedBox(height: 18),
                Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: soft))), const Expanded(child: Divider())]),
                const SizedBox(height: 16),
                // Fingerprint replaces "Continue with Google"
                Center(child: InkResponse(
                  onTap: bioReady ? _fingerprint : () => setState(() => err = 'Turn on fingerprint in Profile after your first sign in.'),
                  radius: 56,
                  child: Container(
                    width: 84, height: 84,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: orange, width: 2), color: Theme.of(context).cardColor),
                    child: const Icon(Icons.fingerprint, size: 54, color: orange)))),
                const SizedBox(height: 6),
                Center(child: Text('Touch to sign in', style: TextStyle(color: soft))),
              ]),
            ),
            const SizedBox(height: 18),
            Center(child: Wrap(alignment: WrapAlignment.center, children: [
              Text("Don't have an account? ", style: TextStyle(color: soft)),
              GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('Create account', style: TextStyle(color: orange, fontWeight: FontWeight.bold))),
            ])),
          ]),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterState();
}

class _RegisterState extends State<RegisterScreen> {
  final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController(), ref = TextEditingController();
  String? err; bool busy = false;
  Future<void> _go() async {
    setState(() { busy = true; err = null; });
    try {
      final d = await Api.call('POST', '/api/auth/register', {'name': name.text.trim(), 'email': email.text.trim(), 'password': pass.text, 'referralCode': ref.text.trim()});
      await store.write(key: 'token', value: d['token']); await store.write(key: 'email', value: email.text.trim());
      if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Shell()), (_) => false);
    } catch (e) { setState(() => err = friendly(e)); }
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Use your full legal name. It must match the name on the bank account you withdraw to.'),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address')),
          const SizedBox(height: 10),
          TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password (8+ characters)')),
          const SizedBox(height: 10),
          TextField(controller: ref, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Referral code (optional)')),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
          const SizedBox(height: 16),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: busy ? null : _go, child: const Text('Create account')),
        ]),
      );
}

// ---------------- SHELL ----------------
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int i = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkReflection(context)); // weekly pop-up, Friday to Sunday
  }
  @override
  Widget build(BuildContext context) {
    final pages = [const HomePage(), const SavingsPage(), const CoachPage(), const BudgetPage(), const ProfilePage()];
    return Scaffold(
      body: SafeArea(child: pages[i]),
      floatingActionButton: FloatingActionButton.small(
        backgroundColor: orange, child: const Icon(Icons.support_agent),
        onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const SupportChat())),
      bottomNavigationBar: NavigationBar(
        selectedIndex: i, onDestinationSelected: (v) => setState(() => i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.savings), label: 'Savings'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Insights'),
          NavigationDestination(icon: Icon(Icons.calculate), label: 'Budget'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class Soon extends StatelessWidget {
  final String name;
  const Soon(this.name, {super.key});
  @override
  Widget build(BuildContext context) => Center(child: Text('$name arrives in the next phase.'));
}

// ---------------- HOME (numbers and money hidden) ----------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  late Future f = Api.call('GET', '/api/me');
  late Future ban = Api.call('GET', '/api/announcements/banners');
  void refresh() => setState(() { f = Api.call('GET', '/api/me'); ban = Api.call('GET', '/api/announcements/banners'); });

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: f,
        builder: (c, s) {
          final d = s.data;
          final name = (d?['name'] ?? '').toString().split(' ').first;
          final code = d?['referralCode'];
          final reward = d?['referralReward'];   // null when referrals are off, or the code is still locked
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text('Good day, $name', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              IconButton(tooltip: 'Notifications', icon: const Icon(Icons.notifications),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()))),
            ]),
            FutureBuilder(future: ban, builder: (c, s) {
              final l = s.hasData ? List<Map>.from(s.data) : <Map>[];
              if (l.isEmpty) return const SizedBox(height: 12);
              return Padding(padding: const EdgeInsets.only(top: 10, bottom: 8), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340),
                  child: BannerCarousel(urls: l.map((x) => x['url'] as String).toList(), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()))))));
            }),
            const Text('Total savings'),
            const Text('₦ ••••••', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            // No Transfer button by design. Withdraw lives inside each plan.
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _Action('Add money', Icons.add, orange, onTap: () => pickPlanAndAdd(context)),
              _Action('Wallet', Icons.account_balance_wallet, Colors.tealAccent, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()))),
              const _Action('Converter', Icons.currency_exchange, Colors.blueAccent),
            ]),
            const SizedBox(height: 20),
            if (d != null && code != null)
              Card(color: const Color(0xFF6B3A0C), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('MY REFERRAL CODE', style: TextStyle(color: Colors.white70)),
                Text(code, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                Text(reward != null ? 'Reward: $reward.' : 'Share this code when you invite friends.', style: const TextStyle(color: Colors.white70)),
              ])))
            else if (d != null)
              Card(child: ListTile(
                leading: const Icon(Icons.lock, color: orange),
                title: const Text('Referral code locked'),
                subtitle: const Text('Complete KYC and pay the ₦5,000 membership fee to unlock your referral code.'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MembershipScreen())).then((_) => refresh()))),
            const SizedBox(height: 8),
            const Converter(),
          ]);
        },
      );
}

class _Action extends StatelessWidget {
  final String t; final IconData i; final Color c; final VoidCallback? onTap;
  const _Action(this.t, this.i, this.c, {this.onTap});
  @override
  Widget build(BuildContext context) => InkResponse(onTap: onTap, child: Column(children: [
        CircleAvatar(radius: 28, backgroundColor: c, child: Icon(i, color: Colors.white)),
        const SizedBox(height: 6), Text(t, style: const TextStyle(fontSize: 12)),
      ]));
}

// ---------------- CONVERTER (live rates from the server) ----------------
const symbols = {'NGN': '₦', 'USD': '\$', 'GBP': '£', 'EUR': '€', 'CNY': '¥'};

class Converter extends StatefulWidget {
  const Converter({super.key});
  @override
  State<Converter> createState() => _ConverterState();
}

class _ConverterState extends State<Converter> {
  String from = 'NGN', to = 'CNY'; final amt = TextEditingController(text: '10000');
  Map<String, double>? rates; // per 1 unit in NGN; null means the live rate is unavailable
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await Api.fx();
      if (mounted) setState(() { rates = r == null ? null : {'NGN': 1.0, ...r}; loading = false; });
    } catch (_) {
      if (mounted) setState(() { rates = null; loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())));
    final rt = rates;
    if (rt == null) {
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Currency converter', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Live rate unavailable right now. Please try again later.'),
        TextButton(onPressed: () { setState(() => loading = true); _load(); }, child: const Text('Try again')),
      ])));
    }
    final v = double.tryParse(amt.text) ?? 0;
    final out = v * rt[from]! / rt[to]!;
    DropdownButton<String> dd(String val, ValueChanged<String?> f) =>
        DropdownButton(value: val, items: rt.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(), onChanged: f);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Currency converter', style: TextStyle(fontWeight: FontWeight.bold)),
      TextField(controller: amt, keyboardType: TextInputType.number, onChanged: (_) => setState(() {})),
      Row(children: [dd(from, (x) => setState(() => from = x!)), const Icon(Icons.arrow_forward), dd(to, (x) => setState(() => to = x!))]),
      Text('${symbols[to]}${out.toStringAsFixed(2)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: orange)),
    ])));
  }
}

// ---------------- SAVINGS: C PLAN + MISSION PLAN ----------------
class SavingsPage extends StatefulWidget {
  const SavingsPage({super.key});
  @override
  State<SavingsPage> createState() => _SavingsState();
}

class _SavingsState extends State<SavingsPage> {
  late Future f = Api.call('GET', '/api/plans');
  void refresh() => setState(() => f = Api.call('GET', '/api/plans'));

  Future<void> open(String type) async {
    final ctl = TextEditingController();
    DateTime? date = DateTime.now().add(const Duration(days: 90));
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
          title: Text(type == 'C_PLAN' ? 'Open C Plan' : 'Open Mission Plan'),
          content: type == 'C_PLAN'
              ? OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(context: c, firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: date ?? DateTime.now().add(const Duration(days: 90)));
                    if (d != null) set(() => date = d);
                  },
                  child: Text(date == null ? 'Pick unlock date' : date.toString().split(' ').first))
              : TextField(controller: ctl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Target amount (₦)')),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open plan'))])));
    if (ok != true) return;
    try {
      await Api.call('POST', '/api/plans', {'type': type, 'unlockDate': date?.toIso8601String(), 'targetAmount': double.tryParse(ctl.text)});
      refresh();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e)))); }
  }

  Future<void> _extend(Map p) async {
    var minDate = DateTime.now().add(const Duration(days: 1));
    final maxDate = DateTime.now().add(const Duration(days: 3650));
    // A lock can only be moved LATER. The first allowed day is the day after the current unlock date (the server enforces this too).
    try {
      final existing = DateTime.parse(p['unlockDate'].toString()).toLocal();
      final dayAfter = DateTime(existing.year, existing.month, existing.day).add(const Duration(days: 1));
      if (dayAfter.isAfter(minDate)) minDate = dayAfter;
    } catch (_) {}
    if (minDate.isAfter(maxDate)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This plan is already locked for the longest time allowed.')));
      return;
    }
    var initial = minDate.add(const Duration(days: 90));
    if (initial.isAfter(maxDate)) initial = maxDate;
    final d = await showDatePicker(context: context, firstDate: minDate, lastDate: maxDate, initialDate: initial);
    if (d == null) return;
    try {
      await Api.extendPlan(p['_id']?.toString() ?? p['id'].toString(), d);
      refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unlock date extended.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  Future<void> _togglePause(Map p) async {
    final id = p['_id']?.toString() ?? p['id']?.toString() ?? '';
    final paused = p['paused'] == true;
    try {
      if (paused) await Api.resumePlan(id); else await Api.pausePlan(id);
      refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(paused ? 'Plan resumed.' : 'Plan paused.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: f,
        builder: (c, s) {
          if (!s.hasData) return Center(child: s.hasError ? Text(friendly(s.error!)) : const CircularProgressIndicator());
          final plans = List<Map>.from(s.data);
          Map? get(String t) => plans.cast<Map?>().firstWhere((p) => p!['type'] == t, orElse: () => null);
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Your savings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _tile('C Plan', 'Time-based. Withdraw when your date arrives.', get('C_PLAN'), 'C_PLAN'),
            _tile('Mission Plan', 'Goal-based. Withdraw when you hit your target.', get('MISSION'), 'MISSION'),
          ]);
        },
      );

  Widget _tile(String title, String sub, Map? p, String type) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(sub, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 10),
        if (p == null) FilledButton(onPressed: () => open(type), child: Text('Open $title'))
        else ...[
          Text('₦ ••••••', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(type == 'C_PLAN' ? 'Unlocks ${p['unlockDate'].toString().split('T').first}' : 'Target ₦${p['targetAmount']}'),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p['canWithdraw'] ? Colors.redAccent : Colors.grey.shade800),
            onPressed: () => p['canWithdraw']
                ? showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => WithdrawSheet(plan: p, done: refresh))
                : ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(p['reason'] ?? 'Not yet unlocked.'))),
            child: const Text('Withdraw')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => addMoneyDialog(context, p, onPaid: () { if (mounted) refresh(); }), icon: const Icon(Icons.add), label: const Text('Add money'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => AutoSaveSheet(plan: p, done: refresh)), icon: const Icon(Icons.autorenew), label: const Text('Auto-save'))),
          ]),
          if (type == 'C_PLAN') ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => _extend(p), icon: const Icon(Icons.event), label: const Text('Extend'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => _togglePause(p), icon: Icon(p['paused'] == true ? Icons.play_arrow : Icons.pause), label: Text(p['paused'] == true ? 'Resume' : 'Pause'))),
            ]),
          ],
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('Add money any time, or auto-save daily, weekly or monthly from your card.', style: TextStyle(color: Colors.grey, fontSize: 12))),
        ],
      ])));
}

// ---------------- WITHDRAW (fingerprint or PIN, name-checked on server) ----------------
class WithdrawSheet extends StatefulWidget {
  final Map plan; final VoidCallback done;
  const WithdrawSheet({super.key, required this.plan, required this.done});
  @override
  State<WithdrawSheet> createState() => _WithdrawState();
}

class _WithdrawState extends State<WithdrawSheet> {
  final acct = TextEditingController(), pin = TextEditingController();
  List<Map>? banks;   // Flutterwave's bank list, so the member picks a bank instead of typing a code
  String? bankCode;
  String? msg; bool busy = false;

  @override
  void initState() {
    super.initState();
    Api.banks().then((b) { if (mounted) setState(() => banks = b); }).catchError((e) {
      if (mounted) setState(() => msg = friendly(e));
    });
  }

  @override
  void dispose() { acct.dispose(); pin.dispose(); super.dispose(); }

  Future<void> submit() async {
    final account = acct.text.trim();
    final code = bankCode;
    if (!RegExp(r'^\d{10}$').hasMatch(account)) { setState(() => msg = 'Enter the 10-digit account number.'); return; }
    if (code == null) { setState(() => msg = 'Choose the bank that holds the account.'); return; }
    if (!RegExp(r'^\d{4}$').hasMatch(pin.text)) { setState(() => msg = 'Enter your 4-digit PIN.'); return; }
    // Fingerprint (if on) opens the gate; the server still verifies the 4-digit PIN.
    if (await Bio.enabled && !await Bio.prompt('Confirm withdrawal')) { if (mounted) setState(() => msg = 'Fingerprint not confirmed.'); return; }
    setState(() { busy = true; msg = null; });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await Api.call('POST', '/api/plans/${widget.plan['_id']}/withdraw', {'pin': pin.text, 'accountNumber': account, 'bankCode': code});
      widget.done();
      if (r is Map && r['pending'] == true) {
        // The payout may or may not have gone out. Keep the button off so the member cannot pay out twice.
        if (mounted) setState(() { msg = 'We could not confirm your withdrawal yet. Please do not try again. Our team will check it and update you.'; busy = true; });
        return;
      }
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Withdrawal sent to your bank account.')));
    } catch (e) {
      if (mounted) setState(() { msg = friendly(e); busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Withdraw to your own account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(controller: acct, keyboardType: TextInputType.number, maxLength: 10,
              decoration: const InputDecoration(labelText: 'Account number', counterText: '')),
          const SizedBox(height: 8),
          if (banks == null)
            const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator())
          else
            DropdownButtonFormField<String>(
              value: bankCode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Bank'),
              items: banks!.map<DropdownMenuItem<String>>((b) => DropdownMenuItem(
                    value: b['code'].toString(),
                    child: Text(b['name'].toString(), overflow: TextOverflow.ellipsis),
                  )).toList(),
              onChanged: (v) => setState(() => bankCode = v),
            ),
          const SizedBox(height: 8),
          TextField(controller: pin, obscureText: true, maxLength: 4, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '4-digit PIN', counterText: '')),
          if (msg != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(msg!, style: const TextStyle(color: Colors.redAccent))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: busy || banks == null ? null : submit,
            child: const Text('Withdraw'),
          ),
        ]),
      );
}

// ---------------- PROFILE ----------------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfileState();
}

/// Shows the start and the domain of an email, never the whole address. Safe for any input.
String maskEmail(String e) {
  final at = e.indexOf('@');
  if (at < 1) return '•••';
  return '${e.substring(0, at == 1 ? 1 : 2)}•••${e.substring(at)}';
}

class _ProfileState extends State<ProfilePage> {
  late Future f = Api.call('GET', '/api/me');
  bool bio = false;
  @override
  void initState() { super.initState(); Bio.enabled.then((v) => setState(() => bio = v)); }

  Future<void> toggle(bool v) async {
    if (v) {
      if (!await Bio.available()) { _snack('No fingerprint is set up on this phone. Add one in phone Settings first.'); return; }
      if (!await Bio.prompt('Turn on fingerprint for CSave')) return;
      final pw = await _askPassword();
      if (pw == null || pw.isEmpty) return;
      // Check the password first, so a typo is never stored as the fingerprint sign-in password.
      try {
        final r = await Api.call('POST', '/api/me/verify-password', {'password': pw});
        if (r['ok'] != true) { _snack('That password is not right. Fingerprint was not turned on.'); return; }
      } catch (e) { _snack(friendly(e)); return; }
      await store.write(key: 'bioPass', value: pw);   // kept in Keystore/Keychain, released only after fingerprint
    } else { await store.delete(key: 'bioPass'); }
    await Bio.setEnabled(v); if (mounted) setState(() => bio = v);
  }

  Future<String?> _askPassword() {
    final c = TextEditingController();
    return showDialog<String>(context: context, builder: (_) => AlertDialog(
          title: const Text('Confirm your password'),
          content: TextField(controller: c, obscureText: true),
          actions: [FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Confirm'))]));
  }

  Future<void> setPin() async {
    final c = TextEditingController();
    final p = await showDialog<String>(context: context, builder: (_) => AlertDialog(
          title: const Text('Set 4-digit withdrawal PIN'),
          content: TextField(controller: c, obscureText: true, maxLength: 4, keyboardType: TextInputType.number),
          actions: [FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save PIN'))]));
    if (p == null) return;
    try { await Api.call('POST', '/api/me/pin', {'pin': p}); _snack('PIN saved.'); } catch (e) { _snack(friendly(e)); }
  }

  void _snack(String m) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))); }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: f,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final d = s.data; final kyc = d['kycStatus'] == 'approved';
          final email = d['email'].toString();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(d['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(maskEmail(email), style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Card(child: ListTile(
              leading: Icon(kyc ? Icons.verified : Icons.flag, color: kyc ? Colors.green : Colors.redAccent),
              title: Text(kyc ? 'KYC verified' : d['kycStatus'] == 'pending' ? 'KYC under review' : d['kycStatus'] == 'rejected' ? 'KYC needs attention' : 'KYC not complete'),
              subtitle: Text(kyc ? 'You can withdraw.' : d['kycStatus'] == 'pending' ? 'We will notify you when it is approved.' : d['kycStatus'] == 'rejected' && d['kycRejectReason'] != null ? 'Reason: ${d['kycRejectReason']}. Tap to correct and submit again.' : 'Complete KYC to withdraw and unlock referrals.'),
              onTap: kyc || d['kycStatus'] == 'pending' ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KycScreen())).then((_) => setState(() => f = Api.call('GET', '/api/me'))))),
            Card(child: ListTile(
              leading: Icon(d['membershipPaid'] ? Icons.card_membership : Icons.flag, color: d['membershipPaid'] ? Colors.green : Colors.redAccent),
              title: Text(d['membershipPaid'] ? 'Member ${d['membershipId']}' : 'Membership fee not paid'),
              subtitle: Text(d['membershipPaid'] ? 'Your membership is active.' : '₦5,000 one-time membership fee. Terms apply.'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MembershipScreen())).then((_) => setState(() => f = Api.call('GET', '/api/me'))))),
            if (d['role'] == 'admin' || d['role'] == 'support')
              Card(child: ListTile(leading: const Icon(Icons.headset_mic, color: orange), title: const Text('Customer service dashboard'), subtitle: const Text('Tickets, AI answers to confirm, approved answers'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportDashboard())))),
            Card(child: SwitchListTile(title: const Text('Fingerprint'), subtitle: const Text('Sign in and confirm withdrawals with your fingerprint'), value: bio, onChanged: toggle)),
            Card(child: ListTile(leading: const Icon(Icons.brightness_6), title: const Text('Light / dark mode'), trailing: Switch(value: Theme.of(context).brightness == Brightness.light, onChanged: (_) async { await toggleTheme(); setState(() {}); }))),
            Card(child: ListTile(leading: const Icon(Icons.pin), title: Text(d['hasPin'] ? 'Change withdrawal PIN' : 'Set withdrawal PIN'), onTap: setPin)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () async { await Api.forgetDevice(); if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const Entry()), (_) => false); }, child: const Text('Sign out')),
          ]);
        },
      );
}

// ---------------- KYC ----------------
class KycScreen extends StatefulWidget {
  const KycScreen({super.key});
  @override
  State<KycScreen> createState() => _KycState();
}

class _KycState extends State<KycScreen> {
  final f = {for (var k in ['phone', 'residentialAddress', 'placeOfOrigin', 'occupation', 'dob', 'idNumber', 'nextOfKin']) k: TextEditingController()};
  String idType = 'NIN'; String? err; bool busy = false;
  String? gender, marital, proof;

  Future<void> submit() async {
    setState(() { busy = true; err = null; });
    try {
      await Api.call('POST', '/api/kyc', {for (var e in f.entries) e.key: e.value.text.trim(), 'idType': idType, 'gender': gender, 'maritalStatus': marital, 'proofOfAddress': proof});
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('KYC submitted. We will review it.'))); Navigator.pop(context); }
    } catch (e) { setState(() => err = friendly(e)); }
    if (mounted) setState(() => busy = false);
  }

  Widget _t(String k, String label, [TextInputType? t]) => Padding(padding: const EdgeInsets.only(bottom: 10),
      child: TextField(controller: f[k], keyboardType: t, decoration: InputDecoration(labelText: label)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Verify your identity')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          _t('phone', 'Phone number', TextInputType.phone),
          _t('dob', 'Date of birth (DD/MM/YYYY)'),
          DropdownButtonFormField<String>(value: gender, decoration: const InputDecoration(labelText: 'Gender'),
              items: ['Male', 'Female'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => gender = v)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: marital, decoration: const InputDecoration(labelText: 'Marital status'),
              items: ['Single', 'Married', 'Divorced', 'Widowed'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => marital = v)),
          const SizedBox(height: 10),
          _t('occupation', 'Occupation'),
          _t('placeOfOrigin', 'Place of origin (state and LGA)'),
          _t('residentialAddress', 'Residential address (where you live now)'),
          DropdownButtonFormField<String>(value: proof, decoration: const InputDecoration(labelText: 'Proof of address'),
              items: ['NEPA bill', 'Water bill', 'Tenancy agreement', 'Bank statement', 'Other utility bill'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => proof = v)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: idType, decoration: const InputDecoration(labelText: 'ID type'),
              items: ['NIN', 'BVN', 'Voter card', "Driver's licence", 'International passport'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => idType = v!)),
          const SizedBox(height: 10),
          _t('idNumber', 'ID number'),
          _t('nextOfKin', 'Next of kin (name and phone)'),
          const Text('Your ID number is stored encrypted. Staff open it only to check your ID. Staff lists show just the last 4 digits.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
          const SizedBox(height: 16),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: busy ? null : submit, child: const Text('Submit KYC')),
        ]),
      );
}

// ---------------- MEMBERSHIP (₦5,000) ----------------
class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});
  @override
  State<MembershipScreen> createState() => _MemState();
}

class _MemState extends State<MembershipScreen> {
  late Future f = Api.call('GET', '/api/me');
  String? err; bool busy = false;

  PaymentWatcher? _payment;

  @override
  void dispose() { _payment?.stop(); super.dispose(); }

  Future<void> pay() async {
    setState(() { busy = true; err = null; });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final d = await Api.call('POST', '/api/membership/pay');
      final link = d['link'] as String?;
      if (link == null) throw ApiError('Could not start the payment. Try again.');
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      // Watch for the fee to clear, so the membership ID appears here without a manual check.
      _payment?.stop();
      _payment = PaymentWatcher(
        check: () async => (await Api.call('GET', '/api/me'))['membershipPaid'] == true,
        onPaid: () {
          messenger.showSnackBar(const SnackBar(content: Text('Payment received. Your membership is active.')));
          if (mounted) setState(() => f = Api.call('GET', '/api/me'));
        },
      )..start();
      messenger.showSnackBar(const SnackBar(
          content: Text('Complete the payment in the browser. This page updates when it arrives.')));
    } catch (e) { if (mounted) setState(() => err = friendly(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Membership')),
        body: FutureBuilder(future: f, builder: (c, s) {
          if (s.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendly(s.error!), textAlign: TextAlign.center)));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final d = s.data;
          return ListView(padding: const EdgeInsets.all(20), children: [
            if (d['membershipPaid']) ...[
              const Icon(Icons.verified, color: Colors.green, size: 56),
              Center(child: Text(d['membershipId'], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: orange))),
              const Center(child: Text('Your membership is active. We emailed your ID and the cooperative bylaws.', textAlign: TextAlign.center)),
            ] else ...[
              const Text('₦5,000', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: orange)),
              const Text('One-time compulsory membership fee. Terms and conditions apply.'),
              const SizedBox(height: 12),
              Text(d['kycStatus'] == 'none' || d['kycStatus'] == 'rejected' ? 'Submit your KYC first. Go to Profile, then KYC.' : 'After you pay, your membership ID appears in your notifications and in your email.'),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
              const SizedBox(height: 16),
              FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: busy ? null : pay, child: const Text('Pay ₦5,000')),
              OutlinedButton(onPressed: () => setState(() => f = Api.call('GET', '/api/me')), child: const Text('I have paid. Check again')),
            ],
          ]);
        }),
      );
}

// ---------------- NOTIFICATIONS ----------------
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});
  @override
  Widget build(BuildContext context) {
    Api.call('POST', '/api/notifications/read');
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: FutureBuilder(future: Api.call('GET', '/api/notifications'), builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final l = List<Map>.from(s.data);
        if (l.isEmpty) return const Center(child: Text('Nothing yet. Updates about your account show up here.'));
        return ListView(padding: const EdgeInsets.all(12), children: l.map((n) {
          final imgs = List<String>.from(n['images'] ?? []);
          return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (imgs.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: BannerCarousel(urls: imgs)))),
            Text(n['title'], style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(n['body']),
          ])));
        }).toList());
      }),
    );
  }
}

// ---------------- FORGOT PASSWORD ----------------
class ForgotScreen extends StatefulWidget {
  const ForgotScreen({super.key});
  @override
  State<ForgotScreen> createState() => _ForgotState();
}

class _ForgotState extends State<ForgotScreen> {
  final email = TextEditingController(), code = TextEditingController(), pass = TextEditingController();
  bool sent = false, busy = false; String? err;

  Future<void> go() async {
    setState(() { busy = true; err = null; });
    try {
      if (!sent) { await Api.call('POST', '/api/auth/forgot', {'email': email.text.trim()}); setState(() => sent = true); }
      else {
        await Api.call('POST', '/api/auth/reset', {'email': email.text.trim(), 'code': code.text.trim(), 'newPassword': pass.text});
        await store.delete(key: 'bioPass'); await Bio.setEnabled(false);   // the old password is dead: switch the fingerprint sign-in off
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed. Sign in with your new password.'))); Navigator.pop(context); }
      }
    } catch (e) { if (mounted) setState(() => err = friendly(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address')),
          if (sent) ...[
            const SizedBox(height: 10),
            const Text('If that email has an account, we sent a 6-digit code. It expires in 10 minutes.'),
            const SizedBox(height: 10),
            TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: '6-digit code')),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'New password (8+ characters)')),
          ],
          if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err ?? '', style: const TextStyle(color: Colors.redAccent))),
          const SizedBox(height: 16),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: busy ? null : go, child: Text(sent ? 'Change password' : 'Send code')),
        ]),
      );
}
