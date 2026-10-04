import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Opens the [AppDateField] labelled [label] and types [day] in the picker's
/// text mode (no calendar navigation, whatever today is).
Future<void> pickDate(WidgetTester tester, String label, DateTime day) async {
  final field = find.bySemanticsLabel(RegExp('^$label:'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(TextField)),
    DateFormat('dd/MM/yyyy').format(day),
  );
  await tester.pumpAndSettle();
  final buttons = find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(TextButton));
  await tester.tap(buttons.last);
  await tester.pumpAndSettle();
}
