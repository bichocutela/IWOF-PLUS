import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iwof_plus/core/app_controller.dart';
import 'package:iwof_plus/main.dart';

void main() {
  testWidgets(
    'login fits a small screen and validates phone without an API call',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = AppController()..initialized = true;
      await tester.pumpWidget(IwofPlusApp(controller: controller));
      expect(find.text('PLUS'), findsOneWidget);
      await tester.ensureVisible(find.text('Entrar'));
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      expect(find.text('Informe seu telefone com DDD.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
