import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension BackNavigation on BuildContext {
  /// Back to the previous screen, or to [fallback] when this one was opened
  /// directly (a redirect or a deep link left nothing to pop).
  void backOr(String fallback) => canPop() ? pop() : go(fallback);
}
