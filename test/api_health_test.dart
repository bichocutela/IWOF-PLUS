import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iwof_plus/services/api_health.dart';
import 'package:iwof_plus/services/iwof_api.dart';

void main() {
  test('diagnostics are read-only and reports contain no response data',
      () async {
    String token() {
      final claims = base64Url.encode(utf8.encode('{"worker_id":"17"}'));
      return 'header.$claims.signature';
    }

    final seen = <String>[];
    final api = IwofApi(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final query = body['query'] as String;
      expect(query, isNot(contains('mutation')));
      seen.add(query);
      Map<String, dynamic> data;
      if (query.contains('citiesOperation')) {
        data = {'citiesOperation': [{'city': 'Natal'}]};
      } else if (query.contains('workerRequests(')) {
        data = {
          'workerRequests': {
            'totalResults': 0,
            'requests': [],
          },
        };
      } else if (query.contains('list: courses')) {
        data = {'list': {
          'totalResults': 1,
          'nextPage': null,
          'courses': [{'id': '7', 'name': 'Curso Teste'}],
        }};
      } else if (query.contains('courseVideos(')) {
        data = {'courseVideos': {'videos': []}};
      } else if (query.contains('courseQuestions(')) {
        data = {'courseQuestions': {'questions': []}};
      } else if (query.contains('worker(id:')) {
        data = {'worker': {
          'id': '17', 'name': 'Nome confidencial', 'balance': 900,
          'jobs': [
            {'id': '1', 'name': 'Habilitação não confirmada - Caixa'},
          ],
        }};
      } else if (query.contains('extract(')) {
        data = {'extract': [
          {'description': 'Movimentação privada', 'value': 80},
        ]};
      } else if (query.contains('getWorkerRegisterStatus(')) {
        data = {'getWorkerRegisterStatus': {'documents_status': 'OK'}};
      } else if (query.contains('getWorkerSchedulingCompliance(')) {
        data = {'getWorkerSchedulingCompliance': {
          'canAcceptNewSchedules': true, 'missingDocuments': [],
        }};
      } else {
        throw StateError('Query unexpected');
      }
      return http.Response(jsonEncode({'data': data}), 200);
    }));
    final rows = await ApiHealth(api).run(token());
    expect(rows.length, 12);
    expect(rows.where((row) => row.state == 'OK'), hasLength(11));
    expect(rows.where((row) => row.state == 'NÃO CONFIRMADO'), hasLength(1));
    expect(rows.last.title, 'Habilitações individuais');
    expect(seen.length, 11);
    final report = ApiHealth.report(rows);
    expect(report, isNot(contains('Nome confidencial')));
    expect(report, isNot(contains('Movimentação privada')));
    expect(report, isNot(contains('900')));
    expect(report, isNot(contains('header.')));
    expect(report, isNot(contains('Habilitação não confirmada - Caixa')));
  });

  test('opaque session skips profile-related checks safely', () async {
    final api = IwofApi(client: MockClient((_) async =>
        http.Response(jsonEncode({'data': {}}), 200)));
    final rows = await ApiHealth(api).run('opaque-session');
    final privateChecks = rows.where((row) =>
        const [
          'Perfil básico', 'Extrato', 'Cadastro', 'Elegibilidade',
          'Origem de funções (worker.jobs)', 'Habilitações individuais',
        ]
            .contains(row.title));
    expect(privateChecks.length, 6);
    expect(privateChecks.every((row) => row.state == 'NÃO TESTADO'), isTrue);
  });
}
