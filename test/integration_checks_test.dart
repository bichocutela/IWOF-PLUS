import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iwof_plus/screens/integration_checks.dart';

void main() {
  testWidgets('the integration checklist starts untested and is manually editable',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: IntegrationChecksScreen()),
    );
    expect(find.text('Teste cada área no seu aparelho'), findsOneWidget);
    final initial = tester.widget<ChoiceChip>(find.byType(ChoiceChip).first);
    expect(initial.selected, isTrue);
    await tester.tap(find.text('FUNCIONOU').first);
    await tester.pump();
    final newSelection = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .toList()[1];
    expect(newSelection.selected, isTrue);
  });
}
