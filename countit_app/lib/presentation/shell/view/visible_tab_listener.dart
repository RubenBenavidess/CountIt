import 'package:flutter/widgets.dart';

/// Calls [onVisible] each time the shell tab holding [child] comes back on
/// screen. The shell keeps hidden tabs mounted with tickers disabled
/// (`TickerMode`), so the switch is a dependency change: no polling, and
/// nothing runs while the tab stays hidden. The first build does not count
/// (the screen loads its data itself).
class VisibleTabListener extends StatefulWidget {
  const VisibleTabListener({super.key, required this.onVisible, required this.child});

  final VoidCallback onVisible;
  final Widget child;

  @override
  State<VisibleTabListener> createState() => _VisibleTabListenerState();
}

class _VisibleTabListenerState extends State<VisibleTabListener> {
  bool? _visible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_visible == false && visible) widget.onVisible();
    _visible = visible;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
