import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iwof_plus/core/work_models.dart';

void main() {
  test('work item tolerates missing optional fields', () {
    final item = WorkItem.fromJson({
      'id': '1',
      'job': {'name': 'Auxiliar'},
      'store': {'name': 'Empresa'},
      'job_store': {'value': 123.45},
      'requestWorker': {'status': 'AGENDADO'}
    });
    expect(item.title, 'Auxiliar');
    expect(item.estimatedValue, 123.45);
    expect(item.paidValue, isNull);
  });
  testWidgets('long text remains scrollable on a narrow viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
          children: [
            for (var i = 0; i < 20; i++)
              Text('Conteúdo longo número $i', key: ValueKey('item_$i')),
          ],
        ),
      ),
    ));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('item_19')), 200);
    expect(find.byKey(const ValueKey('item_19')), findsOneWidget);
  });
}
