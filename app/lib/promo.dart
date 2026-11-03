import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';

/// Banner shape = the staff console crop (1000 x 319), the same wide rectangle for every announcement picture.
const bannerRatio = 1000 / 319;

/// One picture shows still. Two or more slide by themselves, one after the other.
class BannerCarousel extends StatefulWidget {
  final List<String> urls; final VoidCallback? onTap; final Duration every;
  const BannerCarousel({super.key, required this.urls, this.onTap, this.every = const Duration(seconds: 4)});
  @override
  State<BannerCarousel> createState() => _BannerState();
}

class _BannerState extends State<BannerCarousel> {
  final pc = PageController(); int i = 0; Timer? t;

  @override
  void initState() { super.initState(); _start(); }
  @override
  void didUpdateWidget(BannerCarousel old) { super.didUpdateWidget(old); if (old.urls.length != widget.urls.length) _start(); }
  void _start() {
    t?.cancel();
    if (widget.urls.length < 2) return;
    t = Timer.periodic(widget.every, (_) {
      if (!mounted || !pc.hasClients) return;
      pc.animateToPage((i + 1) % widget.urls.length, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }
  @override
  void dispose() { t?.cancel(); pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final n = widget.urls.length;
    return GestureDetector(onTap: widget.onTap, child: ClipRRect(borderRadius: BorderRadius.circular(18), child: AspectRatio(aspectRatio: bannerRatio, child: Stack(fit: StackFit.expand, children: [
      PageView.builder(controller: pc, itemCount: n, onPageChanged: (x) => setState(() => i = x), itemBuilder: (_, k) {
        final u = widget.urls[k];
        return Image.network(u.startsWith('http') ? u : '${Api.base}$u', fit: BoxFit.cover,
            loadingBuilder: (c, child, p) => p == null ? child : Container(color: Theme.of(context).cardColor),
            errorBuilder: (c, e, s) => Container(color: Theme.of(context).cardColor, child: const Icon(Icons.image_not_supported, color: Colors.grey)));
      }),
      if (n > 1) Positioned(bottom: 6, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(n, (k) => AnimatedContainer(duration: const Duration(milliseconds: 250), margin: const EdgeInsets.symmetric(horizontal: 3), width: k == i ? 14 : 6, height: 6,
              decoration: BoxDecoration(color: k == i ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(3)))))),
    ]))));
  }
}
