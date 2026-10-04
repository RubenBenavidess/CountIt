import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

/// Motion of the app: short (150–350 ms), standard curves, never infinite and
/// never in the way of a tap. Everything here turns off when the system asks
/// to reduce motion (`MediaQuery.disableAnimationsOf`): the final state shows
/// at once.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 350);

  /// Things that enter or grow: decelerate into place.
  static const enter = Curves.easeOutCubic;

  /// Things that change state in place.
  static const standard = Curves.easeInOutCubic;

  /// False when the user (or a test) asked to reduce motion.
  static bool enabled(BuildContext context) => !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// [duration], or zero when motion is reduced.
  static Duration of(BuildContext context, Duration duration) => enabled(context) ? duration : Duration.zero;
}

/// Page transition of every route (theme-wide, so each `GoRoute` gets it
/// without a `CustomTransitionPage`): the new page fades in while rising
/// 4 % of the screen; the page below fades slightly. Instant with reduced
/// motion.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  static final _rise = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero);
  static final _dim = Tween<double>(begin: 1, end: 0.92);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!AppMotion.enabled(context)) return child;
    final enter = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: Curves.easeInCubic);
    final below = CurvedAnimation(parent: secondaryAnimation, curve: AppMotion.standard);
    return FadeTransition(
      opacity: _dim.animate(below),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(position: _rise.animate(enter), child: child),
      ),
    );
  }
}

/// Number that counts briefly to its value (balances): from 0 the first
/// time, then from the value on screen. Inside a list ([StaggerScope]) only
/// with the first load, not when a card scrolls back into view. Screen
/// readers get the final value.
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.value, required this.format, this.style});

  final double value;
  final String Function(double value) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = format(value);
    if (!AppMotion.enabled(context)) return Text(text, style: style);
    return Semantics(
      label: text,
      excludeSemantics: true,
      // TweenAnimationBuilder starts at `begin` once; later values animate
      // from wherever the number is.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: StaggerScope.isFresh(context) ? 0 : value, end: value),
        duration: AppMotion.slow,
        curve: AppMotion.enter,
        // The final text (invisible) sizes the box, so the layout never
        // jumps meanwhile; a RichText, so text finders see one number.
        builder: (context, current, _) => Stack(
          children: [
            Visibility.maintain(
              visible: false,
              child: RichText(
                text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
              ),
            ),
            Text(format(current), style: style, maxLines: 1),
          ],
        ),
      ),
    );
  }
}

/// Marks when a list first showed its data, so its items enter one after
/// another only then: items built later (scrolling, reloads) appear as is.
class StaggerScope extends StatefulWidget {
  const StaggerScope({super.key, required this.child});

  final Widget child;

  /// How long after the first frame items still enter animated.
  static const window = Duration(milliseconds: 500);

  /// Whether something built now may play its entrance: outside any scope,
  /// or within the [window] of the scope above it.
  static bool isFresh(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_StaggerStart>();
    return scope == null || clock.now().difference(scope.start) < window;
  }

  @override
  State<StaggerScope> createState() => _StaggerScopeState();
}

class _StaggerScopeState extends State<StaggerScope> {
  final DateTime _start = clock.now();

  @override
  Widget build(BuildContext context) => _StaggerStart(start: _start, child: widget.child);
}

class _StaggerStart extends InheritedWidget {
  const _StaggerStart({required this.start, required super.child});

  final DateTime start;

  @override
  bool updateShouldNotify(_StaggerStart oldWidget) => start != oldWidget.start;
}

/// Item of a list that fades and rises into place, [index] × 40 ms after the
/// first ones (at most 8 steps, so nothing waits more than ~0.6 s). Only
/// inside the [StaggerScope]'s first moments; never with reduced motion.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late Animation<double> _curve;

  static const _step = Duration(milliseconds: 40);
  static const _maxSteps = 8;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final inScope = context.getInheritedWidgetOfExactType<_StaggerStart>() != null;
    if (!inScope || !StaggerScope.isFresh(context) || !AppMotion.enabled(context)) return;
    final delay = _step * widget.index.clamp(0, _maxSteps);
    final total = delay + AppMotion.medium;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _curve = CurvedAnimation(
      parent: controller,
      curve: Interval(delay.inMilliseconds / total.inMilliseconds, 1, curve: AppMotion.enter),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Slight scale-down while pressed (97 %): feedback for buttons and cards.
/// It never delays the tap; with reduced motion it does nothing.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !AppMotion.enabled(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: widget.child,
      ),
    );
  }
}

/// Progress from 0 to [value] the first time, then from the previous value:
/// [builder] paints it (bars, charts).
class AnimatedProgress extends StatelessWidget {
  const AnimatedProgress({super.key, required this.value, required this.builder, this.duration = AppMotion.slow});

  final double value;
  final Duration duration;
  final Widget Function(BuildContext context, double value) builder;

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.enabled(context)) return builder(context, value);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: AppMotion.enter,
      builder: (context, current, _) => builder(context, current),
    );
  }
}
