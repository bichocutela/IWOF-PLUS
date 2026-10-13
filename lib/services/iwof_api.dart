import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models.dart';

class IwofApi {
  IwofApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static final endpoint = Uri.parse(
    'https://59pcbz0e53.execute-api.us-east-1.amazonaws.com/production/graphql',
  );
  static const jobFields =
      '''id job { name } store { name address coordinates image company { image } }
    job_store { value percentage } start_at finish_at''';
  Future<Map<String, dynamic>> query(
    String query, {
    Map<String, dynamic>? variables,
    String? token,
  }) async {
    final response = await _client
        .post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'x-iwof-platform': 'android',
            'x-iwof-app-version': '2.3.14',
            if (token != null) 'authorization': 'Bearer $token',
          },
          body: jsonEncode({'query': query, 'variables': variables ?? {}}),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SessionExpired();
    }
    if (response.statusCode != 200) {
      throw Exception(
        'O serviço de vagas está indisponível (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['errors'] is List && (body['errors'] as List).isNotEmpty) {
      final message = '${body['errors'][0]['message']}';
      if (RegExp(
        r'jwt|unauthorized|unauthenticated|token.*expir',
        caseSensitive: false,
      ).hasMatch(message)) {
        throw const SessionExpired();
      }
      throw Exception(message);
    }
    return body['data'] as Map<String, dynamic>? ?? {};
  }

  Future<String> login(String phone, String password) async {
    final data = await query(
      'query LoginWorker(\$login: String!, \$password: String!) { loginWorker(login: \$login, password: \$password) }',
      variables: {'login': formatPhone(phone), 'password': password},
    );
    final token = data['loginWorker'];
    if (token is! String || token.isEmpty) {
      throw Exception('Não foi possível iniciar a sessão.');
    }
    return token;
  }

  Future<List<String>> cities(String token) async {
    final data = await query('{ citiesOperation { city } }', token: token);
    return (data['citiesOperation'] as List? ?? [])
        .map((e) => '${e['city']}')
        .toSet()
        .toList()
      ..sort();
  }

  Future<JobPage> jobs(String token, String city, int page) async {
    // JSON quoting escapes city text without interpolating raw user input into GraphQL.
    final data = await query(
      '{ workerRequestsNewApp(page: $page, status: "NOVO", address: {city: ${jsonEncode(city)}}) { totalResults requests { $jobFields } } }',
      token: token,
    );
    final result = data['workerRequestsNewApp'] as Map<String, dynamic>? ?? {};
    return JobPage(
      (result['totalResults'] as num?)?.toInt() ?? 0,
      (result['requests'] as List? ?? [])
          .map((e) => Job.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Future<List<Job>> allJobs(String token, String city) async {
    final collected = <String, Job>{};
    for (var page = 1; page <= 250; page++) {
      final result = await jobs(token, city, page);
      final previousCount = collected.length;
      for (final job in result.jobs) {
        collected[job.id] = job;
      }
      if (collected.length >= result.total) return collected.values.toList();
      if (result.jobs.isEmpty || previousCount == collected.length) {
        throw Exception(
          'A consulta ficou incompleta. A verificação será repetida.',
        );
      }
    }
    throw Exception(
      'A consulta excedeu o limite de segurança. Nenhum aviso foi confirmado.',
    );
  }

  Future<Job> detail(String token, String id) async {
    final data = await query(
      '{ request(id: ${jsonEncode(id)}) { $jobFields job_store { description epi look_for value percentage } } }',
      token: token,
    );
    if (data['request'] == null) {
      throw Exception('Essa vaga não está mais disponível.');
    }
    return Job.fromJson({
      'id': id,
      ...Map<String, dynamic>.from(data['request']),
    });
  }
}
