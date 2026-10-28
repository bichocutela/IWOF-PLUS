import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iwof_plus/services/iwof_api.dart';
import 'package:iwof_plus/services/plus_api.dart';

void main() {
  test('official assessment calls the original CorrectWorkerTest mutation',
      () async {
    final api = PlusApi(IwofApi(client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['query'], contains('mutation CorrectWorkerTest'));
      expect(body['query'], contains(r'correctWorkerTest(course_id: $course_id'));
      expect(body['variables'], {
        'course_id': 'course-1',
        'answers': [
          {'question_id': 'q1', 'answer': 2},
        ],
      });
      return http.Response(jsonEncode({
        'data': {'correctWorkerTest': {'approved': true}}
      }), 200);
    })));
    expect(await api.submitAssessment('session', 'course-1', [
      {'question_id': 'q1', 'answer': 2},
    ]), isTrue);
  });

  test('negative result is a confirmed unsuccessful exam', () async {
    final api = PlusApi(IwofApi(client: MockClient((request) async =>
        http.Response(jsonEncode({
          'data': {'correctWorkerTest': {'approved': false}},
        }), 200))));
    expect(await api.submitAssessment('session', 'c', [
      {'question_id': 'q', 'answer': 1},
    ]), isFalse);
  });

  test('missing backend confirmation is not treated as approved', () async {
    final api = PlusApi(IwofApi(client: MockClient((request) async =>
        http.Response(jsonEncode({'data': {
          'correctWorkerTest': null,
        }}), 200))));
    await expectLater(api.submitAssessment('session', 'c', [
      {'question_id': 'q', 'answer': 1},
    ]), throwsFormatException);
  });
}
