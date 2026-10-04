import 'package:equatable/equatable.dart';

import '../../app/errors/app_failure.dart';

enum LoadStatus { initial, loading, success, failure }

/// Generic state for Cubits that load data: the Bloc counterpart of an
/// async value. Keeps the last data while reloading so lists do not flash.
class LoadState<T> extends Equatable {
  const LoadState._(this.status, {this.data, this.failure});

  const LoadState.initial() : this._(LoadStatus.initial);

  const LoadState.loading({T? previous}) : this._(LoadStatus.loading, data: previous);

  const LoadState.success(T data) : this._(LoadStatus.success, data: data);

  const LoadState.failure(AppFailure failure, {T? previous})
    : this._(LoadStatus.failure, data: previous, failure: failure);

  final LoadStatus status;
  final T? data;
  final AppFailure? failure;

  bool get isLoading => status == LoadStatus.loading || status == LoadStatus.initial;

  /// Next loading state keeping the current data (pull-to-refresh).
  LoadState<T> reloading() => LoadState.loading(previous: data);

  @override
  List<Object?> get props => [status, data, failure];
}
