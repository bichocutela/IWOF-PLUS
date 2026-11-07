import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iwof_plus/core/models.dart';
import 'package:iwof_plus/screens/app_shell.dart';

void main() {
  const channel = MethodChannel('br.com.iwofplus.iwof_plus/share');

  for (final width in [280.0, 420.0]) {
    testWidgets('job card shares via the same native action at width $width',
        (tester) async {
      String? shared;
      var opened = false;
      var accepted = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          expect(call.method, 'shareText');
          shared = (call.arguments as Map<dynamic, dynamic>)['text'] as String;
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final job = Job(
        id: 'job-22',
        title: 'Separador',
        store: 'Loja de teste',
        address: 'Natal - RN',
        start: DateTime(2026, 11, 7, 6),
        finish: DateTime(2026, 11, 7, 12),
        value: 12.35,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: JobCard(
                job: job,
                saved: false,
                onSave: () {},
                onTap: () => opened = true,
                onAccept: () => accepted = true,
              ),
            ),
          ),
        ),
      ));
      final share = width < 315 + 36
          ? find.byTooltip('Compartilhar vaga')
          : find.text('Compartilhar');
      await tester.tap(share);
      await tester.pump();
      expect(shared, job.shareText);
      expect(opened, isFalse);
      expect(accepted, isFalse);
      await tester.tap(find.text('Aceitar vaga'));
      expect(accepted, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
