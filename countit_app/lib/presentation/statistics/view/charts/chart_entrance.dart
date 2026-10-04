import 'package:flutter/widgets.dart';

import '../../../../shared/widgets/motion.dart';

/// Entrance of a chart: [builder] gets 0→1 over 350 ms when the chart first
/// shows and again when [data] is another answer (another range or wallet);
/// selecting a bar or a point does not replay it. With reduced motion it is
/// 1 from the start.
class ChartEntrance extends StatefulWidget {
  const ChartEntrance({super.key, required this.data, required this.builder});

  /// The data drawn; compared by identity.
  final Object data;
  final Widget Function(BuildContext context, double progress) builder;

  @override
  State<ChartEntrance> createState() => _ChartEntranceState();
}

class _ChartEntranceState extends State<ChartEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.slow);
  late final Animation<double> _progress = CurvedAnimation(parent: _controller, curve: AppMotion.enter);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _play();
  }

  @override
  void didUpdateWidget(ChartEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) _play();
  }

  void _play() {
    if (AppMotion.enabled(context)) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _progress, builder: (context, _) => widget.builder(context, _progress.value));
}
