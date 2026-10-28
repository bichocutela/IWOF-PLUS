import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models.dart';
import '../core/work_models.dart';

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

  Future<void> sendPasswordResetCode(String email) async {
    const source = r'''
      mutation SendCodeToResetPasswordByPhone(
        $email: String!,
        $channel: PasswordResetChannel
      ) {
        sendCodeToResetPasswordByPhone(email: $email, channel: $channel)
      }
    ''';
    final data = await query(source, variables: {'email': email, 'channel': null});
    final result = data['sendCodeToResetPasswordByPhone'];
    if (result == null || result == false) {
      throw const FormatException('O iWof não confirmou o envio do código.');
    }
  }

  Future<void> resetWorkerPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    const source = r'''
      mutation WorkerResetPassword(
        $check_code: String!,
        $email: String!,
        $newPassword: String!,
        $channel: PasswordResetChannel
      ) {
        workerResetPassword(
          check_code: $check_code,
          email: $email,
          newPassword: $newPassword,
          channel: $channel
        )
      }
    ''';
    final data = await query(source, variables: {
      'check_code': code,
      'email': email,
      'newPassword': newPassword,
      'channel': null,
    });
    final result = data['workerResetPassword'];
    if (result == null || result == false) {
      throw const FormatException('O iWof não confirmou a redefinição.');
    }
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

  /// Original iWof 2.3.14 AcceptRequest mutation. Only call after an
  /// explicit user confirmation and never from refresh/background jobs.
  Future<void> acceptJob(String token, String requestId, {String? workerId}) async {
    if (requestId.trim().isEmpty) {
      throw const FormatException('Vaga sem identificador.');
    }
    const operation = r'''
      mutation AcceptRequest($request_id: ID!, $worker_id: ID) {
        acceptRequest(request_id: $request_id, worker_id: $worker_id)
      }
    ''';
    final response = await query(
      operation,
      token: token,
      variables: {
        'request_id': requestId,
        'worker_id': workerId,
      },
    );
    if (response['acceptRequest'] == null ||
        response['acceptRequest'] == false) {
      throw const FormatException('O iWof não confirmou o agendamento.');
    }
  }

  /// Original iWof 2.3.14 DeleteRequest mutation. Never cancel a service
  /// solely because a user opens its details.
  Future<void> cancelWork(String token, String requestId,
      {String? reason}) async {
    if (requestId.trim().isEmpty) {
      throw const FormatException('Agendamento sem identificador.');
    }
    const operation = r'''
      mutation DeleteRequest($id: ID!, $reason: String) {
        deleteRequest(id: $id, reason: $reason)
      }
    ''';
    final response = await query(
      operation,
      token: token,
      variables: {'id': requestId, 'reason': reason},
    );
    if (response['deleteRequest'] == null ||
        response['deleteRequest'] == false) {
      throw const FormatException('O iWof não confirmou o cancelamento.');
    }
  }

  // Read-only contracts recovered from the original iWof 2.3.14 application.
  // No mutations, automatic scheduling or cancellation are performed.
  Future<WorkCollection> workAgenda(String token) => _workRequests(
    token,
    WorkKind.agenda,
  );

  Future<WorkCollection> workHistory(String token) => _workRequests(
    token,
    WorkKind.history,
  );

  Future<WorkCollection> _workRequests(String token, WorkKind kind) async {
    const agendaQuery = '''
    {
      workerRequests(status: ["AGENDADO", "AGUARDANDO LIBERAR", "EM ANDAMENTO"]) {
        totalResults
        requests {
          id
          is_cancellable
          job { name }
          store { name image company { image } }
          job_store { value percentage }
          requestWorker { status }
          request_workers
          start_at
          finish_at
        }
      }
    }
    ''';
    const historyQuery = '''
    {
      workerRequests(status: ["EM REVISÃO", "FINALIZADO", "CANCELADO"]) {
        totalResults
        requests {
          id
          job { name }
          store { name image company { image } }
          job_store { value percentage }
          requestWorker { paid_value status }
          request_workers
          status
          start_at
          finish_at
        }
      }
    }
    ''';
    final data = await query(
      kind == WorkKind.agenda ? agendaQuery : historyQuery,
      token: token,
    );
    final result = data['workerRequests'];
    if (result is! Map ||
        result['totalResults'] is! num ||
        result['requests'] is! List) {
      throw const FormatException('Consulta de trabalhos incompleta.');
    }
    final total = (result['totalResults'] as num).toInt();
    final requests = result['requests'] as List;
    if (total < 0) {
      throw const FormatException('Total de trabalhos inválido.');
    }
    final items = requests
        .map((e) => WorkItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    items.sort((a, b) {
      if (a.start == null) return b.start == null ? 0 : 1;
      if (b.start == null) return -1;
      return kind == WorkKind.agenda
          ? a.start!.compareTo(b.start!)
          : b.start!.compareTo(a.start!);
    });
    return WorkCollection(total, items);
  }
}
