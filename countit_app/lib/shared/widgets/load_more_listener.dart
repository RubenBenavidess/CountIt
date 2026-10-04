import 'package:flutter/widgets.dart';

/// Calls [onLoadMore] when the scrollable below gets within [threshold]
/// pixels of its end (infinite scroll). Only the closest scrollable counts;
/// the callback must ignore calls while a page is already loading.
class LoadMoreListener extends StatelessWidget {
  const LoadMoreListener({super.key, required this.onLoadMore, required this.child, this.threshold = 600});

  final VoidCallback onLoadMore;
  final double threshold;
  final Widget child;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 &&
        (notification is ScrollUpdateNotification || notification is ScrollEndNotification) &&
        notification.metrics.extentAfter < threshold) {
      onLoadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(onNotification: _onScroll, child: child);
}
