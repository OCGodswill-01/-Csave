import 'package:flutter/material.dart';
import 'api.dart';
import 'coach.dart';
import 'main.dart';
import 'notify.dart';

/// Category colours come from the server as text. A bad one falls back to grey instead of crashing the screen.
Color _hex(String? h) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch((h ?? '').trim());
  return Color(int.parse('FF${m?.group(1) ?? '8a8580'}', radix: 16));
}
void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

/// Savings commitment: a percent must be 0 to 90 (the server's limit), a fixed amount zero or more.
Future<void> sendSavings(BuildContext context, Future<void> Function(Map) save, String raw, bool percent) async {
  final v = double.tryParse(raw.trim());
  final ok = v != null && v >= 0 && (!percent || v <= 90);
  if (!ok) { _snack(context, percent ? 'Enter a percent from 0 to 90.' : 'Enter an amount of zero or more.'); return; }
  await save({'savingsValue': v});
}

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});
  @override
  State<BudgetPage> createState() => _BudgetState();
}

class _BudgetState extends State<BudgetPage> with SingleTickerProviderStateMixin {
  late final tc = TabController(length: 10, vsync: this);
  Map? b; bool loading = true; String? err;
  static const names = ['Overview', 'Income', 'Categories', 'Expenses', 'Goals', 'Calendar', 'Tasks', 'Rules', 'History', 'Settings'];

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { b = (await Api.call('GET', '/api/budget'))['budget']; } catch (e) { err = friendly(e); }
    if (mounted) setState(() => loading = false);
  }
  Future<void> save(Map body) async {
    try { final r = await Api.call('POST', '/api/budget', body); if (mounted) setState(() => b = r['budget']); }
    catch (e) { if (mounted) _snack(context, friendly(e)); }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final header = Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B0B0B), Color(0xFF6B3A0C)])),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.calculate, color: Color(0xFFFFC21A)), SizedBox(width: 10), Text('Smart Budget', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white))]),
          SizedBox(height: 2), Text('Plan · Track · Achieve', style: TextStyle(color: Color(0xFF9BE8C0))),
        ]));
    if (b == null) return Column(children: [header, Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(err ?? 'Set up your budget in one tap. We add the usual categories for you.', textAlign: TextAlign.center), const SizedBox(height: 14),
      err != null
          ? FilledButton(onPressed: () { setState(() { loading = true; err = null; }); load(); }, child: const Text('Try again'))
          : FilledButton(onPressed: () => save({}), child: const Text('Start my budget'))]))))]);
    return Column(children: [
      header,
      TabBar(controller: tc, isScrollable: true, indicatorColor: orange, labelColor: orange, tabs: names.map((n) => Tab(text: n)).toList()),
      Expanded(child: TabBarView(controller: tc, children: [
        _Overview(b!, load), _Income(b!, save), _Cats(b!, save, load), _Expenses(b!, load), const _Goals(), _Calendar(b!), const _Tasks(), _Rules(b!), const _History(), _Settings(b!, save),
      ])),
    ]);
  }
}

// ---------- Overview ----------
class _Overview extends StatelessWidget {
  final Map b; final Future<void> Function() reload;
  const _Overview(this.b, this.reload);
  @override
  Widget build(BuildContext context) {
    final p = b['period']; final pct = b['totalBudget'] == 0 ? 0.0 : (b['totalSpent'] / b['totalBudget']).clamp(0, 1).toDouble();
    return ListView(padding: const EdgeInsets.all(16), children: [
      ...List<Map>.from(b['alerts']).map((a) => Card(color: const Color(0xFFFFF8DC), child: ListTile(leading: const Icon(Icons.warning_amber, color: Color(0xFFB45309)),
          title: Text(a['title'], style: const TextStyle(color: Color(0xFF7C3A00), fontWeight: FontWeight.bold)), subtitle: Text(a['text'], style: const TextStyle(color: Color(0xFF9A4A0C)))))),
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFFFF9A00), Color(0xFFC25A00)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('CURRENT PERIOD\n${p['start']} — ${p['end']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            Chip(label: Text('${p['daysLeft']} days left'))]),
          const SizedBox(height: 10),
          Row(children: [
            _tile('Total budget', naira(b['totalBudget']), b['rolloverIn'] > 0 ? '+${naira(b['rolloverIn'])} rollover' : ''),
            const SizedBox(width: 8), _tile('Spent', naira(b['totalSpent']), '${(pct * 100).toStringAsFixed(1)}%'),
            const SizedBox(width: 8), _tile('Remaining', naira(b['remaining']), '')]),
          const SizedBox(height: 12), LinearProgressIndicator(value: pct, minHeight: 8, color: Colors.white, backgroundColor: Colors.white24),
        ])),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: () => addExpenseDialog(context, b, reload), icon: const Icon(Icons.add), label: const Text('Add spending')),
      const SizedBox(height: 8),
      ...List<Map>.from(b['categories']).where((c) => c['limit'] > 0).map((c) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [CircleAvatar(radius: 6, backgroundColor: _hex(c['color'])), const SizedBox(width: 8), Expanded(child: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold))), Text('${naira(c['spent'])} / ${naira(c['limit'])}')]),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: (c['spent'] / c['limit']).clamp(0, 1).toDouble(), minHeight: 6, color: c['status'] == 'over' ? Colors.redAccent : c['status'] == 'near' ? Colors.amber : Colors.green)])))),
    ]);
  }
  Widget _tile(String t, String v, String s) => Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(color: Colors.white70, fontSize: 12)), Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), Text(s, style: const TextStyle(color: Colors.white70, fontSize: 11))])));
}

Future<void> addExpenseDialog(BuildContext context, Map b, Future<void> Function() reload) async {
  final cats = List<Map>.from(b['categories']); String? cat; final amt = TextEditingController(), note = TextEditingController();
  final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
    title: const Text('Add spending'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButton<String?>(isExpanded: true, value: cat, hint: const Text('Category (or let my rules decide)'),
          items: [const DropdownMenuItem(value: null, child: Text('Auto (use my rules)')), ...cats.map((x) => DropdownMenuItem(value: x['name'] as String, child: Text(x['name'])))], onChanged: (v) => set(() => cat = v)),
      TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₦)')),
      TextField(controller: note, decoration: const InputDecoration(labelText: 'What was it for?')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add'))])));
  if (ok != true) return;
  final spent = double.tryParse(amt.text.trim());
  if (spent == null || spent <= 0) { if (context.mounted) _snack(context, 'Enter an amount above zero.'); return; }
  try {
    final d = await Api.call('POST', '/api/budget/expense', {'category': cat, 'amount': spent, 'note': note.text});
    await reload(); if (!context.mounted) return; final s = d['status'];
    _snack(context, s == 'over' ? 'You went over ${d['category']}. It happens. Plan the rest of the period around it.' : s == 'near' ? 'You are close to the ${d['category']} limit.' : 'Added to ${d['category']}. You are within budget. Well done.');
  } catch (e) { if (context.mounted) _snack(context, friendly(e)); }
}

// ---------- Income ----------
class _Income extends StatelessWidget {
  final Map b; final Future<void> Function(Map) save;
  const _Income(this.b, this.save);
  Future<void> _add(BuildContext context) async {
    final n = TextEditingController(), a = TextEditingController(); String f = 'monthly';
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(title: const Text('Add income source'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: n, decoration: const InputDecoration(labelText: 'Name (e.g. Salary)')),
      TextField(controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₦)')),
      DropdownButton<String>(isExpanded: true, value: f, items: const [DropdownMenuItem(value: 'monthly', child: Text('Monthly')), DropdownMenuItem(value: 'weekly', child: Text('Weekly'))], onChanged: (v) => set(() => f = v!))]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add'))])));
    if (ok == true) {
      final amt = double.tryParse(a.text.trim());
      if (n.text.trim().isEmpty || amt == null || amt <= 0) { _snack(context, 'Enter a name and an amount above zero.'); return; }
      save({'incomes': [...List<Map>.from(b['incomes']).map((i) => {'name': i['name'], 'freq': i['freq'], 'amount': i['amount']}), {'name': n.text.trim(), 'freq': f, 'amount': amt}]});
    }
  }
  @override
  Widget build(BuildContext context) {
    final incomes = List<Map>.from(b['incomes']); final percent = b['savingsMode'] == 'percent'; final v = TextEditingController(text: '${b['savingsValue']}');
    final pct = b['income'] == 0 ? 0.0 : (b['savings'] / b['income']).clamp(0, 1).toDouble();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFF00BF80), Color(0xFF007A55)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TOTAL MONTHLY INCOME', style: TextStyle(color: Colors.white70, letterSpacing: 1.2)),
          Text(naira(b['income']), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white)), Text('${incomes.length} source${incomes.length == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10), _row('Savings first', naira(b['savings'])), const SizedBox(height: 6), _row('Available for expenses', naira(b['available'])),
          const SizedBox(height: 10), LinearProgressIndicator(value: pct, minHeight: 8, color: Colors.white, backgroundColor: Colors.white24)])),
      const SizedBox(height: 14),
      Card(child: Column(children: [
        ListTile(title: const Text('Income sources', style: TextStyle(fontWeight: FontWeight.bold)), trailing: TextButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('Add'))),
        ...incomes.map((i) => ListTile(title: Text(i['name']), subtitle: Text('${i['freq'] == 'weekly' ? 'Weekly' : 'Monthly'} · ${naira(i['amount'])}'),
            trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => save({'incomes': incomes.where((x) => x != i).map((x) => {'name': x['name'], 'freq': x['freq'], 'amount': x['amount']}).toList()})))),
        if (incomes.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Add your salary so your coach can plan with real numbers.')),
      ])),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Savings commitment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const Text('Set how much of your income you commit to saving before budgeting the rest.'), const SizedBox(height: 10),
        Wrap(spacing: 8, children: [ChoiceChip(label: const Text('% of income'), selected: percent, onSelected: (_) => save({'savingsMode': 'percent'})), ChoiceChip(label: const Text('Fixed amount'), selected: !percent, onSelected: (_) => save({'savingsMode': 'fixed'}))]),
        const SizedBox(height: 8),
        TextField(controller: v, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: percent ? 'Percentage (%)' : 'Amount (₦)'), onSubmitted: (x) => sendSavings(context, save, x, percent)),
        const SizedBox(height: 8), FilledButton(onPressed: () => sendSavings(context, save, v.text, percent), child: const Text('Save')),
      ]))),
    ]);
  }
  Widget _row(String a, String b) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [Expanded(child: Text(a, style: const TextStyle(color: Colors.white))), Text(b, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]));
}

// ---------- Categories ----------
class _Cats extends StatelessWidget {
  final Map b; final Future<void> Function(Map) save; final Future<void> Function() reload;
  const _Cats(this.b, this.save, this.reload);
  List<Map> _list() => List<Map>.from(b['categories']).map((c) => {'name': c['name'], 'limit': c['limit'], 'color': c['color']}).toList();
  @override
  Widget build(BuildContext context) {
    final cats = List<Map>.from(b['categories']); final over = b['overAllocated'] > 0;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: over ? const Color(0xFFFFEFEF) : const Color(0xFFEAF8F1), borderRadius: BorderRadius.circular(20), border: Border.all(color: over ? Colors.red.shade200 : Colors.green.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Allocated of available for expenses', style: TextStyle(color: Colors.black54)),
          Text('${naira(b['allocated'])} / ${naira(b['available'])}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
          if (over) Text('Exceeds by ${naira(b['overAllocated'])}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)) else const Text('Within your available money', style: TextStyle(color: Colors.green)),
        ])),
      const SizedBox(height: 12),
      Card(child: Column(children: [
        ListTile(title: Text('Categories (${cats.length})', style: const TextStyle(fontWeight: FontWeight.bold)), trailing: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Add'), onPressed: () async {
          final n = TextEditingController(); final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('New category'), content: TextField(controller: n, decoration: const InputDecoration(labelText: 'Name')),
              actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add'))]));
          if (ok == true && n.text.trim().isNotEmpty) save({'categories': [..._list(), {'name': n.text.trim(), 'limit': 0, 'color': '#d4730a'}]});
        })),
        ...cats.map((c) { final ctl = TextEditingController(text: c['limit'] == 0 ? '' : '${c['limit']}');
          return ListTile(leading: CircleAvatar(radius: 7, backgroundColor: _hex(c['color'])), title: Text(c['name']), subtitle: Text('${c['count']} expenses · ${naira(c['spent'])} spent'),
            trailing: SizedBox(width: 130, child: Row(children: [
              Expanded(child: TextField(controller: ctl, keyboardType: TextInputType.number, textAlign: TextAlign.end, decoration: const InputDecoration(hintText: 'Limit'),
                  onSubmitted: (v) => save({'categories': _list().map((x) => x['name'] == c['name'] ? {...x, 'limit': double.tryParse(v) ?? 0} : x).toList()}))),
              IconButton(tooltip: 'Reset ${c['name']}', icon: const Icon(Icons.restart_alt), onPressed: () async { await Api.call('POST', '/api/budget/reset', {'name': c['name']}); await reload(); }),
            ])));
        }),
        const Padding(padding: EdgeInsets.all(12), child: Text('Type a limit and press Enter on your keyboard to save it.', style: TextStyle(color: Colors.grey, fontSize: 12))),
      ])),
    ]);
  }
}

// ---------- Expenses ----------
class _Expenses extends StatefulWidget {
  final Map b; final Future<void> Function() reload;
  const _Expenses(this.b, this.reload);
  @override
  State<_Expenses> createState() => _ExpState();
}

class _ExpState extends State<_Expenses> {
  String f = 'all'; List<Map>? items;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final r = await Api.call('GET', '/api/budget/expenses${f == 'all' ? '' : '?source=$f'}'); if (mounted) setState(() => items = List<Map>.from(r)); }
  @override
  Widget build(BuildContext context) {
    final cats = List<Map>.from(widget.b['categories']).map((c) => c['name'] as String).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, children: ['all', 'manual', 'auto'].map((x) => ChoiceChip(label: Text(x[0].toUpperCase() + x.substring(1)), selected: f == x, onSelected: (_) { f = x; _load(); })).toList()),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: () async { await addExpenseDialog(context, widget.b, widget.reload); _load(); }, icon: const Icon(Icons.add), label: const Text('Add spending')),
      if (items == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      if (items != null && items!.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No spending logged in this period yet.')),
      ...?items?.map((e) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(e['note'].toString().isEmpty ? e['category'] : e['note'], style: const TextStyle(fontWeight: FontWeight.bold))), Text(naira(e['amount']), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () async { await Api.call('DELETE', '/api/budget/expenses/${e['_id']}'); await widget.reload(); _load(); })]),
        Row(children: [Text(e['date'], style: const TextStyle(color: Colors.grey)), const SizedBox(width: 8), Chip(label: Text(e['source'].toString().toUpperCase(), style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact), const Spacer(),
          DropdownButton<String>(value: cats.contains(e['category']) ? e['category'] : null, items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) async { await Api.call('POST', '/api/budget/expenses/${e['_id']}', {'category': v}); await widget.reload(); _load(); })]),
      ])))),
    ]);
  }
}

// ---------- Goals ----------
class _Goals extends StatefulWidget {
  const _Goals();
  @override
  State<_Goals> createState() => _GoalsState();
}

class _GoalsState extends State<_Goals> {
  List<Map>? goals;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final r = await Api.call('GET', '/api/goals'); if (mounted) setState(() => goals = List<Map>.from(r)); }
  Future<void> _new() async {
    final n = TextEditingController(), t = TextEditingController(); DateTime? d;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(title: const Text('New goal'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: n, decoration: const InputDecoration(labelText: 'Goal (e.g. New laptop)')),
      TextField(controller: t, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Target (₦)')),
      TextButton(onPressed: () async { final p = await showDatePicker(context: c, firstDate: DateTime.now().add(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: DateTime.now().add(const Duration(days: 180))); if (p != null) set(() => d = p); }, child: Text(d == null ? 'Pick deadline' : d.toString().split(' ').first))]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create'))])));
    if (ok != true) return;
    final target = double.tryParse(t.text.trim());
    if (n.text.trim().isEmpty || target == null || target <= 0) { if (mounted) _snack(context, 'Enter a goal name and a target above zero.'); return; }
    try { await Api.call('POST', '/api/goals', {'name': n.text.trim(), 'target': target, 'deadline': d?.toIso8601String()}); _load(); } catch (e) { if (mounted) _snack(context, friendly(e)); }
  }
  Future<void> _addMoney(Map g) async {
    final a = TextEditingController(); final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text('Add to ${g['name']}'), content: TextField(controller: a, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₦)')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add'))]));
    if (ok == true) {
      final amount = double.tryParse(a.text.trim());
      if (amount == null || amount <= 0) { if (mounted) _snack(context, 'Enter an amount above zero.'); return; }
      try { await Api.call('POST', '/api/goals/${g['_id']}/add', {'amount': amount}); _load(); } catch (e) { if (mounted) _snack(context, friendly(e)); }
    }
  }
  @override
  Widget build(BuildContext context) {
    if (goals == null) return const Center(child: CircularProgressIndicator());
    final active = goals!.where((g) => g['done'] != true).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [Expanded(child: Text('$active active goal(s)')), FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('New goal'))]),
      const SizedBox(height: 8),
      ...goals!.map((g) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(g['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, decoration: g['done'] == true ? TextDecoration.lineThrough : null))),
          if (g['done'] != true) IconButton(icon: const Icon(Icons.check_circle_outline, color: Colors.green), onPressed: () async { await Api.call('POST', '/api/goals/${g['_id']}/done'); _load(); }),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () async { await Api.call('DELETE', '/api/goals/${g['_id']}'); _load(); })]),
        Text('Deadline: ${g['deadline'].toString().split('T').first}', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 6), Row(children: [Text(naira(g['saved'])), const Spacer(), Text('${g['pct']}% of ${naira(g['target'])}')]),
        LinearProgressIndicator(value: g['pct'] / 100, minHeight: 7, color: Colors.green),
        if (g['done'] != true) ...[const SizedBox(height: 6), Text('Save ${naira(g['monthly'])}/month to reach this goal', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)), TextButton(onPressed: () => _addMoney(g), child: const Text('Add money to goal'))],
      ])))),
    ]);
  }
}

// ---------- Calendar (alarms) ----------
class _Calendar extends StatefulWidget {
  final Map b;
  const _Calendar(this.b);
  @override
  State<_Calendar> createState() => _CalState();
}

class _CalState extends State<_Calendar> {
  List<Map>? rem, goals;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.call('GET', '/api/reminders'), Api.call('GET', '/api/goals')]);
      rem = List<Map>.from(r[0]); goals = List<Map>.from(r[1]).where((g) => g['done'] != true).toList();
      await Alarms.sync(rem!); if (mounted) setState(() {});
    } catch (e) { if (mounted) _snack(context, friendly(e)); }
  }
  Future<void> _add() async {
    final title = TextEditingController(), day = TextEditingController(text: '25'); String kind = 'salary'; TimeOfDay t = const TimeOfDay(hour: 8, minute: 0);
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(title: const Text('New alarm'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButton<String>(isExpanded: true, value: kind, items: const {'salary': 'Salary day', 'budget': 'Budget day', 'saving': 'Saving day', 'goal': 'Goal deadline', 'custom': 'Something else'}.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) => set(() => kind = v!)),
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
      TextField(controller: day, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Day of the month (1 to 28)')),
      TextButton(onPressed: () async { final p = await showTimePicker(context: c, initialTime: t); if (p != null) set(() => t = p); }, child: Text('Time: ${t.format(c)}'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Set alarm'))])));
    if (ok != true) return;
    final dd = int.tryParse(day.text.trim());
    if (title.text.trim().isEmpty || dd == null || dd < 1 || dd > 28) { if (mounted) _snack(context, 'Give the alarm a name and a day from 1 to 28.'); return; }
    try {
      final hh = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final r = await Api.call('POST', '/api/reminders', {'title': title.text.trim(), 'kind': kind, 'day': dd, 'time': hh});
      rem!.add(r); await Alarms.sync(rem!); setState(() {}); if (mounted) _snack(context, 'Alarm set. Your phone will ring on day ${r['day']} at ${r['time']}.');
    } catch (e) { if (mounted) _snack(context, friendly(e)); }
  }
  @override
  Widget build(BuildContext context) {
    if (rem == null) return const Center(child: CircularProgressIndicator());
    final events = <Map>[{'day': widget.b['payDay'], 'title': 'Pay day (budget period starts)', 'icon': Icons.payments, 'time': ''},
      ...rem!.map((r) => {'day': r['day'], 'title': r['title'], 'icon': Icons.alarm, 'time': r['time'], 'id': r['_id']})]..sort((a, b) => (a['day'] as int).compareTo(b['day'] as int));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [const Expanded(child: Text('Calendar and alarms', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), FilledButton.icon(onPressed: _add, icon: const Icon(Icons.alarm_add), label: const Text('Add'))]),
      const SizedBox(height: 8),
      ...events.map((e) => Card(child: ListTile(leading: Icon(e['icon'], color: orange), title: Text(e['title']), subtitle: Text('Every month on day ${e['day']}${e['time'] == '' ? '' : ' at ${e['time']}'}'),
          trailing: e['id'] == null ? null : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await Api.call('DELETE', '/api/reminders/${e['id']}'); await Alarms.cancel(e['id']); setState(() => rem!.removeWhere((r) => r['_id'] == e['id'])); })))),
      ...goals!.map((g) => Card(child: ListTile(leading: const Icon(Icons.flag, color: Colors.green), title: Text('Goal deadline: ${g['name']}'), subtitle: Text(g['deadline'].toString().split('T').first)))),
      const Padding(padding: EdgeInsets.only(top: 8), child: Text('Alarms use your phone. Days run 1 to 28 so every month has them. In battery saver an alarm can arrive a few minutes late.', style: TextStyle(color: Colors.grey, fontSize: 12))),
    ]);
  }
}

class Alarms {
  static Future<bool> get nudges async => (await store.read(key: 'alarms')) != '0';
  static Future<void> sync(List rem) async {
    await Notify.askPermission();
    if (await nudges) {
      await Notify.daily(9001, 'Good morning', 'Check your budget and plan today.', 8, 0);
      await Notify.daily(9002, 'Good evening', 'How far did you go today? Check your budget and plan tomorrow.', 20, 30);
      await Notify.weeklySunday(9003, 'Weekly reflection', 'Take two minutes to reflect. Be honest with yourself.', 19, 0);
    } else { for (final i in [9001, 9002, 9003]) { await Notify.cancelId(i); } }
    for (final r in rem) { await Notify.monthly(r['_id'], r['title'], 'Reminder: ${r['title']}', r['day'], r['time']); }
  }
  static Future<void> cancel(String id) => Notify.cancelServer(id);
}

// ---------- Tasks ----------
class _Tasks extends StatefulWidget {
  const _Tasks();
  @override
  State<_Tasks> createState() => _TasksState();
}

class _TasksState extends State<_Tasks> {
  List<Map>? t; final c = TextEditingController();
  @override
  void initState() { super.initState(); Api.call('GET', '/api/tasks').then((r) { if (mounted) setState(() => t = List<Map>.from(r)); }); }
  void _set(dynamic r) => setState(() => t = List<Map>.from(r));
  @override
  Widget build(BuildContext context) {
    if (t == null) return const Center(child: CircularProgressIndicator());
    final done = t!.where((x) => x['done'] == true).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Weekly Checklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), Text('Resets every Monday', style: TextStyle(color: Colors.grey))])),
          Text('$done', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: orange)), Text('/${t!.length}')]),
        LinearProgressIndicator(value: t!.isEmpty ? 0 : done / t!.length, minHeight: 7, color: orange)]))),
      Card(child: Column(children: [
        ListTile(title: const Text('Tasks', style: TextStyle(fontWeight: FontWeight.bold)), trailing: TextButton.icon(onPressed: () async => _set(await Api.call('POST', '/api/tasks/reset')), icon: const Icon(Icons.refresh), label: const Text('Reset'))),
        ...t!.map((x) => CheckboxListTile(value: x['done'] == true, onChanged: (_) async => _set(await Api.call('POST', '/api/tasks/${x['_id']}/toggle')), controlAffinity: ListTileControlAffinity.leading,
            title: Text('${x['emoji']}  ${x['text']}'), secondary: x['custom'] == true ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () async => _set(await Api.call('DELETE', '/api/tasks/${x['_id']}'))) : null)),
      ])),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Expanded(child: TextField(controller: c, decoration: const InputDecoration(hintText: 'e.g. Pay electricity bill'))),
        IconButton(icon: const Icon(Icons.add_circle, color: orange, size: 32), onPressed: () async { final x = c.text; c.clear(); try { _set(await Api.call('POST', '/api/tasks', {'text': x})); } catch (e) { if (mounted) _snack(context, friendly(e)); } })]))),
    ]);
  }
}

// ---------- Rules ----------
class _Rules extends StatefulWidget {
  final Map b;
  const _Rules(this.b);
  @override
  State<_Rules> createState() => _RulesState();
}

class _RulesState extends State<_Rules> {
  List<Map>? rules;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final r = await Api.call('GET', '/api/budget/rules'); if (mounted) setState(() => rules = List<Map>.from(r)); }
  Future<void> _add() async {
    final k = TextEditingController(); String? cat; final cats = List<Map>.from(widget.b['categories']).map((c) => c['name'] as String).toList();
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(title: const Text('New rule'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: k, decoration: const InputDecoration(labelText: 'If the note contains... (e.g. uber)')),
      DropdownButton<String>(isExpanded: true, value: cat, hint: const Text('put it in category'), items: cats.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => set(() => cat = v))]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add rule'))])));
    if (ok == true) { try { await Api.call('POST', '/api/budget/rules', {'keyword': k.text, 'category': cat}); _load(); } catch (e) { if (mounted) _snack(context, friendly(e)); } }
  }
  @override
  Widget build(BuildContext context) => rules == null ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [const Expanded(child: Text('Auto-categorise rules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add'))]),
        const Text('When you log spending with Auto and a note that has your keyword, it goes to the right category.', style: TextStyle(color: Colors.grey)),
        ...rules!.map((r) => Card(child: ListTile(leading: const Icon(Icons.sell, color: orange), title: Text('"${r['keyword']}"  →  ${r['category']}'), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await Api.call('DELETE', '/api/budget/rules/${r['_id']}'); _load(); })))),
      ]);
}

// ---------- History ----------
class _History extends StatelessWidget {
  const _History();
  @override
  Widget build(BuildContext context) => FutureBuilder(future: Api.call('GET', '/api/budget/history'), builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(padding: const EdgeInsets.all(16), children: List<Map>.from(s.data).map((p) {
          final pct = p['effective'] == 0 ? 0.0 : (p['spent'] / p['effective']).clamp(0, 1).toDouble();
          return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p['current'] ? const Color(0xFFFFD54F) : Colors.transparent)), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['start']} — ${p['end']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), if (p['current']) const Chip(label: Text('CURRENT'), visualDensity: VisualDensity.compact),
            const SizedBox(height: 6), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_k('Effective', naira(p['effective'])), _k('Spent', naira(p['spent'])), _k('Rollover in', naira(p['rolloverIn']))]),
            const SizedBox(height: 8), LinearProgressIndicator(value: pct, minHeight: 7, color: Colors.green)])));
        }).toList());
      });
  static Widget _k(String a, String b) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(b, style: const TextStyle(fontWeight: FontWeight.bold))]);
}

// ---------- Settings ----------
class _Settings extends StatefulWidget {
  final Map b; final Future<void> Function(Map) save;
  const _Settings(this.b, this.save);
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  bool nudges = true;
  @override
  void initState() { super.initState(); Alarms.nudges.then((v) { if (mounted) setState(() => nudges = v); }); }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(title: const Text('Pay day'), subtitle: const Text('Your budget period starts on this day each month'),
            trailing: DropdownButton<int>(value: widget.b['payDay'], items: List.generate(28, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))), onChanged: (v) => widget.save({'payDay': v})))),
        Card(child: SwitchListTile(title: const Text('Roll over unspent money'), subtitle: const Text('Money you did not spend moves into the next period'), value: widget.b['rollover'], onChanged: (v) => widget.save({'rollover': v}))),
        Card(child: SwitchListTile(title: const Text('Daily and weekly nudges'), subtitle: const Text('Morning 8:00 plan, night 8:30 check, Sunday 7:00 pm reflection'), value: nudges,
            onChanged: (v) async { await store.write(key: 'alarms', value: v ? '1' : '0'); if (mounted) setState(() => nudges = v); await Alarms.sync(List.from(await Api.call('GET', '/api/reminders'))); })),
      ]);
}
