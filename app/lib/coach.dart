import 'package:flutter/material.dart';
import 'api.dart';
import 'main.dart';

String naira(num n) => '₦${n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';

// ---------------- WEEKLY REFLECTION POP-UP ----------------
Future<void> checkReflection(BuildContext context) async {
  try {
    final r = await Api.call('GET', '/api/reflection/current');
    if (r['due'] != true || !context.mounted) return;
    await showDialog(context: context, builder: (_) => _ReflectionDialog(question: r['question']));
  } catch (_) {}
}

class _ReflectionDialog extends StatefulWidget {
  final String question;
  const _ReflectionDialog({required this.question});
  @override
  State<_ReflectionDialog> createState() => _RefState();
}

class _RefState extends State<_ReflectionDialog> {
  final c = TextEditingController(); String? reply, err; bool busy = false;
  Future<void> send() async {
    setState(() { busy = true; err = null; });
    try { final d = await Api.call('POST', '/api/reflection', {'answer': c.text}); setState(() => reply = d['reply']); }
    catch (e) { setState(() => err = friendly(e)); }
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Weekly reflection'),
        content: SingleChildScrollView(child: reply != null ? Text(reply!) : Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.question), const SizedBox(height: 10),
          TextField(controller: c, maxLines: 4, maxLength: 600, decoration: const InputDecoration(hintText: 'Write the truth. Nobody is judging.')),
          if (err != null) Text(err!, style: const TextStyle(color: Colors.redAccent)),
        ])),
        actions: reply != null
            ? [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))]
            : [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')), FilledButton(onPressed: busy ? null : send, child: const Text('Submit'))],
      );
}

// ---------------- INSIGHTS = AI MONEY COACH (type to chat) ----------------
// A different assistant from the customer-service Help button: it knows your budget, goals and score.
class CoachPage extends StatefulWidget {
  const CoachPage({super.key});
  @override
  State<CoachPage> createState() => _CoachState();
}

class _CoachState extends State<CoachPage> {
  final input = TextEditingController(), scroll = ScrollController();
  List<Map> msgs = []; Map? score; bool busy = false, showScore = false; String? err;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.call('GET', '/api/coach/history'), Api.call('GET', '/api/coach/score')]);
      msgs = List<Map>.from(r[0]); score = r[1];
    } catch (_) {}
    if (mounted) setState(() {}); _down();
  }

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); });

  Future<void> send(String text, {String? kind}) async {
    text = text.trim(); if (text.isEmpty || busy) return;
    if (!await ensureAiConsent(context)) { if (mounted) setState(() => err = 'The coach needs your agreement to use AI. Tap send again to read it.'); return; }
    setState(() { msgs.add({'role': 'member', 'text': text}); busy = true; err = null; input.clear(); }); _down();
    try {
      final d = await Api.call('POST', '/api/coach/chat', {'message': text, 'kind': kind});
      setState(() => msgs.add({'role': 'coach', 'text': d['reply']}));
      score = await Api.call('GET', '/api/coach/score');
    } catch (e) { setState(() => err = friendly(e)); }
    if (mounted) setState(() => busy = false); _down();
  }

  @override
  Widget build(BuildContext context) {
    final card = Theme.of(context).cardColor;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 0), child: Row(children: [
        const CircleAvatar(backgroundColor: orange, child: Icon(Icons.psychology, color: Colors.white)),
        const SizedBox(width: 10),
        const Expanded(child: Text('Your money coach', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        if (score != null) TextButton(onPressed: () => setState(() => showScore = !showScore), child: Text('Score ${score!['total']}')),
        IconButton(tooltip: 'Clear chat', icon: const Icon(Icons.delete_outline), onPressed: () async { try { await Api.call('DELETE', '/api/coach/history'); setState(() => msgs = []); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e)))); } }),
      ])),
      if (showScore && score != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${score!['total']} / 100 · ${score!['label']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ...Map<String, dynamic>.from(score!['parts']).entries.map((e) => Padding(padding: const EdgeInsets.only(top: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${e.key}  ${e.value[0]}/${e.value[1]}', style: const TextStyle(fontSize: 12)),
          LinearProgressIndicator(value: e.value[1] == 0 ? 0.0 : (e.value[0] / e.value[1]).clamp(0, 1).toDouble(), color: orange, minHeight: 5)]))),
      ])))),
      Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
        if (msgs.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(16), child: const Text('Hi, I am your money coach. Tell me your salary, ask how to budget, or ask how you are doing this month. I look at your budget and goals when I answer.'))),
        ...msgs.map((m) { final me = m['role'] == 'member'; return Align(alignment: me ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), constraints: const BoxConstraints(maxWidth: 300),
                decoration: BoxDecoration(color: me ? orange : card, borderRadius: BorderRadius.circular(16)),
                child: Text(m['text'], style: TextStyle(color: me ? Colors.white : null, height: 1.4)))); }),
        if (busy) const Padding(padding: EdgeInsets.all(8), child: Text('Coach is thinking...', style: TextStyle(color: Colors.grey))),
        if (err != null) Text(err!, style: const TextStyle(color: Colors.redAccent)),
      ])),
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        for (final c in [['Morning plan', 'Give me my plan for this morning.', 'morning'], ['Night check', 'Help me check my budget tonight and plan tomorrow.', 'night'],
          ['Analyse my account', 'Analyse my account: look at my budget, spending history and savings and tell me how I am doing.', null], ['Explain my score', 'Explain my score this month.', null], ['I just got paid', 'I just got paid. Help me plan this salary.', null]])
          Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(c[0]!), onPressed: busy ? null : () => send(c[1]!, kind: c[2]))),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: Row(children: [
        Expanded(child: TextField(controller: input, maxLength: 500, minLines: 1, maxLines: 3, onSubmitted: send,
            decoration: const InputDecoration(hintText: 'Type to your coach', counterText: ''))),
        IconButton(onPressed: busy ? null : () => send(input.text), icon: const Icon(Icons.send, color: orange)),
      ])),
      const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('Education only, not licensed financial advice.', style: TextStyle(color: Colors.grey, fontSize: 11))),
    ]);
  }
}
