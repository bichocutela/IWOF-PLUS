import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iwof_plus/screens/app_shell.dart';

void main() {
  testWidgets('city picker can reach the last city on a small display',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cities = List.generate(45, (i) => 'Cidade ${i.toString().padLeft(2, '0')}');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => CityPicker(cities: cities),
                ),
                child: const Text('Abrir cidades'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir cidades'));
    await tester.pumpAndSettle();
    expect(find.text('Onde você quer trabalhar?'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Cidade 44'),
      250,
      scrollable: find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ).first,
    );
    expect(find.text('Cidade 44'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
