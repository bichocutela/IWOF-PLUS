import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iwof_plus/core/models.dart';
import 'package:iwof_plus/services/iwof_api.dart';
import 'package:iwof_plus/services/location_service.dart';

void main() {
  test('job image falls back to the company when the store image is blank', () {
    final job = Job.fromJson({
      'id': '1', 'store': {'name': 'Loja', 'image': ' ',
        'company': {'image': 'https://example.test/logo.png'}},
    });
    expect(job.image, 'https://example.test/logo.png');
    expect(Job.fromJson({'id': '2', 'store': {'image': ''}}).image, isNull);
  });

  test('share text contains the actual job details and official link', () {
    final job = Job(
      id: '593692', title: 'Separador', store: 'Mixx Atacado - Lagoa Nova',
      address: '', start: DateTime(2026, 10, 29, 8), finish: DateTime(2026, 10, 29, 14),
      value: 12.35, percentage: 11.5,
    );
    final text = job.shareText;
    expect(text, contains('Vaga IWOF - Separador'));
    expect(text, contains('R\$ 65,58'));
    expect(text, contains('29 de outubro de 2026'));
    expect(text, contains('08:00 às 14:00 (6h)'));
    expect(text, contains('Quinta-feira'));
    expect(text, contains('https://iwof.com.br/job/593692'));
  });

  test('flames follow plus signs in the original job name', () {
    Job makeJob(String title) => Job(
      id: '1', title: title, store: 'Loja', address: '',
      start: null, finish: null,
    );
    expect(makeJob('Repositor').flameCount, 0);
    expect(makeJob('Repositor +').flameCount, 1);
    expect(makeJob('Repositor ++').flameCount, 2);
  });

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
