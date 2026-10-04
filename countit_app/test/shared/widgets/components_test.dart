import 'dart:async';

import 'package:countit_app/app/errors/app_failure.dart';
import 'package:countit_app/shared/state/load_state.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/widgets/app_button.dart';
import 'package:countit_app/shared/widgets/app_card.dart';
import 'package:countit_app/shared/widgets/app_dialogs.dart';
import 'package:countit_app/shared/widgets/app_feedback.dart';
import 'package:countit_app/shared/widgets/app_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  setUpAll(Dates.init);

  group('AppButton (COU-35)', () {
    testWidgets('tap, disabled and loading', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        Column(
          children: [
            AppButton(label: 'Guardar', onPressed: () => taps++),
            const AppButton(label: 'Deshabilitado', onPressed: null),
            AppButton(label: 'Enviando', loading: true, onPressed: () => taps++),
          ],
        ),
      );
      await tester.tap(find.text('Guardar'));
      await tester.tap(find.byType(AppButton).at(2));
      expect(taps, 1, reason: 'a loading button ignores taps');
      expect(find.text('Enviando'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(find.byType(AppButton).first).height, 52);
    });
  });

  group('fields (COU-35)', () {
    testWidgets('text field shows label and error', (tester) async {
      await tester.pumpApp(const AppTextField(label: 'Nombre', errorText: 'Este campo no puede quedar vacío'));
      expect(find.text('Nombre'), findsOneWidget);
      expect(find.text('Este campo no puede quedar vacío'), findsOneWidget);
    });

    testWidgets('password toggles visibility', (tester) async {
      await tester.pumpApp(const AppPasswordField());
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();
      expect(field().obscureText, isFalse);
    });

    testWidgets('money field rejects a third decimal and letters', (tester) async {
      final controller = TextEditingController();
      await tester.pumpApp(AppMoneyField(controller: controller));
      await tester.enterText(find.byType(TextField), '12.34');
      expect(controller.text, '12.34');
      await tester.enterText(find.byType(TextField), '12.345');
      expect(controller.text, '12.34', reason: 'the edit is refused, the previous value stays');
      await tester.enterText(find.byType(TextField), '12,5');
      expect(controller.text, '12,5');
      await tester.enterText(find.byType(TextField), '1a');
      expect(controller.text, '12,5');
    });

    testWidgets('money field: the «\$» prefix shares the value\'s line box (same baseline)', (tester) async {
      final controller = TextEditingController(text: '1234,56');
      addTearDown(controller.dispose);
      await tester.pumpApp(AppMoneyField(controller: controller));
      final prefix = tester.getRect(find.text(r'$'));
      final value = tester.getRect(find.byType(EditableText));
      expect(prefix.height, moreOrLessEquals(value.height, epsilon: 0.5));
      expect(prefix.top, moreOrLessEquals(value.top, epsilon: 0.5));
      expect(prefix.right, lessThan(value.left));
    });

    testWidgets('date field shows the date in Spanish and a placeholder', (tester) async {
      await tester.pumpApp(
        Column(
          children: [
            AppDateField(
              label: 'Fecha',
              value: DateTime(2026, 10, 3),
              onChanged: (_) {},
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            ),
            AppDateField(
              label: 'Fin',
              value: null,
              onChanged: (_) {},
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            ),
          ],
        ),
      );
      expect(find.text('3 oct 2026'), findsOneWidget);
      expect(find.text('Selecciona una fecha'), findsOneWidget);
    });

    testWidgets('dropdown lists options and reports the choice', (tester) async {
      String? chosen;
      await tester.pumpApp(
        AppDropdownField<String>(
          label: 'Tipo',
          value: null,
          options: const [AppOption('cash', 'Efectivo'), AppOption('savings', 'Ahorros')],
          onChanged: (v) => chosen = v,
        ),
      );
      await tester.tap(find.text('Selecciona una opción'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ahorros').last);
      await tester.pumpAndSettle();
      expect(chosen, 'savings');
    });
  });

  group('cards and dialogs (COU-39)', () {
    testWidgets('confirm dialog returns true / false', (tester) async {
      late BuildContext ctx;
      await tester.pumpApp(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      );

      var result = showConfirmDialog(
        ctx,
        title: 'Eliminar billetera',
        message: 'Esta acción no se puede deshacer',
        confirmLabel: 'Eliminar',
        destructive: true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);

      result = showConfirmDialog(ctx, title: 'T', message: 'M');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);

      result = showConfirmDialog(ctx, title: 'T', message: 'M');
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5)); // outside the dialog
      await tester.pumpAndSettle();
      expect(await result, isFalse, reason: 'dismissing is not confirming');
    });

    testWidgets('bottom sheet shows its title and content', (tester) async {
      late BuildContext ctx;
      await tester.pumpApp(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      );
      unawaited(showAppBottomSheet<void>(ctx, title: 'Filtros', builder: (_) => const Text('Contenido')));
      await tester.pumpAndSettle();
      expect(find.text('Filtros'), findsOneWidget);
      expect(find.text('Contenido'), findsOneWidget);
    });

    testWidgets('card, badge and progress', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        AppCard(
          onTap: () => taps++,
          child: const Column(
            children: [
              AppBadge('Excedido', tone: BadgeTone.warn),
              AppProgressBar(value: 1.3, tone: ProgressTone.over, semanticLabel: 'Servicios'),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(AppCard));
      expect(taps, 1);
      expect(find.text('Excedido'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, 1, reason: 'an exceeded budget shows a full bar');
    });
  });

  group('states and snackbar (COU-42)', () {
    const failure = AppFailure(kind: FailureKind.network, message: 'No hay conexión');

    Widget view(LoadState<List<String>> state, {VoidCallback? onRetry}) => LoadStateView<List<String>>(
      state: state,
      onRetry: onRetry,
      isEmpty: (items) => items.isEmpty,
      empty: const EmptyState(title: 'Aún no tienes billeteras'),
      builder: (context, items) => Text(items.join(',')),
    );

    testWidgets('loading, error with retry, empty and data', (tester) async {
      await tester.pumpApp(view(const LoadState.loading()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      var retries = 0;
      await tester.pumpApp(view(const LoadState.failure(failure), onRetry: () => retries++));
      expect(find.text('No hay conexión'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      expect(retries, 1);

      await tester.pumpApp(view(const LoadState.success([])));
      expect(find.text('Aún no tienes billeteras'), findsOneWidget);

      await tester.pumpApp(view(const LoadState.success(['Ahorros', 'Efectivo'])));
      expect(find.text('Ahorros,Efectivo'), findsOneWidget);
    });

    testWidgets('reloading keeps the previous data visible', (tester) async {
      await tester.pumpApp(view(const LoadState.success(['Ahorros']).reloading()));
      expect(find.text('Ahorros'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('snackbars replace each other instead of piling up', (tester) async {
      late BuildContext ctx;
      await tester.pumpApp(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      );
      showAppSnackBar(ctx, 'Primero');
      showAppSnackBar(ctx, 'Segundo', kind: SnackKind.success);
      showFailureSnackBar(ctx, failure);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('No hay conexión'), findsOneWidget);
    });
  });
}
