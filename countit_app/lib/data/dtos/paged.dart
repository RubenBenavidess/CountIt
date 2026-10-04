import 'package:equatable/equatable.dart';

/// One page of a paginated list (admin lists, notifications).
class Paged<T> extends Equatable {
  const Paged(this.items, {required this.hasMore});

  final List<T> items;

  /// The server had at least one more row after this page.
  final bool hasMore;

  @override
  List<Object?> get props => [items, hasMore];
}
