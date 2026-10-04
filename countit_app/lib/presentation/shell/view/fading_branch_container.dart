import 'package:flutter/material.dart';

import '../../../shared/widgets/motion.dart';

/// Tabs of the shell, all kept alive like an `IndexedStack`, with a short
/// cross-fade when the tab changes (instant with reduced motion).
///
/// Hidden tabs stay mounted but get no taps, no tickers (`TickerMode`, which
/// `VisibleTabListener` relies on), no semantics and no heroes; once faded
/// out they are offstage (not painted, not hit-tested).
class FadingBranchContainer extends StatelessWidget {
  const FadingBranchContainer({super.key, required this.currentIndex, required this.children});

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.of(context, AppMotion.medium);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          _Branch(active: i == currentIndex, duration: duration, child: children[i]),
      ],
    );
  }
}

class _Branch extends StatefulWidget {
  const _Branch({required this.active, required this.duration, required this.child});

  final bool active;
  final Duration duration;
  final Widget child;

  @override
  State<_Branch> createState() => _BranchState();
}

class _BranchState extends State<_Branch> {
  /// On screen: the active tab, or the previous one while it fades out.
  late bool _shown = widget.active;

  @override
  void didUpdateWidget(_Branch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) {
      _shown = true;
    } else if (widget.duration == Duration.zero) {
      _shown = false;
    }
  }

  void _faded() {
    if (!widget.active && _shown && mounted) setState(() => _shown = false);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Offstage(
      offstage: !_shown,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: widget.duration,
        curve: AppMotion.standard,
        onEnd: _faded,
        child: IgnorePointer(
          ignoring: !active,
          child: ExcludeSemantics(
            excluding: !active,
            child: HeroMode(
              enabled: active,
              child: TickerMode(enabled: active, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
