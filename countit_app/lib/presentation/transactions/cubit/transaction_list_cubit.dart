import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/errors/app_failure.dart';
import '../../../data/dtos/transaction.dart';
import '../../../data/repositories/transaction_repository.dart';

/// A line of the grouped list: a day header or a transaction.
sealed class TransactionListEntry extends Equatable {
  const TransactionListEntry();
}

class TransactionDayHeader extends TransactionListEntry {
  const TransactionDayHeader(this.day);

  final DateTime day;

  @override
  List<Object?> get props => [day];
}

class TransactionRow extends TransactionListEntry {
  const TransactionRow(this.transaction);

  final Transaction transaction;

  @override
  List<Object?> get props => [transaction];
}

/// Inserts a header before the first transaction of each day. [items] come
/// sorted by date descending, so one pass is enough.
List<TransactionListEntry> groupByDay(List<Transaction> items) {
  final entries = <TransactionListEntry>[];
  DateTime? current;
  for (final transaction in items) {
    if (transaction.date != current) {
      current = transaction.date;
      entries.add(TransactionDayHeader(current));
    }
    entries.add(TransactionRow(transaction));
  }
  return entries;
}

enum TransactionListStatus { initial, loading, success, failure }

class TransactionListState extends Equatable {
  TransactionListState({
    this.status = TransactionListStatus.initial,
    this.items = const [],
    this.next,
    this.loadingMore = false,
    this.failure,
    this.moreFailure,
    this.filter = const TransactionFilter(),
    this.knownAuthors = const {},
  }) : entries = groupByDay(items);

  final TransactionListStatus status;

  /// Every page loaded so far, newest first.
  final List<Transaction> items;

  /// Where the next page starts; null when the last page is loaded.
  final TransactionCursor? next;

  /// A next page is on its way (spinner at the end of the list).
  final bool loadingMore;

  /// Error of the first page (with [items] kept from a previous load, if any).
  final AppFailure? failure;

  /// Error of the last «load more» (retry row at the end of the list).
  final AppFailure? moreFailure;

  /// The active filters (COU-234).
  final TransactionFilter filter;

  /// Authors (`user_id` → `author_name`) seen in every page loaded so far,
  /// under any filter: the options of the author filter.
  final Map<String, String> knownAuthors;

  /// [items] with day headers, computed once per state (not in `build`).
  final List<TransactionListEntry> entries;

  bool get hasMore => next != null;

  /// Nothing loaded yet: the first load is running or failed.
  bool get isFirstLoad => status != TransactionListStatus.success && items.isEmpty;

  TransactionListState copyWith({
    TransactionListStatus? status,
    List<Transaction>? items,
    TransactionCursor? Function()? next,
    bool? loadingMore,
    AppFailure? Function()? failure,
    AppFailure? Function()? moreFailure,
    TransactionFilter? filter,
    Map<String, String>? knownAuthors,
  }) => TransactionListState(
    status: status ?? this.status,
    items: items ?? this.items,
    next: next == null ? this.next : next(),
    loadingMore: loadingMore ?? this.loadingMore,
    failure: failure == null ? this.failure : failure(),
    moreFailure: moreFailure == null ? this.moreFailure : moreFailure(),
    filter: filter ?? this.filter,
    knownAuthors: knownAuthors ?? this.knownAuthors,
  );

  /// [knownAuthors] plus the authors of [page].
  Map<String, String> authorsWith(List<Transaction> page) {
    final added = {
      for (final t in page)
        if (t.userId != null && t.authorName != null && !knownAuthors.containsKey(t.userId)) t.userId!: t.authorName!,
    };
    return added.isEmpty ? knownAuthors : {...knownAuthors, ...added};
  }

  @override
  List<Object?> get props => [status, items, next, loadingMore, failure, moreFailure, filter, knownAuthors];
}

/// HU-17: the transactions of one wallet, newest first, loaded page by page
/// and filtered (COU-231, COU-232, COU-234).
///
/// Every [load] starts a new generation: answers of an older load or of a
/// «load more» started before it are dropped, so a slow response can never
/// mix pages of two different queries.
class TransactionListCubit extends Cubit<TransactionListState> {
  TransactionListCubit(this._transactions, {required this.walletId}) : super(TransactionListState());

  final TransactionRepository _transactions;
  final int walletId;
  int _generation = 0;

  /// (Re)loads the first page; the current rows stay visible meanwhile.
  Future<void> load() async {
    final generation = ++_generation;
    emit(
      state.copyWith(
        status: TransactionListStatus.loading,
        loadingMore: false,
        failure: () => null,
        moreFailure: () => null,
      ),
    );
    try {
      final page = await _transactions.list(walletId, filter: state.filter);
      if (_isStale(generation)) return;
      emit(
        state.copyWith(
          status: TransactionListStatus.success,
          items: page.items,
          next: () => page.next,
          knownAuthors: state.authorsWith(page.items),
        ),
      );
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      emit(state.copyWith(status: TransactionListStatus.failure, failure: () => failure));
    }
  }

  /// Appends the next page; ignored while loading or at the end. After a
  /// failure only an explicit [retry] tries again, so scrolling near the end
  /// does not hammer a failing backend.
  Future<void> loadMore({bool retry = false}) async {
    final cursor = state.next;
    if (cursor == null || state.loadingMore || state.status != TransactionListStatus.success) return;
    if (state.moreFailure != null && !retry) return;
    final generation = _generation;
    emit(state.copyWith(loadingMore: true, moreFailure: () => null));
    try {
      final page = await _transactions.list(walletId, filter: state.filter, after: cursor);
      if (_isStale(generation)) return;
      emit(
        state.copyWith(
          items: [...state.items, ...page.items],
          next: () => page.next,
          loadingMore: false,
          knownAuthors: state.authorsWith(page.items),
        ),
      );
    } on AppFailure catch (failure) {
      if (_isStale(generation)) return;
      emit(state.copyWith(loadingMore: false, moreFailure: () => failure));
    }
  }

  /// Lists again with [filter]. Rows of the previous filter are cleared at
  /// once (they would not match) and any answer still on its way is dropped.
  Future<void> applyFilter(TransactionFilter filter) async {
    if (filter == state.filter && state.status != TransactionListStatus.failure) return;
    emit(TransactionListState(filter: filter, knownAuthors: state.knownAuthors));
    await load();
  }

  bool _isStale(int generation) => isClosed || generation != _generation;
}
