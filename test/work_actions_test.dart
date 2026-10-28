import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iwof_plus/services/iwof_api.dart';

void main() {
  test('accept job sends original mutation with explicit request id', () async {
    var calls = 0;
    final api = IwofApi(client: MockClient((request) async {
      calls++;
      expect(request.headers['authorization'], 'Bearer mock-session');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final operation = body['query'] as String;
      expect(operation, contains('mutation AcceptRequest'));
      expect(operation, contains('acceptRequest(request_id:'));
      expect(body['variables'], {
        'request_id': 'request-9', 'worker_id': null,
      });
      return http.Response(jsonEncode({
        'data': {'acceptRequest': true},
      }), 200);
    }));
    await api.acceptJob('mock-session', 'request-9');
    expect(calls, 1);
  });

  test('acceptance is not claimed if server rejects it', () async {
    final api = IwofApi(client: MockClient((request) async {
      return http.Response(jsonEncode({
        'data': {'acceptRequest': false},
      }), 200);
    }));
    await expectLater(
      api.acceptJob('mock-session', 'request-9'),
      throwsFormatException,
    );
  });

  test('cancel uses exact original deleteRequest contract', () async {
    final api = IwofApi(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['query'], contains('mutation DeleteRequest'));
      expect(body['variables'], {'id': 'r-2', 'reason': null});
      return http.Response(jsonEncode({
        'data': {'deleteRequest': true},
      }), 200);
    }));
    await api.cancelWork('mock-session', 'r-2');
  });

  test('cancel failure does not appear as success', () async {
    final api = IwofApi(client: MockClient((request) async {
      return http.Response(jsonEncode({
        'data': {'deleteRequest': false},
      }), 200);
    }));
    await expectLater(
      api.cancelWork('mock-session', 'r-2'),
      throwsFormatException,
    );
  });

  test('empty id does not send any mutation', () async {
    var called = false;
    final api = IwofApi(client: MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    }));
    await expectLater(api.acceptJob('session', '  '), throwsFormatException);
    await expectLater(api.cancelWork('session', ''), throwsFormatException);
    expect(called, false);
  });
}
