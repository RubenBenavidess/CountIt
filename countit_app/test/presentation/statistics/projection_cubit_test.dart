import 'package:bloc_test/bloc_test.dart';
import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/presentation/statistics/cubit/projection_cubit.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';
import '../../helpers/projection_fixtures.dart';

const _network = AppFailure(kind: FailureKind.network, message: 'No hay conexión.');
const _notInPlan = AppFailure(
  kind: FailureKind.featureNotInPlan,
  message: 'Tu plan no incluye la proyección de billeteras',
  key: 'feature_not_in_plan',
  status: 403,
);

void main() {
  late MockAnalysisRepository analysis;
  final auto = projectionFixture();
  final december = projectionFixture(until: '2026-12-31');
  final dec31 = DateTime(2026, 12, 31);

  setUp(() {
    analysis = MockAnalysisRepository();
    when(() => analysis.walletProjection(4)).thenAnswer((_) async => auto);
    when(() => analysis.walletProjection(4, until: dec31)).thenAnswer((_) async => december);
  });

  ProjectionCubit build({bool allowed = true}) => ProjectionCubit(analysis, walletId: 4, allowed: allowed);

  group('ProjectionCubit (COU-99, COU-172)', () {
    blocTest<ProjectionCubit, ProjectionState>(
      'loads the automatic horizon',
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => [
        const ProjectionState(projection: LoadState.loading()),
        ProjectionState(projection: LoadState.success(auto)),
      ],
    );

    blocTest<ProjectionCubit, ProjectionState>(
      'a plan known to lack the feature never calls the API',
      build: () => build(allowed: false),
      act: (cubit) => cubit.load(),
      expect: () => [const ProjectionState(locked: true)],
      verify: (_) => verifyNever(() => analysis.walletProjection(any(), until: any(named: 'until'))),
    );

    blocTest<ProjectionCubit, ProjectionState>(
      'the API decides: 403 feature_not_in_plan locks the screen',
      setUp: () => when(() => analysis.walletProjection(4)).thenThrow(_notInPlan),
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => [const ProjectionState(projection: LoadState.loading()), const ProjectionState(locked: true)],
    );

    blocTest<ProjectionCubit, ProjectionState>(
      'a chosen date, then back to automatic from memory',
      build: build,
      act: (cubit) async {
        await cubit.load();
        await cubit.selectUntil(dec31);
        await cubit.selectUntil(null);
      },
      skip: 2,
      expect: () => [
        ProjectionState(until: dec31, projection: const LoadState.loading()),
        ProjectionState(until: dec31, projection: LoadState.success(december)),
        ProjectionState(projection: LoadState.success(auto)),
      ],
      verify: (_) => verify(() => analysis.walletProjection(4)).called(1),
    );

    blocTest<ProjectionCubit, ProjectionState>(
      'a failed refresh keeps the projection with the error',
      build: build,
      seed: () => ProjectionState(projection: LoadState.success(auto)),
      act: (cubit) {
        when(() => analysis.walletProjection(4)).thenThrow(_network);
        return cubit.refresh();
      },
      expect: () => [
        ProjectionState(projection: LoadState.loading(previous: auto)),
        ProjectionState(projection: LoadState.failure(_network, previous: auto)),
      ],
    );
  });
}
