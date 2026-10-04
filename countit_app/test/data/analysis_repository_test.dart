import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/data/dtos/statistics.dart';
import 'package:countit_app/data/repositories/analysis_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';
import '../helpers/statistics_fixtures.dart';

void main() {
  late MockApiClient api;
  late SupabaseAnalysisRepository analysis;

  setUp(() {
    api = MockApiClient();
    analysis = SupabaseAnalysisRepository(api);
  });

  group('walletStatistics (COU-22)', () {
    test('calls get_wallet_statistics with the wallet and the API range', () async {
      when(() => api.rpc<dynamic>(any(), params: any(named: 'params')))
          .thenAnswer((_) async => statisticsJson(range: '3m'));
      final stats = await analysis.walletStatistics(4, StatisticsRange.months3);
      verify(() => api.rpc<dynamic>('get_wallet_statistics', params: {'p_wallet_id': 4, 'p_range': '3m'})).called(1);
      expect(stats.range, StatisticsRange.months3);
    });

    test('a 404 wallet_not_found reaches the caller unchanged', () async {
      const failure = AppFailure(
        kind: FailureKind.notFound,
        message: 'Billetera no encontrada',
        key: 'wallet_not_found',
        status: 404,
      );
      when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenThrow(failure);
      await expectLater(analysis.walletStatistics(9, StatisticsRange.days30), throwsA(failure));
    });

    test('an unexpected answer is a server failure, never a crash', () async {
      when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => null);
      await expectLater(
        analysis.walletStatistics(4, StatisticsRange.days30),
        throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.server)),
      );
      when(() => api.rpc<dynamic>(any(), params: any(named: 'params'))).thenAnswer((_) async => {'wallet_id': 4});
      await expectLater(
        analysis.walletStatistics(4, StatisticsRange.days30),
        throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.server)),
      );
    });
  });
}
