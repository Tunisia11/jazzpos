import 'package:flutter/material.dart';
import 'package:jazzpos/ui/theme/app_design_tokens.dart';

/// Shows the Trace POS logo on a white screen for a moment at launch, then
/// fades into [child]. The app keeps initialising underneath, so this adds no
/// extra waiting beyond [duration].
class SplashGate extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const SplashGate({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.duration == Duration.zero) {
      _done = true;
    } else {
      Future<void>.delayed(widget.duration, () {
        if (mounted) setState(() => _done = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _done
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : const _SplashView(key: ValueKey('splash')),
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage('assets/images/trace_logo_mark.png'),
              width: 180,
              fit: BoxFit.contain,
            ),
            SizedBox(height: 20),
            Text(
              'Trace POS',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: AppDesignTokens.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),
            SizedBox(height: 28),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 3,
                color: AppDesignTokens.primary,
                backgroundColor: AppDesignTokens.primarySoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
