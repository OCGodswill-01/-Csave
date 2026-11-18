import 'package:flutter/material.dart';
import 'api.dart';
import 'screens.dart';
import 'splash.dart';
import 'main.dart';

/// Shown when a member has not finished KYC or has not paid the membership fee.
/// It says exactly what is missing and links to the right step.
class KycGateScreen extends StatefulWidget {
  const KycGateScreen({super.key});
  @override
  State<KycGateScreen> createState() => _KycGateState();
}

class _KycGateState extends State<KycGateScreen> {
  Map<String, dynamic>? me;
  String? err;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final d = Map<String, dynamic>.from(await Api.call('GET', '/api/me'));
      if (mounted) setState(() { me = d; err = null; });
    } catch (e) {
      if (mounted) setState(() => err = friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = me;
    final status = d?['kycStatus'] ?? 'none';
    final paid = d?['membershipPaid'] == true;
    final reason = d?['kycRejectReason'];
    String headline;
    String text;
    String? button;
    VoidCallback? go;

    if (status == 'approved' && !paid) {
      headline = 'KYC approved';
      text = 'Pay the one-time ₦5,000 membership fee to unlock CSave.';
      button = 'Pay membership';
      go = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MembershipScreen())).then((_) => _load());
    } else if (status == 'pending') {
      headline = 'KYC under review';
      text = 'Our team is checking your details and photos. We will notify you when it is done.';
    } else if (status == 'rejected') {
      headline = 'KYC needs correction';
      text = reason != null ? 'Reason: $reason' : 'Please check your details and submit again.';
      button = 'Complete KYC';
      go = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KycScreen())).then((_) => _load());
    } else {
      headline = 'Complete your KYC';
      text = 'Fill in your details and take the four photos. Our team reviews them, then you pay the ₦5,000 membership fee.';
      button = 'Complete KYC';
      go = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KycScreen())).then((_) => _load());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('CSave')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(headline, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (err != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(err!, style: const TextStyle(color: Colors.redAccent))),
            const SizedBox(height: 24),
            if (button != null && go != null) FilledButton(onPressed: go, child: Text(button)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                await Api.clearAccount();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Splash(next: Entry())), (_) => false);
                }
              },
              child: const Text('Logout'),
            ),
          ]),
        ),
      ),
    );
  }
}
