import 'package:countit_app/presentation/shell/view/fading_branch_container.dart';
import 'package:countit_app/presentation/statistics/view/charts/chart_entrance.dart';
import 'package:countit_app/shared/utils/dates.dart';
import 'package:countit_app/shared/utils/money.dart';
import 'package:countit_app/shared/widgets/app_button.dart';
import 'package:countit_app/shared/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// [child] as a user who asked the system to reduce motion.
Widget _reduced(Widget child) => Builder(
  builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child),
);

void main() {
  setUpAll(Dates.init);

  group('CountUpText', () {
    testWidgets('counts briefly to the value; screen readers hear only the final one', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpApp(const CountUpText(value: 1250.5, format: Money.format));
      expect(find.text(r'$0,00'), findsOneWidget);
      expect(find.bySemanticsLabel(r'$1.250,50'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text(r'$1.250,50'), findsNothing, reason: 'still counting');
      await tester.pumpAndSettle();
      expect(find.text(r'$1.250,50'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('in a list, only with the first load (not when a card scrolls back into view)', (tester) async {
      final show = ValueNotifier(false);
      addTearDown(show.dispose);
      await tester.pumpApp(
        StaggerScope(
          child: ValueListenableBuilder(
            valueListenable: show,
            builder: (context, visible, _) =>
                visible ? const CountUpText(value: 20, format: Money.format) : const SizedBox(),
          ),
        ),
      );
      await tester.pump(StaggerScope.window + const Duration(milliseconds: 1));
      show.value = true;
      await tester.pump();
      expect(find.text(r'$20,00'), findsOneWidget);
    });

    testWidgets('with reduced motion the value shows at once', (tester) async {
      await tester.pumpApp(_reduced(const CountUpText(value: 1250.5, format: Money.format)));
      expect(find.text(r'$1.250,50'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('StaggeredEntrance', () {
    Widget list({int count = 3}) => StaggerScope(
      child: Column(
        children: [for (var i = 0; i < count; i++) StaggeredEntrance(index: i, child: Text('Fila $i'))],
      ),
    );

    double opacityOf(WidgetTester tester, String text) => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.ancestor(of: find.text(text), matching: find.byType(StaggeredEntrance)),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    testWidgets('items of the first load enter one after another, under 0.6 s', (tester) async {
      await tester.pumpApp(list());
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf(tester, 'Fila 0'), greaterThan(opacityOf(tester, 'Fila 2')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isFalse);
      expect(opacityOf(tester, 'Fila 2'), 1);
    });

    testWidgets('items built after the first moments appear as they are (scrolling back, next pages)', (tester) async {
      final show = ValueNotifier(false);
      addTearDown(show.dispose);
      await tester.pumpApp(
        StaggerScope(
          child: ValueListenableBuilder(
            valueListenable: show,
            builder: (context, visible, _) => visible
                ? Column(
                    children: [for (var i = 0; i < 3; i++) StaggeredEntrance(index: i, child: Text('Fila $i'))],
                  )
                : const SizedBox(),
          ),
        ),
      );
      await tester.pump(StaggerScope.window + const Duration(milliseconds: 1));
      show.value = true;
      await tester.pump();
      expect(find.descendant(of: find.byType(StaggeredEntrance), matching: find.byType(FadeTransition)), findsNothing);
    });

    testWidgets('nothing moves with reduced motion', (tester) async {
      await tester.pumpApp(_reduced(list()));
      expect(find.descendant(of: find.byType(StaggeredEntrance), matching: find.byType(SlideTransition)), findsNothing);
    });
  });

  group('PressScale', () {
    testWidgets('a pressed button shrinks a little and the tap still lands', (tester) async {
      var taps = 0;
      await tester.pumpApp(AppButton(label: 'Guardar', onPressed: () => taps++));
      double scale() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      final gesture = await tester.startGesture(tester.getCenter(find.text('Guardar')));
      await tester.pump();
      expect(scale(), lessThan(1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scale(), 1);
      expect(taps, 1);
    });

    testWidgets('disabled buttons and reduced motion do not scale', (tester) async {
      await tester.pumpApp(
        Column(
          children: [
            const AppButton(label: 'Deshabilitado', onPressed: null),
            _reduced(AppButton(label: 'Quieto', onPressed: () {})),
          ],
        ),
      );
      expect(find.byType(AnimatedScale), findsNothing);
    });
  });

  testWidgets('AnimatedProgress fills from empty to the value', (tester) async {
    double? shown;
    await tester.pumpApp(
      AnimatedProgress(
        value: 0.8,
        builder: (context, value) {
          shown = value;
          return const SizedBox();
        },
      ),
    );
    expect(shown, 0);
    await tester.pumpAndSettle();
    expect(shown, 0.8);
  });

  group('ChartEntrance', () {
    testWidgets('plays when the chart shows and again with other data, not on other rebuilds', (tester) async {
      final values = <double>[];
      Widget chart(Object data) => ChartEntrance(
        data: data,
        builder: (context, progress) {
          values.add(progress);
          return const SizedBox();
        },
      );
      final first = Object();
      await tester.pumpApp(chart(first));
      await tester.pumpAndSettle();
      expect(values.first, 0);
      expect(values.last, 1);

      values.clear();
      await tester.pumpApp(chart(first));
      await tester.pumpAndSettle();
      expect(values.every((v) => v == 1), isTrue, reason: 'same data: no replay');

      values.clear();
      await tester.pumpApp(chart(Object()));
      await tester.pump();
      expect(values.last, lessThan(1));
      await tester.pumpAndSettle();
      expect(values.last, 1);
    });

    testWidgets('with reduced motion the chart is complete from the first frame', (tester) async {
      final values = <double>[];
      await tester.pumpApp(
        _reduced(
          ChartEntrance(
            data: Object(),
            builder: (context, progress) {
              values.add(progress);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(values, everyElement(1));
    });
  });

  group('FadingBranchContainer', () {
    Widget tabs(int current) => FadingBranchContainer(
      currentIndex: current,
      children: [
        for (var i = 0; i < 3; i++)
          Builder(
            builder: (context) => Text('Pestaña $i ${TickerMode.valuesOf(context).enabled ? 'activa' : 'oculta'}'),
          ),
      ],
    );

    testWidgets('cross-fades to the new tab; hidden tabs keep their state offstage and without tickers', (
      tester,
    ) async {
      await tester.pumpApp(tabs(0));
      expect(find.text('Pestaña 0 activa'), findsOneWidget);
      expect(find.text('Pestaña 1 oculta'), findsNothing, reason: 'offstage');
      expect(find.text('Pestaña 1 oculta', skipOffstage: false), findsOneWidget);

      await tester.pumpApp(tabs(1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Pestaña 1 activa'), findsOneWidget);
      expect(find.text('Pestaña 0 oculta'), findsOneWidget, reason: 'still fading out');
      await tester.pumpAndSettle();
      expect(find.text('Pestaña 0 oculta'), findsNothing);
      expect(find.text('Pestaña 0 oculta', skipOffstage: false), findsOneWidget);
    });

    testWidgets('with reduced motion the switch is instant', (tester) async {
      await tester.pumpApp(_reduced(tabs(0)));
      await tester.pumpApp(_reduced(tabs(2)));
      expect(find.text('Pestaña 2 activa'), findsOneWidget);
      expect(find.text('Pestaña 0 oculta'), findsNothing, reason: 'offstage at once');
    });
  });

  testWidgets('page transition: fade and rise, none with reduced motion', (tester) async {
    const builder = AppPageTransitionsBuilder();
    expect(builder.transitionDuration, lessThanOrEqualTo(const Duration(milliseconds: 350)));
    late Widget animated;
    late Widget still;
    await tester.pumpApp(
      Column(
        children: [
          Builder(
            builder: (context) {
              final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
              animated = builder.buildTransitions(
                route,
                context,
                const AlwaysStoppedAnimation(0.5),
                kAlwaysDismissedAnimation,
                const Text('Página'),
              );
              return const SizedBox();
            },
          ),
          _reduced(
            Builder(
              builder: (context) {
                final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
                still = builder.buildTransitions(
                  route,
                  context,
                  const AlwaysStoppedAnimation(0.5),
                  kAlwaysDismissedAnimation,
                  const Text('Página'),
                );
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
    expect(animated, isA<FadeTransition>());
    expect(still, isA<Text>());
  });
}
