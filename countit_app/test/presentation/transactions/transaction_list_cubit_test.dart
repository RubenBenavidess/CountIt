import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/transaction.dart';
import 'package:countit_app/presentation/transactions/cubit/transaction_list_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/transaction_fixtures.dart';

const _ana = {'u1': 'María Quishpe'};
const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');

void main() {
  late MockTransactionRepository transactions;

  final first = [
    transactionFixture(id: 3, date: DateTime(2026, 10, 3)),
    transactionFixture(id: 2, date: DateTime(2026, 10, 3)),
  ];
  final second = [transactionFixture(id: 1, date: DateTime(2026, 10, 1))];
  final cursor = TransactionCursor.after(first.last);

  setUpAll(() {
    registerFallbackValue(cursor);
    registerFallbackValue(const TransactionFilter());
  });

  setUp(() => transactions = MockTransactionRepository());

  void firstPage(TransactionPage page) => when(() => transactions.list(4)).thenAnswer((_) async => page);

  void nextPage(TransactionPage page) => when(() => transactions.list(4, after: cursor)).thenAnswer((_) async => page);

  TransactionListState loaded({
    List<Transaction>? items,
    TransactionCursor? next,
    Map<String, String> authors = const {},
  }) => TransactionListState(
    status: TransactionListStatus.success,
    items: items ?? first,
    next: next,
    knownAuthors: authors,
  );

  test('groupByDay puts one header before each day', () {
    final entries = groupByDay([...first, ...second]);
    expect(entries, [
      TransactionDayHeader(DateTime(2026, 10, 3)),
      TransactionRow(first[0]),
      TransactionRow(first[1]),
      TransactionDayHeader(DateTime(2026, 10, 1)),
      TransactionRow(second[0]),
    ]);
  });

  group('load (COU-231)', () {
    blocTest<TransactionListCubit, TransactionListState>(
      'loads the first page of its wallet',
      setUp: () => firstPage(TransactionPage(first, next: cursor)),
      build: () => TransactionListCubit(transactions, walletId: 4),
      act: (cubit) => cubit.load(),
      expect: () => [TransactionListState(status: TransactionListStatus.loading), loaded(next: cursor, authors: _ana)],
    );

    blocTest<TransactionListCubit, TransactionListState>(
      'a failed reload keeps the rows on screen',
      setUp: () => when(() => transactions.list(4)).thenThrow(_network),
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: loaded,
      act: (cubit) => cubit.load(),
      expect: () => [
        TransactionListState(status: TransactionListStatus.loading, items: first),
        TransactionListState(status: TransactionListStatus.failure, items: first, failure: _network),
      ],
    );

    blocTest<TransactionListCubit, TransactionListState>(
      'a reload starts again from the first page (later pages are dropped)',
      setUp: () => firstPage(TransactionPage(first, next: cursor)),
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: () => loaded(items: [...first, ...second]),
      act: (cubit) => cubit.load(),
      skip: 1,
      expect: () => [loaded(next: cursor, authors: _ana)],
    );
  });

  group('loadMore (COU-232)', () {
    blocTest<TransactionListCubit, TransactionListState>(
      'appends the next page after the cursor',
      setUp: () => nextPage(TransactionPage(second)),
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: () => loaded(next: cursor),
      act: (cubit) => cubit.loadMore(),
      expect: () => [
        TransactionListState(status: TransactionListStatus.success, items: first, next: cursor, loadingMore: true),
        loaded(items: [...first, ...second], authors: _ana),
      ],
    );

    blocTest<TransactionListCubit, TransactionListState>(
      'does nothing at the end of the list',
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: loaded,
      act: (cubit) => cubit.loadMore(),
      expect: () => <TransactionListState>[],
      verify: (_) => verifyNever(() => transactions.list(any(), after: any(named: 'after'))),
    );

    blocTest<TransactionListCubit, TransactionListState>(
      'concurrent calls request the next page once',
      setUp: () => nextPage(TransactionPage(second)),
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: () => loaded(next: cursor),
      act: (cubit) => Future.wait([cubit.loadMore(), cubit.loadMore()]),
      verify: (_) => verify(() => transactions.list(4, after: cursor)).called(1),
    );

    blocTest<TransactionListCubit, TransactionListState>(
      'a failure keeps the rows; scrolling does not retry, the retry button does',
      setUp: () => when(() => transactions.list(4, after: cursor)).thenThrow(_network),
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: () => loaded(next: cursor),
      act: (cubit) async {
        await cubit.loadMore();
        await cubit.loadMore();
        await cubit.loadMore(retry: true);
      },
      expect: () => [
        TransactionListState(status: TransactionListStatus.success, items: first, next: cursor, loadingMore: true),
        TransactionListState(status: TransactionListStatus.success, items: first, next: cursor, moreFailure: _network),
        TransactionListState(status: TransactionListStatus.success, items: first, next: cursor, loadingMore: true),
        TransactionListState(status: TransactionListStatus.success, items: first, next: cursor, moreFailure: _network),
      ],
      verify: (_) => verify(() => transactions.list(4, after: cursor)).called(2),
    );

    late Completer<TransactionPage> slow;

    blocTest<TransactionListCubit, TransactionListState>(
      'a page that arrives after a reload started is dropped (no mixed queries)',
      setUp: () {
        slow = Completer<TransactionPage>();
        when(() => transactions.list(4, after: cursor)).thenAnswer((_) => slow.future);
        firstPage(TransactionPage([transactionFixture(id: 9)]));
      },
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: () => loaded(next: cursor),
      act: (cubit) async {
        final more = cubit.loadMore();
        await cubit.load();
        slow.complete(TransactionPage(second));
        await more;
      },
      verify: (cubit) {
        expect(cubit.state.items.map((t) => t.transactionId), [9]);
        expect(cubit.state.loadingMore, isFalse);
      },
    );
  });

  group('filters (COU-234)', () {
    const expenses = TransactionFilter(type: TransactionType.expense);

    blocTest<TransactionListCubit, TransactionListState>(
      'applying a filter clears the rows and lists again with it',
      setUp: () => when(() => transactions.list(4, filter: expenses)).thenAnswer((_) async => TransactionPage(second)),
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: () => loaded(authors: _ana),
      act: (cubit) => cubit.applyFilter(expenses),
      expect: () => [
        TransactionListState(filter: expenses, knownAuthors: _ana),
        TransactionListState(status: TransactionListStatus.loading, filter: expenses, knownAuthors: _ana),
        TransactionListState(
          status: TransactionListStatus.success,
          items: second,
          filter: expenses,
          knownAuthors: _ana,
        ),
      ],
    );

    blocTest<TransactionListCubit, TransactionListState>(
      'the same filter again does nothing',
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: () => TransactionListState(status: TransactionListStatus.success, filter: expenses),
      act: (cubit) => cubit.applyFilter(expenses),
      expect: () => <TransactionListState>[],
    );

    blocTest<TransactionListCubit, TransactionListState>(
      'next pages keep the filter',
      setUp: () =>
          when(() => transactions.list(4, filter: expenses, after: cursor))
              .thenAnswer((_) async => TransactionPage(second)),
      build: () => TransactionListCubit(transactions, walletId: 4),
      seed: () =>
          TransactionListState(status: TransactionListStatus.success, items: first, next: cursor, filter: expenses),
      act: (cubit) => cubit.loadMore(),
      verify: (_) => verify(() => transactions.list(4, filter: expenses, after: cursor)).called(1),
    );

    late Completer<TransactionPage> slow;

    blocTest<TransactionListCubit, TransactionListState>(
      'changing filters quickly: only the last filter\'s answer is shown',
      setUp: () {
        slow = Completer<TransactionPage>();
        when(() => transactions.list(4, filter: expenses)).thenAnswer((_) => slow.future);
        when(() => transactions.list(4, filter: const TransactionFilter(type: TransactionType.income)))
            .thenAnswer((_) async => TransactionPage([transactionFixture(id: 8, type: TransactionType.income)]));
      },
      build: () => TransactionListCubit(transactions, walletId: 4),
      act: (cubit) async {
        final first = cubit.applyFilter(expenses);
        await cubit.applyFilter(const TransactionFilter(type: TransactionType.income));
        slow.complete(TransactionPage(second));
        await first;
      },
      verify: (cubit) {
        expect(cubit.state.filter.type, TransactionType.income);
        expect(cubit.state.items.map((t) => t.transactionId), [8]);
      },
    );

    test('authors accumulate across pages and filters', () {
      final state = TransactionListState(knownAuthors: _ana);
      final merged = state.authorsWith([
        transactionFixture(userId: 'u2', authorName: 'Luis'),
        transactionFixture(userId: null, authorName: null),
      ]);
      expect(merged, {'u1': 'María Quishpe', 'u2': 'Luis'});
      expect(identical(state.authorsWith([transactionFixture()]), state.knownAuthors), isTrue);
    });
  });
}
