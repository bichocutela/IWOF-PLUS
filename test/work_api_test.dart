import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iwof_plus/core/models.dart';
import 'package:iwof_plus/core/work_models.dart';
import 'package:iwof_plus/services/iwof_api.dart';

void main() {
  test('agenda reads original statuses without mutation', () async {
    final api = IwofApi(
      client: MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final query = payload['query'] as String;
        expect(query, contains('"AGENDADO", "AGUARDANDO LIBERAR", "EM ANDAMENTO"'));
        expect(query, contains('is_cancellable'));
        expect(query, isNot(contains('mutation')));
        expect(request.headers['authorization'], 'Bearer private-session');
        return http.Response(
          jsonEncode({
            'data': {
              'workerRequests': {
                'totalResults': 1,
                'requests': [
                  {
                    'id': '42',
                    'job': {'name': 'Reposição'},
                    'store': {'name': 'Empresa A'},
                    'job_store': {'value': 120},
                    'requestWorker': {'status': 'AGENDADO'},
                    'is_cancellable': true,
                    'start_at': '2026-11-02T09:00:00Z',
                    'finish_at': '2026-11-02T17:00:00Z',
                  },
                ],
              },
            },
          }),
          200,
        );
      }),
    );
    final agenda = await api.workAgenda('private-session');
    expect(agenda.total, 1);
    expect(agenda.items.single.id, '42');
    expect(agenda.items.single.isCancellable, isTrue);
    expect(agenda.items.single.statusLabel, 'Agendado');
    expect(agenda.items.single.paidValue, isNull);
  });

  test('history keeps paid value separate from expected value', () async {
    final api = IwofApi(
      client: MockClient((request) async {
        final query = (jsonDecode(request.body) as Map)['query'] as String;
        expect(query, contains('"EM REVISÃO", "FINALIZADO", "CANCELADO"'));
        expect(query, contains('paid_value'));
        return http.Response(
          jsonEncode({
            'data': {
              'workerRequests': {
                'totalResults': 2,
                'requests': [
                  {
                    'id': '9',
                    'job': {'name': 'Auxiliar'},
                    'store': {'name': 'Empresa B'},
                    'job_store': {'value': 100.0},
                    'requestWorker': {'status': 'FINALIZADO', 'paid_value': 85},
                    'start_at': '2026-10-20T10:00:00Z',
                  },
                  {
                    'id': '8',
                    'job': {'name': 'Apoio'},
                    'store': {'name': 'Empresa C'},
                    'status': 'CANCELADO',
                    'job_store': {'value': '90'},
                  },
                ],
              },
            },
          }),
          200,
        );
      }),
    );
    final history = await api.workHistory('private-session');
    expect(history.total, 2);
    expect(history.items.first.estimatedValue, 100);
    expect(history.items.first.paidValue, 85);
    expect(history.items.last.paidValue, isNull);
    expect(history.items.last.statusLabel, 'Cancelado');
    expect(WorkItem.money(null), 'Não informado');
  });

  test('null or malformed API data is not treated as empty', () async {
    final api = IwofApi(
      client: MockClient((_) async =>
          http.Response(jsonEncode({'data': {'workerRequests': null}}), 200)),
    );
    await expectLater(api.workAgenda('session'), throwsFormatException);
  });

  test('expired session is preserved as typed error', () async {
    final api = IwofApi(
      client: MockClient((_) async => http.Response('unauthorized', 401)),
    );
    await expectLater(api.workHistory('session'), throwsA(isA<SessionExpired>()));
  });
}
