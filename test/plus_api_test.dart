import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iwof_plus/services/iwof_api.dart';
import 'package:iwof_plus/services/plus_api.dart';

void main() {
  test('worker id only comes from explicit worker session claims', () {
    String token(Map<String, dynamic> payload) {
      final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
      return 'header.$body.signature';
    }

    expect(PlusApi.workerIdFromSession(token({
      'account_type': 'worker',
      'id': 'worker-lowercase',
    })), 'worker-lowercase');
    expect(PlusApi.workerIdFromSession(token({
      'role': 'PROFISSIONAL',
      'id': 'worker-pt',
    })), 'worker-pt');
    expect(PlusApi.workerIdFromSession(token({
      'custom:account_type': 'Professional',
      'custom:id': 'worker-custom',
    })), 'worker-custom');
    expect(PlusApi.workerIdFromSession(token({
      'custom:worker_id': 'worker-explicit',
    })), 'worker-explicit');

    expect(PlusApi.workerIdFromSession(token({'worker_id': '57'})), '57');
    expect(PlusApi.workerIdFromSession(token({'worker': {'id': '89'}})), '89');
    // The original iWof app obtains worker.id from JWT.payload.user.
    expect(PlusApi.workerIdFromSession(token({'user': {'id': 'worker-from-user'}})),
        'worker-from-user');
    expect(PlusApi.workerIdFromSession(token({'id': '66'})), isNull);
    expect(PlusApi.workerIdFromSession('opaque-token'), isNull);
    expect(PlusApi.workerIdFromSession(token({'worker_id': '../../x'})), isNull);
  });

  test('profile requests minimum fields and never password or bank details', () async {
    final plus = PlusApi(IwofApi(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final query = body['query'] as String;
      expect(query, contains('worker(id:'));
      expect(query, isNot(contains('password')));
      expect(query, isNot(contains('pix_key')));
      expect(query, isNot(contains('conta_cpf')));
      expect(query, isNot(contains('mutation')));
      expect(body['variables'], {'id': 'worker-1'});
      return http.Response(jsonEncode({
        'data': {'worker': {
          'id': 'worker-1', 'name': 'Pessoa Teste', 'score': 9.0,
          'balance': 50.25, 'activated': true,
          'courseAttempts': [
            {'approved': true, 'percentage_correction': 90,
             'course': {'name': 'Segurança'}}
          ],
        }}
      }), 200);
    })));
    final profile = await plus.worker('local-mock-token', 'worker-1');
    expect(profile.name, 'Pessoa Teste');
    expect(profile.balance, 50.25);
    expect(profile.attempts.single.approved, true);
  });

  test('extract preserves pending and paid entries separately', () async {
    final plus = PlusApi(IwofApi(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect((body['query'] as String), isNot(contains('mutation')));
      expect(body['variables'], {'worker_id': '12'});
      return http.Response(jsonEncode({'data': {'extract': [
        {'order_id': '1', 'description': 'Crédito', 'value': '80.50',
         'type': 'CREDIT', 'status': 'PENDING', 'date': '2026-10-01'},
        {'order_id': '2', 'description': 'Pagamento', 'value': -30,
         'type': 'DEBIT', 'status': 'DONE', 'date': '2026-10-15'},
      ]}}), 200);
    })));
    final entries = await plus.extract('session', '12');
    expect(entries.first.id, '2');
    expect(entries.last.status, 'PENDING');
    expect(entries.last.value, 80.5);
  });

  test('missing registration data is an error and not treated as complete', () async {
    final plus = PlusApi(IwofApi(client: MockClient((_) async {
      return http.Response(jsonEncode({'data': {
        'getWorkerRegisterStatus': null
      }}), 200);
    })));
    await expectLater(plus.registration('session', '12'), throwsFormatException);
  });

  test('compliance shows missing document list without changing it', () async {
    final plus = PlusApi(IwofApi(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['variables'], {'worker_id': '12'});
      return http.Response(jsonEncode({'data': {
        'getWorkerSchedulingCompliance': {
          'canAcceptNewSchedules': false,
          'missingDocuments': ['RG', 'Comprovante'],
        }
      }}), 200);
    })));
    final result = await plus.compliance('session', '12');
    expect(result.canAccept, false);
    expect(result.missingDocuments, ['RG', 'Comprovante']);
  });

  test('courses support pagination and videos and questions hide answer keys',
      () async {
    final plus = PlusApi(IwofApi(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final query = body['query'] as String;
      expect(query, isNot(contains('mutation')));
      expect(query, isNot(contains('correct_answer')));
      if (query.contains('list: courses')) {
        expect(body['variables'], {'page': 1, 'filter': null, 'per_page': 15});
        expect(query, contains(r'filter: $filter'));
        return http.Response(jsonEncode({'data': {'list': {
          'totalResults': 1, 'nextPage': null,
          'courses': [{'id': '5', 'name': 'Treinamento',
                       'status': 'ATIVO', 'type': 'VIDEO'}]
        }}}), 200);
      }
      if (query.contains('courseVideos(')) {
        return http.Response(jsonEncode({'data': {'courseVideos': {
          'totalResults': 1,
          'videos': [{'id': '11', 'title': 'Aula 1',
                      'video': 'https://example.com/teste'}]
        }}}), 200);
      }
      return http.Response(jsonEncode({'data': {'courseQuestions': {
        'questions': [{
          'id': '2', 'enunciation': 'Questão?',
          'answersArray': [{'position': 1, 'answer': 'A'}]
        }]
      }}}), 200);
    })));
    final courses = await plus.courses('session');
    expect(courses.items.single.name, 'Treinamento');
    expect(courses.nextPage, isNull);
    expect((await plus.videos('session', '5')).single.title, 'Aula 1');
    expect((await plus.questions('session', '5')).single.options, ['A']);
  });
}
