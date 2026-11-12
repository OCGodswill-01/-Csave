import 'package:flutter/material.dart';

const _gold = Color(0xFFFFC61A);

/// Shown while the app opens and loads its first data. Black background, gold logo,
/// a thin gold line, then the tagline in a gold serif font.
class Splash extends StatefulWidget {
  final Widget next;
  const Splash({super.key, required this.next});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.next));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/logo.png', width: 180, height: 180),
            const SizedBox(height: 40),
            Container(width: 240, height: 2, color: _gold),
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Your financial wholeness is possible',
                textAlign: TextAlign.center,
                style: TextStyle(color: _gold, fontSize: 26, fontWeight: FontWeight.bold, fontFamily: 'serif', height: 1.3),
              ),
            ),
          ]),
        ),
      );
}
