import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iwof_plus/core/models.dart';
import 'package:iwof_plus/services/iwof_api.dart';
import 'package:iwof_plus/services/location_service.dart';

void main() {
  test(
    'login reproduces the original formatted phone and accepts country code',
    () {
      expect(formatPhone('11912345678'), '(11) 91234-5678');
      expect(formatPhone('+55 (11) 91234-5678'), '(11) 91234-5678');
      expect(() => formatPhone('123'), throwsFormatException);
    },
  );
  test(
    'GPS drift does not change region until confirmed after two minutes',
    () {
      final guard = RegionGuard();
      final now = DateTime(2026, 10, 13);
      expect(guard.accept('Natal', 'Parnamirim', 2000, now), isNull);
      expect(guard.accept('Natal', 'Parnamirim', 20, now), isNull);
      expect(
        guard.accept(
          'Natal',
          'Parnamirim',
          20,
          now.add(const Duration(minutes: 1)),
        ),
        isNull,
      );
      expect(
        guard.accept(
          'Natal',
          'Parnamirim',
          20,
          now.add(const Duration(minutes: 2)),
        ),
        'Parnamirim',
      );
      expect(normalizeCity(' João Pessoa '), 'joao pessoa');
    },
  );
  test(
    'complete monitor traverses pages and keeps stable unique IDs',
    () async {
      var calls = 0;
      final api = IwofApi(
        client: MockClient((request) async {
          calls++;
          expect(request.headers['authorization'], 'Bearer test-session');
          final query = jsonDecode(request.body)['query'] as String;
          expect(query, contains('address: {city: "Natal"}'));
          return http.Response(
            jsonEncode({
              'data': {
                'workerRequestsNewApp': {
                  'totalResults': 3,
                  'requests': calls == 1
                      ? [
                          {'id': '1'},
                          {'id': '2'},
                        ]
                      : [
                          {'id': '3'},
                        ],
                },
              },
            }),
            200,
          );
        }),
      );
      expect((await api.allJobs('test-session', 'Natal')).map((e) => e.id), [
        '1',
        '2',
        '3',
      ]);
      expect(calls, 2);
    },
  );
  test(
    'incomplete pagination must fail instead of committing partial results',
    () async {
      final api = IwofApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'workerRequestsNewApp': {'totalResults': 9, 'requests': []},
              },
            }),
            200,
          ),
        ),
      );
      await expectLater(api.allJobs('test', 'Natal'), throwsException);
    },
  );
  test(
    'expired session is reported without exposing response contents',
    () async {
      final api = IwofApi(
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );
      await expectLater(
        api.jobs('test', 'Natal', 1),
        throwsA(isA<SessionExpired>()),
      );
    },
  );
}
