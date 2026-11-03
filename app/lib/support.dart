import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'main.dart';

// ---------------- MEMBER: HELP CHAT (AI first, then a real person) ----------------
class SupportChat extends StatefulWidget {
  const SupportChat({super.key});
  @override
  State<SupportChat> createState() => _SupportChatState();
}

class _SupportChatState extends State<SupportChat> {
  final input = TextEditingController(); List<Map> msgs = []; String status = 'open'; bool busy = false; String? err; Timer? poll;

  @override
  void initState() { super.initState(); _load(); poll = Timer.periodic(const Duration(seconds: 8), (_) => _load()); }
  @override
  void dispose() { poll?.cancel(); super.dispose(); }

  void _apply(Map d) { msgs = List<Map>.from(d['messages']); status = d['status']; }
  Future<void> _load() async { try { final d = await Api.call('GET', '/api/support/chat'); if (mounted) setState(() => _apply(d)); } catch (_) {} }
  Future<void> _send({bool human = false}) async {
    final t = input.text.trim(); if ((t.isEmpty && !human) || busy) return;
    if (!human && !await ensureAiConsent(context)) { setState(() => err = 'To chat with the AI helper we need your agreement. Or tap "Talk to a person".'); return; }
    setState(() { busy = true; err = null; if (t.isNotEmpty) msgs.add({'role': 'member', 'text': t, 'review': 'none'}); input.clear(); });
    try { final d = await Api.call('POST', '/api/support/chat', {'message': t, 'human': human}); setState(() => _apply(d)); } catch (e) { setState(() => err = friendly(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final card = Theme.of(context).cardColor;
    return Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16), child: SizedBox(height: 470, child: Column(children: [
      Row(children: [const Icon(Icons.support_agent, color: orange), const SizedBox(width: 8), const Expanded(child: Text('CSave Help', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        if (status != 'escalated') TextButton(onPressed: busy ? null : () => _send(human: true), child: const Text('Talk to a person'))]),
      if (status == 'escalated') Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: orange.withOpacity(.15), borderRadius: BorderRadius.circular(10)),
          child: const Text('A person from customer service is handling this. Replies show here and in your notifications.', style: TextStyle(fontSize: 12))),
      Expanded(child: ListView(reverse: false, children: [
        if (msgs.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Hi, I am CSave Help. Ask me about your account, plans, withdrawals, KYC or membership.')),
        ...msgs.map((m) { final me = m['role'] == 'member', staff = m['role'] == 'staff';
          return Align(alignment: me ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), constraints: const BoxConstraints(maxWidth: 290),
            decoration: BoxDecoration(color: me ? orange : staff ? const Color(0xFF1F6F54) : card, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!me) Text(staff ? 'Customer service' : 'CSave Help (AI)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
              Text(m['text'], style: TextStyle(color: me || staff ? Colors.white : null, height: 1.35)),
              if (m['review'] == 'pending') const Padding(padding: EdgeInsets.only(top: 6), child: Text('⏳ Customer service will confirm this answer', style: TextStyle(fontSize: 11, color: Colors.amber))),
              if (m['review'] == 'confirmed') const Padding(padding: EdgeInsets.only(top: 6), child: Text('✔ Confirmed by customer service', style: TextStyle(fontSize: 11, color: Colors.greenAccent))),
              if (m['review'] == 'corrected') const Padding(padding: EdgeInsets.only(top: 6), child: Text('✎ Customer service corrected this below', style: TextStyle(fontSize: 11, color: Colors.amber))),
            ])));
        }),
        if (busy) const Text('Typing...', style: TextStyle(color: Colors.grey)),
        if (err != null) Text(err!, style: const TextStyle(color: Colors.redAccent)),
      ])),
      Row(children: [Expanded(child: TextField(controller: input, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Type your question'))), IconButton(onPressed: busy ? null : _send, icon: const Icon(Icons.send, color: orange))]),
    ])));
  }
}

// ---------------- STAFF: CUSTOMER SERVICE DASHBOARD (admin + support roles) ----------------
class SupportDashboard extends StatefulWidget {
  const SupportDashboard({super.key});
  @override
  State<SupportDashboard> createState() => _SDState();
}

class _SDState extends State<SupportDashboard> {
  late Future f = Api.call('GET', '/api/support/tickets');
  void refresh() => setState(() => f = Api.call('GET', '/api/support/tickets'));
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Customer service'), actions: [
          IconButton(tooltip: 'Approved answers', icon: const Icon(Icons.menu_book), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FaqScreen()))),
          IconButton(icon: const Icon(Icons.refresh), onPressed: refresh)]),
        body: FutureBuilder(future: f, builder: (c, s) {
          if (s.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendly(s.error!), textAlign: TextAlign.center)));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final l = List<Map>.from(s.data);
          if (l.isEmpty) return const Center(child: Text('No open tickets. Nice.'));
          return ListView(children: l.map((t) => ListTile(
              leading: Icon(t['status'] == 'escalated' ? Icons.priority_high : Icons.chat_bubble_outline, color: t['status'] == 'escalated' ? Colors.redAccent : orange),
              title: Text('${t['member'] ?? 'Member'}${t['unread'] == true ? '  •' : ''}'), subtitle: Text(t['last'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: (t['pendingReviews'] ?? 0) > 0 ? Chip(label: Text('${t['pendingReviews']} to confirm'), visualDensity: VisualDensity.compact) : Text(t['status']),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TicketScreen(id: t['id']))).then((_) => refresh()))).toList());
        }),
      );
}

class TicketScreen extends StatefulWidget {
  final String id;
  const TicketScreen({super.key, required this.id});
  @override
  State<TicketScreen> createState() => _TicketState();
}

class _TicketState extends State<TicketScreen> {
  Map? t; final reply = TextEditingController();
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final d = await Api.call('GET', '/api/support/tickets/${widget.id}'); if (mounted) setState(() => t = d); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e)))); }
  }
  Future<void> _post(String path, [Map? body]) async { try { final d = await Api.call('POST', path, body); if (mounted) setState(() => t = {...?t, ...d}); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e)))); } }
  Future<void> _correct(Map m) async {
    final c = TextEditingController(); final ok = await showDialog<bool>(context: context, builder: (x) => AlertDialog(title: const Text('Correct this answer'), content: TextField(controller: c, maxLines: 4, decoration: const InputDecoration(hintText: 'Write the right answer')),
        actions: [TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Send correction'))]));
    if (ok == true && c.text.trim().isNotEmpty) _post('/api/support/tickets/${widget.id}/messages/${m['id']}/confirm', {'correction': c.text});
  }
  @override
  Widget build(BuildContext context) {
    if (t == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final msgs = List<Map>.from(t!['messages']);
    return Scaffold(
      appBar: AppBar(title: Text(t!['member'] ?? 'Ticket'), actions: [TextButton(onPressed: () async { await Api.call('POST', '/api/support/tickets/${widget.id}/resolve'); if (mounted) Navigator.pop(context); }, child: const Text('Resolve'))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Text('${t!['email'] ?? ''} · Member ${t!['membershipId'] ?? 'not yet'} · KYC ${t!['kycStatus'] ?? '-'}', style: const TextStyle(color: Colors.grey, fontSize: 12))),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: msgs.map((m) => Card(color: m['role'] == 'staff' ? const Color(0xFF1F6F54) : m['role'] == 'member' ? orange.withOpacity(.2) : null,
          child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m['role'] == 'ai' ? 'AI' : m['role'] == 'staff' ? 'Customer service' : 'Member', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), Text(m['text']),
            if (m['role'] == 'ai' && m['review'] == 'pending') Row(children: [TextButton(onPressed: () => _post('/api/support/tickets/${widget.id}/messages/${m['id']}/confirm', {}), child: const Text('Confirm')), TextButton(onPressed: () => _correct(m), child: const Text('Correct'))]),
            if (m['review'] == 'confirmed') const Text('✔ Confirmed', style: TextStyle(color: Colors.green, fontSize: 12)),
          ])))).toList())),
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: TextField(controller: reply, decoration: const InputDecoration(hintText: 'Reply to the member'))),
          IconButton(icon: const Icon(Icons.send, color: orange), onPressed: () { final x = reply.text; reply.clear(); if (x.trim().isNotEmpty) _post('/api/support/tickets/${widget.id}/reply', {'text': x}); })])),
      ]),
    );
  }
}

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});
  @override
  State<FaqScreen> createState() => _FaqState();
}

class _FaqState extends State<FaqScreen> {
  List<Map>? faq;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final r = await Api.call('GET', '/api/support/faq'); if (mounted) setState(() => faq = List<Map>.from(r)); }
  Future<void> _add() async {
    final q = TextEditingController(), a = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Teach the chatbot'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: q, decoration: const InputDecoration(labelText: 'Question')), TextField(controller: a, maxLines: 4, decoration: const InputDecoration(labelText: 'Approved answer'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))]));
    if (ok == true) { try { await Api.call('POST', '/api/support/faq', {'q': q.text, 'a': a.text}); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendly(e)))); } }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Approved answers')), floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
        body: faq == null ? const Center(child: CircularProgressIndicator()) : ListView(children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('The AI uses these answers first. Add what members keep asking.', style: TextStyle(color: Colors.grey))),
          ...faq!.map((f) => ListTile(title: Text(f['q']), subtitle: Text(f['a']), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await Api.call('DELETE', '/api/support/faq/${f['_id']}'); _load(); })))]),
      );
}
