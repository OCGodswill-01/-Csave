import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'main.dart' show orange, deep, ink, panel;
import 'payment_watch.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletState();
}

class _WalletState extends State<WalletScreen> {
  double? balance;
  bool loading = true;
  String? err;
  final amountCtrl = TextEditingController();
  String method = 'card';
  List plans = [];
  String? selectedPlan;
  final transferCtrl = TextEditingController();
  bool busy = false;
  PaymentWatcher? _payment;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _payment?.stop();
    amountCtrl.dispose();
    transferCtrl.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() { loading = true; err = null; });
    try {
      final w = await Api.wallet();
      final p = await Api.call('GET', '/api/plans');
      if (!mounted) return;
      setState(() {
        balance = (w['balance'] as num?)?.toDouble() ?? 0;
        plans = p is List ? p : [];
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { err = friendly(e); loading = false; });
    }
  }

  Future<void> fund() async {
    final amt = double.tryParse(amountCtrl.text.trim());
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount above zero.')));
      return;
    }
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final before = balance ?? 0;
    try {
      final r = await Api.fundWallet(amt, method);
      final link = r['link'] as String?;
      if (link == null) throw ApiError('Could not open the payment page. Try again.');
      // launchUrl reports whether the browser opened. Do not pre-check with canLaunchUrl: on Android 11+ that
      // returns false unless the manifest declares <queries>, which would block payments on a working phone.
      final opened = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      if (!opened) throw ApiError('Could not open the payment page. Try again.');
      _watchForPayment(before, messenger);
      messenger.showSnackBar(const SnackBar(
          content: Text('Complete the payment in the browser. Your balance updates here when it arrives.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendly(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Watches the balance so the member sees the new money without coming back to tap anything.
  void _watchForPayment(double before, ScaffoldMessengerState messenger) {
    _payment?.stop();
    _payment = PaymentWatcher(
      check: () async {
        final w = await Api.wallet();
        final now = (w['balance'] as num?) ?? 0;
        return now.toDouble() > before;
      },
      onPaid: () {
        messenger.showSnackBar(const SnackBar(content: Text('Payment received. Your wallet is updated.')));
        if (mounted) refresh();
      },
    )..start();
  }

  Future<void> moveToPlan() async {
    final amt = double.tryParse(transferCtrl.text.trim());
    if (amt == null || amt <= 0 || selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a plan and amount.')));
      return;
    }
    setState(() => busy = true);
    try {
      await Api.transferToPlan(selectedPlan!, amt);
      transferCtrl.clear();
      await refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved to plan.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet'), backgroundColor: ink),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: orange))
          : RefreshIndicator(
              onRefresh: refresh,
              color: orange,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (err != null) Text(err!, style: const TextStyle(color: Colors.redAccent)),
                  Card(
                    color: panel,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        const Text('Available balance', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text('₦ ${(balance ?? 0).toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: orange)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Fund wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (NGN)', prefixText: '₦ '),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(label: const Text('Card'), selected: method == 'card', onSelected: (_) => setState(() => method = 'card'), selectedColor: deep),
                    ChoiceChip(label: const Text('USSD'), selected: method == 'ussd', onSelected: (_) => setState(() => method = 'ussd'), selectedColor: deep),
                    ChoiceChip(label: const Text('Bank transfer'), selected: method == 'bank', onSelected: (_) => setState(() => method = 'bank'), selectedColor: deep),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: orange, minimumSize: const Size.fromHeight(48)),
                    onPressed: busy ? null : fund,
                    child: const Text('Fund'),
                  ),
                  const SizedBox(height: 32),
                  const Text('Move to plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedPlan,
                    decoration: const InputDecoration(labelText: 'Plan'),
                    items: plans.map<DropdownMenuItem<String>>((p) {
                      final id = p['_id']?.toString() ?? p['id']?.toString() ?? '';
                      final title = p['title']?.toString() ?? p['type']?.toString() ?? 'Plan';
                      return DropdownMenuItem(value: id, child: Text(title));
                    }).toList(),
                    onChanged: (v) => setState(() => selectedPlan = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: transferCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (NGN)', prefixText: '₦ '),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: orange),
                    onPressed: busy ? null : moveToPlan,
                    child: const Text('Move to plan'),
                  ),
                ],
              ),
            ),
    );
  }
}
