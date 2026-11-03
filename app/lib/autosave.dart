import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'coach.dart' show naira;
import 'main.dart';
import 'payment_watch.dart';

const _days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
String hourLabel(int h) => '${h % 12 == 0 ? 12 : h % 12}:00 ${h < 12 ? 'AM' : 'PM'}';
String whenText(String freq, int hour, int? weekday, int? day) => freq == 'daily' ? 'every day at ${hourLabel(hour)}'
    : freq == 'weekly' ? 'every ${_days[weekday ?? 1]} at ${hourLabel(hour)}' : 'on day ${day ?? 1} of every month at ${hourLabel(hour)}';
void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

/// Add money to a plan any time, as often as you like. It goes into that plan, not the wallet.
Future<void> addMoneyDialog(BuildContext context, Map plan, {VoidCallback? onPaid}) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(context: context, builder: (x) => AlertDialog(
    title: Text('Add money to ${plan['title']}'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₦)')),
      const SizedBox(height: 8),
      const Text('Add money as often as you like. It goes straight into this plan.', style: TextStyle(fontSize: 12, color: Colors.grey))]),
    actions: [TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Pay'))]));
  if (ok != true) return;
  final amount = double.tryParse(c.text.trim());
  if (amount == null || amount <= 0) { if (context.mounted) _snack(context, 'Enter an amount above zero.'); return; }
  final messenger = ScaffoldMessenger.of(context);
  try {
    final d = await Api.call('POST', '/api/plans/${plan['_id']}/fund', {'amount': amount});
    final link = d['link'] as String?;
    if (link == null) throw ApiError('Could not start the payment. Try again.');
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    // Only watch when we know the plan's balance to compare against.
    if (plan['balance'] is num) {
      final id = (plan['_id'] ?? plan['id']).toString();
      final before = (plan['balance'] as num).toDouble();
      PaymentWatcher(
        check: () => _planGrew(id, before),
        onPaid: () {
          messenger.showSnackBar(const SnackBar(content: Text('Payment received. The money is in your plan.')));
          onPaid?.call();
        },
      ).start();
    }
    messenger.showSnackBar(const SnackBar(
        content: Text('Complete the payment in the browser. Your plan updates here when it arrives.')));
  } catch (e) { if (context.mounted) _snack(context, friendly(e)); }
}

/// True once the plan's balance is above [before]. Used to notice a top-up made in the browser.
Future<bool> _planGrew(String id, double before) async {
  final plans = List<Map>.from(await Api.call('GET', '/api/plans'));
  final match = plans.where((x) => (x['_id'] ?? x['id']).toString() == id).toList();
  if (match.isEmpty) return false;
  return ((match.first['balance'] as num?) ?? 0).toDouble() > before;
}

/// Home "Add money": choose which plan first.
Future<void> pickPlanAndAdd(BuildContext context) async {
  try {
    final plans = List<Map>.from(await Api.call('GET', '/api/plans'));
    if (!context.mounted) return;
    if (plans.isEmpty) { _snack(context, 'Open a C Plan or a Mission Plan in Savings first.'); return; }
    await showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Add money to which plan?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
      ...plans.map((p) => ListTile(leading: const Icon(Icons.savings, color: orange), title: Text(p['title']), onTap: () { Navigator.pop(c); addMoneyDialog(context, p); })),
    ])));
  } catch (e) { if (context.mounted) _snack(context, friendly(e)); }
}

// ---------------- AUTO-SAVE (per plan, charged to the member's card) ----------------
class AutoSaveSheet extends StatefulWidget {
  final Map plan; final VoidCallback done;
  const AutoSaveSheet({super.key, required this.plan, required this.done});
  @override
  State<AutoSaveSheet> createState() => _AutoState();
}

class _AutoState extends State<AutoSaveSheet> {
  Map? rule; bool loading = true, editing = false, consent = false, keepCard = true, busy = false; String? err, info;
  final amt = TextEditingController(); String freq = 'weekly'; int hour = 8, weekday = 1, day = 1;

  PaymentWatcher? _payment;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _payment?.stop(); super.dispose(); }

  /// After a card is added in the browser, wait for the server to switch auto-save on. No "Check again" needed.
  void _watchCard() {
    _payment?.stop();
    final id = widget.plan['_id'].toString();
    _payment = PaymentWatcher(
      check: () async {
        final r = (await Api.call('GET', '/api/plans/$id/autosave'))['rule'];
        return r is Map && r['status'] != 'awaiting_card';
      },
      onPaid: () {
        if (!mounted) return;
        setState(() => info = 'Auto-save is on. Your card is linked.');
        _load();
        widget.done();
      },
    )..start();
  }
  Future<void> _load() async {
    try { rule = (await Api.call('GET', '/api/plans/${widget.plan['_id']}/autosave'))['rule']; } catch (e) { err = friendly(e); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _submit() async {
    setState(() { busy = true; err = null; info = null; });
    try {
      final d = await Api.call('POST', '/api/plans/${widget.plan['_id']}/autosave', {'amount': double.tryParse(amt.text), 'freq': freq, 'hour': hour,
        if (freq == 'weekly') 'weekday': weekday, if (freq == 'monthly') 'day': day, 'consent': true, 'keepCard': keepCard && rule?['cardLast4'] != null});
      final link = d['link'] as String?;
      if (link != null) {
        await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
        info = 'Finish the card payment in the browser. This screen updates by itself when it goes through.';
        _watchCard();
      }
      editing = false; await _load(); widget.done();
    } catch (e) { err = friendly(e); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _act(Future<dynamic> Function() f) async { try { await f(); await _load(); widget.done(); } catch (e) { if (mounted) setState(() => err = friendly(e)); } }

  @override
  Widget build(BuildContext context) {
    final title = widget.plan['title'];
    final a = double.tryParse(amt.text);
    final agree = 'I allow CSave to charge my debit card ${a == null ? '₦…' : naira(a)} ${whenText(freq, hour, weekday, day)} and put it straight into my $title. The first charge happens now when I add my card. I can pause or cancel any time.';
    return Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16), child: SingleChildScrollView(child: loading ? const Center(child: CircularProgressIndicator()) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Auto-save into $title', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: orange.withOpacity(.15), borderRadius: BorderRadius.circular(12)),
          child: const Text('💳 This is charged to your debit card, not your wallet. Each payment goes straight into this plan only.', style: TextStyle(fontSize: 13))),
      const SizedBox(height: 12),
      if (rule != null && !editing) ...[
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rule!['status'] == 'active' ? '● Auto-save is ON' : rule!['status'] == 'paused' ? '⏸ Auto-save is paused' : '⏳ Waiting for your card payment',
              style: TextStyle(fontWeight: FontWeight.bold, color: rule!['status'] == 'active' ? Colors.green : orange)),
          const SizedBox(height: 6),
          Text('${naira(rule!['amount'])} ${whenText(rule!['freq'], rule!['hour'], rule!['weekday'], rule!['day'])}'),
          if (rule!['cardLast4'] != null) Text('Card: ${rule!['cardBrand'] ?? 'Card'} ending ${rule!['cardLast4']}', style: const TextStyle(color: Colors.grey)),
          if (rule!['status'] == 'active' && rule!['nextRunAt'] != null) Text('Next charge: ${DateTime.parse(rule!['nextRunAt']).toLocal().toString().substring(0, 16)}', style: const TextStyle(color: Colors.grey)),
          if ((rule!['failCount'] ?? 0) > 0) Text('${rule!['failCount']} failed try(ies). It pauses after 3.', style: const TextStyle(color: Colors.redAccent)),
        ]))),
        if (rule!['status'] == 'awaiting_card') OutlinedButton(onPressed: _load, child: const Text('Check again')),
        if (rule!['status'] != 'awaiting_card') OutlinedButton(onPressed: () => _act(() => Api.call('POST', '/api/plans/${widget.plan['_id']}/autosave/active', {'active': rule!['status'] != 'active'})), child: Text(rule!['status'] == 'active' ? 'Pause' : 'Turn back on')),
        OutlinedButton(onPressed: () => setState(() { editing = true; amt.text = '${rule!['amount']}'; freq = rule!['freq']; hour = rule!['hour']; weekday = rule!['weekday'] ?? 1; day = rule!['day'] ?? 1; consent = false; }), child: const Text('Change amount or time')),
        TextButton(onPressed: () => _act(() => Api.call('DELETE', '/api/plans/${widget.plan['_id']}/autosave')), child: const Text('Cancel auto-save and remove my card', style: TextStyle(color: Colors.redAccent))),
      ] else ...[
        TextField(controller: amt, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Amount each time (₦100 to ₦1,000,000)')),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: ['daily', 'weekly', 'monthly'].map((f) => ChoiceChip(label: Text(f[0].toUpperCase() + f.substring(1)), selected: freq == f, onSelected: (_) => setState(() => freq = f))).toList()),
        const SizedBox(height: 8),
        Row(children: [
          if (freq == 'weekly') Expanded(child: DropdownButtonFormField<int>(value: weekday, decoration: const InputDecoration(labelText: 'Day'), items: List.generate(7, (i) => DropdownMenuItem(value: i, child: Text(_days[i]))), onChanged: (v) => setState(() => weekday = v!))),
          if (freq == 'monthly') Expanded(child: DropdownButtonFormField<int>(value: day, decoration: const InputDecoration(labelText: 'Day of month'), items: List.generate(28, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))), onChanged: (v) => setState(() => day = v!))),
          if (freq != 'daily') const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<int>(value: hour, decoration: const InputDecoration(labelText: 'Time'), items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text(hourLabel(i)))), onChanged: (v) => setState(() => hour = v!))),
        ]),
        if (rule?['cardLast4'] != null) CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, value: keepCard, onChanged: (v) => setState(() => keepCard = v!), title: Text('Use the same card (ending ${rule!['cardLast4']})')),
        CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, value: consent, onChanged: (v) => setState(() => consent = v!), title: Text(agree, style: const TextStyle(fontSize: 13))),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), onPressed: !consent || busy ? null : _submit,
            child: Text(rule != null && keepCard && rule!['cardLast4'] != null ? 'Save new schedule' : 'Agree and add my card')),
        if (rule != null) TextButton(onPressed: () => setState(() => editing = false), child: const Text('Back')),
      ],
      if (info != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(info!, style: const TextStyle(color: Colors.green))),
      if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
    ])));
  }
}
