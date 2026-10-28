import 'dart:convert';
import '../core/models.dart';
import 'package:http/http.dart' as http;
import 'iwof_api.dart';

/// iWof API reads and user-confirmed account operations recovered from the original app.
class PlusApi {
  const PlusApi(this.api);
  final IwofApi api;

  /// ID hint from a JWT; server-side authorization is always mandatory.
  /// Opaque tokens and ambiguous claims are deliberately not guessed.
  static String? workerIdFromSession(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is! Map) return null;

      final worker = claims['worker'];
      final professional = claims['professional'] ?? claims['profissional'];
      final user = claims['user'];
      final workerTypes = {
        'worker',
        'professional',
        'profissional',
        'iwofworker',
        'workerprofessional',
        'professionalworker',
      };
      bool isWorkerType(dynamic value) {
        if (value is List) return value.any(isWorkerType);
        final normalized = value
            ?.toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z]'), '');
        return workerTypes.contains(normalized);
      }

      final typeClaims = [
        claims['role'],
        claims['account_type'],
        claims['accountType'],
        claims['user_type'],
        claims['userType'],
        for (final entry in claims.entries)
          if (entry.key.toString().toLowerCase().endsWith(':role') ||
              entry.key.toString().toLowerCase().endsWith(':account_type') ||
              entry.key.toString().toLowerCase().endsWith(':accounttype'))
            entry.value,
        if (worker is Map) worker['account_type'],
        if (worker is Map) worker['accountType'],
        if (professional is Map) professional['account_type'],
        if (user is Map) user['account_type'],
      ];
      final isWorkerSession = typeClaims.any(isWorkerType);

      final candidates = <dynamic>[
        claims['worker_id'],
        claims['workerId'],
        claims['custom:worker_id'],
        claims['custom:workerId'],
        if (worker is String) worker,
        if (worker is Map) worker['id'],
        if (worker is Map) worker['worker_id'],
        if (professional is Map) professional['id'],
        if (professional is Map) professional['worker_id'],
        if (isWorkerSession) claims['id'],
        if (isWorkerSession) claims['custom:id'],
        // The official iWof app decodes JWT.payload.user and uses user.id
        // as the authenticated worker ID, without requiring a role claim.
        if (user is Map) user['id'],
        if (user is Map) user['worker_id'],
      ];
      for (final candidate in candidates) {
        final value = candidate?.toString() ?? '';
        if (RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) return value;
      }
    } catch (_) {
      // Do not log or persist decoded authentication claims.
    }
    return null;
  }

  static Map<String, dynamic> object(dynamic v) {
    if (v is! Map) throw const FormatException('Resposta inválida do serviço.');
    return Map<String, dynamic>.from(v);
  }

  static List<Map<String, dynamic>> records(dynamic v) {
    if (v is! List) throw const FormatException('Lista indisponível.');
    return v.map((item) => object(item)).toList();
  }

  static double? amount(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  static DateTime? date(dynamic v) => DateTime.tryParse(v?.toString() ?? '');

  Future<PlusWorker> worker(String token, String id) async {
    const source = r'''
      query WorkerPlus($id: ID!) {
        worker(id: $id) {
          id name score balance activated blockedByFault
          email login image birthdate gender zipcode address neighborhood complement
          city state { name } civilStatus { name } schooling { name }
          professional_experiences { position }
          cpf rg
          courseAttempts {
            approved percentage_correction updated_at
            course { id name type }
          }
        }
      }
    ''';
    final data = await api.query(source,
        token: token, variables: {'id': id});
    return PlusWorker.fromJson(object(data['worker']));
  }

  /// Loads bank details through a separate, explicitly scoped account query.
  /// These fields are kept out of the general worker profile selection.
  Future<PlusWorker> workerWithBankInformation(String token, String id) async {
    final profile = await worker(token, id);
    const source = r'''
      query WorkerBankPlus($id: ID!) {
        worker(id: $id) {
          pix_key pix_type banco conta_tipo conta conta_digito_verificador
          conta_nome_responsavel conta_cpf_responsavel
        }
      }
    ''';
    final data = await api.query(source, token: token, variables: {'id': id});
    final bank = object(data['worker']);
    return profile.withBankInformation(bank);
  }

  /// Fetches the qualifications attached to the authenticated worker.
  Future<List<String>> qualifications(String token, String id) async {
    const source = r'''
      query WorkerQualifications($id: ID!) {
        worker(id: $id) { id jobs { id name } }
      }
    ''';
    final data = await api.query(source, token: token, variables: {'id': id});
    final worker = object(data['worker']);
    final jobs = worker['jobs'];
    return records(jobs)
        .map((job) => (job['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> withdrawals(String token, String id) async {
    const source = r'''
      query Withdraws($id: ID!) {
        worker(id: $id) {
          withdraw { id amount type status created_at updated_at }
        }
      }
    ''';
    final data = await api.query(source, token: token, variables: {'id': id});
    return records(object(data['worker'])['withdraw']);
  }

  Future<Map<String, dynamic>> supportTicket(String token, String ticketId) async {
    const source = r'''
      query SupportTicket($ticket_id: ID!) {
        result: ticket(ticket_id: $ticket_id) {
          id ticket_id status subject
          comments { author plain_body created_at attachments { url name } }
        }
      }
    ''';
    final data = await api.query(source, token: token, variables: {'ticket_id': ticketId});
    return object(data['result']);
  }

  Future<void> replyToTicket(String token, String ticketId, String message) async {
    const source = r'''
      mutation ReplyToTicket($ticket_id: ID!, $message: String!, $image: Upload) {
        result: updateTicket(ticket_id: $ticket_id, msg: $message, image: $image)
      }
    ''';
    final data = await api.query(source, token: token,
      variables: {'ticket_id': ticketId, 'message': message, 'image': null});
    if (data['result'] == null || data['result'] == false) {
      throw const FormatException('O iWof não confirmou a resposta.');
    }
  }

  Future<List<Map<String, dynamic>>> supportTickets(String token, String id) async {
    const source = r'''
      query WorkerSupportTickets($page: Int, $worker_id: ID) {
        result: tickets(page: $page, worker_id: $worker_id) {
          currentPage nextPage
          nodes: tickets { id ticket_id status subject created_at updated_at }
        }
      }
    ''';
    final result = <Map<String, dynamic>>[];
    var page = 1;
    final visited = <int>{};
    while (visited.add(page)) {
      final data = await api.query(source, token: token,
          variables: {'page': page, 'worker_id': id});
      final list = object(data['result']);
      result.addAll(records(list['nodes']));
      final next = list['nextPage'];
      if (next == null) break;
      final nextPage = int.tryParse(next.toString());
      if (nextPage == null || nextPage <= page) {
        throw const FormatException('Paginação de chamados inválida.');
      }
      page = nextPage;
      if (visited.length >= 100) throw const FormatException('Limite de páginas excedido.');
    }
    return result;
  }

  Future<List<PlusEntry>> extract(String token, String id) async {
    const source = r'''
      query getExtract($worker_id: ID!) {
        extract(worker_id: $worker_id) {
          order_id description value type date status
        }
      }
    ''';
    final data = await api.query(source,
        token: token, variables: {'worker_id': id});
    final entries = records(data['extract']).map(PlusEntry.fromJson).toList();
    entries.sort((a, b) {
      if (a.date == null) return b.date == null ? 0 : 1;
      if (b.date == null) return -1;
      return b.date!.compareTo(a.date!);
    });
    return entries;
  }

  Future<PlusRegistration> registration(String token, String id) async {
    const source = r'''
      query getWorkerRegisterStatus($worker_id: ID!) {
        getWorkerRegisterStatus(worker_id: $worker_id) {
          regular_status complementary_data_status bank_data_status
          profile_picture_status documents_status professional_profile_status
        }
      }
    ''';
    final data = await api.query(source,
        token: token, variables: {'worker_id': id});
    return PlusRegistration.fromJson(
        object(data['getWorkerRegisterStatus']));
  }

  Future<PlusCompliance> compliance(String token, String id) async {
    const source = r'''
      query getWorkerSchedulingCompliance($worker_id: ID!) {
        getWorkerSchedulingCompliance(worker_id: $worker_id) {
          canAcceptNewSchedules missingDocuments
        }
      }
    ''';
    final data = await api.query(source,
        token: token, variables: {'worker_id': id});
    return PlusCompliance.fromJson(
        object(data['getWorkerSchedulingCompliance']));
  }

  /// Updates the signed-in worker's email and starts verification.
  /// The caller must obtain explicit user confirmation before calling.
  /// Sends one image using the GraphQL multipart request contract used by iWof.
  /// Image bytes are transient and are not persisted by IWOF PLUS.
  Future<String> uploadImage(
    String token, {
    required String filename,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) throw const FormatException('Arquivo de imagem vazio.');
    final request = http.MultipartRequest('POST', IwofApi.endpoint)
      ..headers.addAll({
        'x-iwof-platform': 'android',
        'x-iwof-app-version': '2.3.14',
        'authorization': 'Bearer ' + token,
      })
      ..fields['operations'] = jsonEncode({
        'query': r'mutation uploadFile($file: Upload!) { upload: uploadFile(file: $file) }',
        'variables': {'file': null},
      })
      ..fields['map'] = jsonEncode({'0': ['variables.file']})
      ..files.add(http.MultipartFile.fromBytes('0', bytes, filename: filename));
    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SessionExpired();
    }
    if (response.statusCode != 200) {
      throw FormatException('O envio da imagem foi recusado (' +
          response.statusCode.toString() + ').');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['errors'] is List && (body['errors'] as List).isNotEmpty) {
      throw const FormatException('O iWof não aceitou o arquivo enviado.');
    }
    final data = body['data'] as Map<String, dynamic>? ?? {};
    final uploaded = data['upload'];
    if (uploaded is! String || uploaded.trim().isEmpty) {
      throw const FormatException('O iWof não retornou o endereço do arquivo.');
    }
    return uploaded;
  }

  Future<void> setWorkerProfilePhoto(String token, String profileImage) async {
    const source = r'''
      mutation SetWorkerProfilePhoto($profileImage: String!) {
        setWorkerProfilePhoto(profileImage: $profileImage) { profileImage }
      }
    ''';
    final data = await api.query(source, token: token,
      variables: {'profileImage': profileImage});
    object(data['setWorkerProfilePhoto']);
  }

  Future<void> setWorkerRgImages(
    String token, {
    required String frontImage,
    required String backImage,
  }) async {
    const source = r'''
      mutation SetWorkerRGImages(
        $rg_front_image: String!,
        $rg_back_image: String!
      ) {
        setWorkerRGImages(
          rg_front_image: $rg_front_image,
          rg_back_image: $rg_back_image
        ) { rg_back_image rg_front_image }
      }
    ''';
    final data = await api.query(source, token: token, variables: {
      'rg_front_image': frontImage,
      'rg_back_image': backImage,
    });
    object(data['setWorkerRGImages']);
  }

  /// Updates only the supplied fields on the authenticated worker profile.
  /// The caller must show the values and obtain explicit confirmation.
  Future<void> updateWorkerProfile(
    String token,
    String workerId, {
    required String rg,
    required String gender,
    required String zipcode,
    required String address,
    required String complement,
    required String neighborhood,
    required String city,
  }) async {
    const source = r'''
      mutation UpdateWorker($id: ID!, $input: UpdateWorkerInput) {
        updateWorker(id: $id, input: $input) {
          id rg gender zipcode address complement neighborhood city
        }
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {
        'id': workerId,
        'input': {
          'rg': rg,
          'gender': gender,
          'zipcode': zipcode,
          'address': address,
          'complement': complement,
          'neighborhood': neighborhood,
          'city': city,
        },
      },
    );
    object(data['updateWorker']);
  }

  /// Requests a withdrawal from the authenticated worker's account.
  /// The original APK declares type optional; the API may apply its default.
  Future<void> requestWithdrawal(String token, double amount) async {
    if (!amount.isFinite || amount <= 0) {
      throw const FormatException('Informe um valor válido para o saque.');
    }
    const source = r'''
      mutation RequestWithdraw($amount: Float!, $type: String) {
        requestWithdraw(amount: $amount, type: $type)
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {'amount': amount, 'type': null},
    );
    final result = data['requestWithdraw'];
    if (result == null || result == false) {
      throw const FormatException('O iWof não confirmou a solicitação.');
    }
  }

  /// Replaces the authenticated worker's bank details.
  /// The UI must show the submitted values and obtain explicit confirmation.
  Future<void> saveBankInformation(
    String token, {
    required String pixKey,
    required String bank,
    required String account,
    required String accountCheckDigit,
    required String accountType,
    required String accountHolder,
    required String accountHolderCpf,
  }) async {
    const source = r'''
      mutation CreateWorkerBankInformation(
        $pix_key: String,
        $banco: String!,
        $conta: String!,
        $conta_digito_verificador: String!,
        $conta_tipo: String!,
        $conta_nome_responsavel: String!,
        $conta_cpf_responsavel: String!
      ) {
        createWorkerBankInformation(
          pix_key: $pix_key,
          banco: $banco,
          conta: $conta,
          conta_digito_verificador: $conta_digito_verificador,
          conta_tipo: $conta_tipo,
          conta_nome_responsavel: $conta_nome_responsavel,
          conta_cpf_responsavel: $conta_cpf_responsavel
        ) {
          id pix_type pix_key banco conta conta_digito_verificador
          conta_tipo conta_nome_responsavel conta_cpf_responsavel
        }
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {
        'pix_key': pixKey,
        'banco': bank,
        'conta': account,
        'conta_digito_verificador': accountCheckDigit,
        'conta_tipo': accountType,
        'conta_nome_responsavel': accountHolder,
        'conta_cpf_responsavel': accountHolderCpf,
      },
    );
    object(data['createWorkerBankInformation']);
  }

  Future<void> updateWorkerEmail(
    String token,
    String workerId,
    String email,
  ) async {
    const source = r'''
      mutation UpdateWorkerEmail($id: ID!, $email: String!) {
        updateWorker(id: $id, input: { email: $email }) {
          name email
        }
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {'id': workerId, 'email': email},
    );
    object(data['updateWorker']);
  }

  Future<void> sendEmailVerification(String token, String email) async {
    const source = r'''
      mutation SendVerification($email: String!) {
        sendVerification(email: $email)
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {'email': email},
    );
    final result = data['sendVerification'];
    if (result == null || result == false) {
      throw const FormatException('O iWof não confirmou o envio do código.');
    }
  }

  Future<void> verifyWorkerEmail(
    String token,
    String workerId,
    String email,
    String code,
  ) async {
    const source = r'''
      mutation VerifyEmail($id: ID!, $email: String!, $code: String!) {
        verifyEmail(id: $id, email: $email, code: $code)
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {'id': workerId, 'email': email, 'code': code},
    );
    final result = data['verifyEmail'];
    if (result == null || result == false) {
      throw const FormatException('O iWof não confirmou a validação do e-mail.');
    }
  }

  /// Creates the same short-lived, authenticated web handoff used by iWof.
  /// Only the original profile and courses pages are exposed here.
  Future<Uri> signupHandoffUrl(String token, {String? page}) async {
    if (page != null && !const {'perfil', 'cursos'}.contains(page)) {
      throw const FormatException('Página oficial não permitida.');
    }
    const source = r'''
      mutation CreateSignupHandoff($page: String) {
        createSignupHandoff(page: $page) { code expires_at }
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {'page': page},
    );
    final handoff = object(data['createSignupHandoff']);
    final code = '${handoff['code'] ?? ''}'.trim();
    if (code.isEmpty) {
      throw const FormatException('O iWof não gerou o acesso temporário.');
    }
    final expiresAt = date(handoff['expires_at']);
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
      throw const FormatException('O acesso temporário do iWof expirou.');
    }
    final pageQuery = page == null ? '' : '?page=${Uri.encodeQueryComponent(page)}';
    return Uri.parse(
      'https://signup.iwof.com.br/$pageQuery#hs=${Uri.encodeComponent(code)}',
    );
  }

  /// Permanently deletes only the authenticated worker requested by ID.
  /// The UI must require explicit, typed confirmation before calling.
  Future<void> deleteWorkerApp(String token, String workerId) async {
    const source = r'''
      mutation DeleteWorkerApp($id: ID!) {
        deleteWorkerApp(id: $id)
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {'id': workerId},
    );
    final result = data['deleteWorkerApp'];
    if (result == null || result == false) {
      throw const FormatException('O iWof não confirmou a exclusão da conta.');
    }
  }

  /// Adds an experience to the authenticated worker's profile.
  /// Only call after the user explicitly confirms submission.
  Future<void> addProfessionalExperience(
    String token, {
    required String position,
    required String companyName,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    const source = r'''
      mutation CreateWorkerProfessionalExperience(
        $position: String!,
        $company_name: String!,
        $start_date: Date!,
        $end_date: Date
      ) {
        createWorkerProfessionalExperience(
          position: $position,
          company_name: $company_name,
          start_date: $start_date,
          end_date: $end_date
        ) {
          id position company_name
        }
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {
        'position': position,
        'company_name': companyName,
        'start_date': _dateVariable(startDate),
        'end_date': endDate == null ? null : _dateVariable(endDate),
      },
    );
    object(data['createWorkerProfessionalExperience']);
  }

  static String _dateVariable(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<PlusCoursePage> courses(String token, {int page = 1}) async {
    const source = r'''
      query CoursesPlus($page: Int, $filter: CourseFilter, $per_page: Int) {
        list: courses(page: $page, filter: $filter, per_page: $per_page) {
          firstPage lastPage currentPage nextPage prevPage totalResults
          courses { id name status percentage_to_pass time_to_retest type }
        }
      }
    ''';
    final data = await api.query(source,
        token: token, variables: {'page': page, 'filter': null, 'per_page': 15});
    return PlusCoursePage.fromJson(object(data['list']));
  }

  Future<List<PlusVideo>> videos(String token, String id) async {
    const source = r'''
      query getCourseVideos($course_id: ID!) {
        courseVideos(course_id: $course_id) {
          totalResults videos { id video title course { id name } }
        }
      }
    ''';
    final data = await api.query(source,
        token: token, variables: {'course_id': id});
    return records(object(data['courseVideos'])['videos'])
        .map(PlusVideo.fromJson).toList();
  }

  /// Sends the assessment to the original iWof backend.
  /// IMPORTANT: CourseWorkerAnswer input field names must be verified
  /// against the live GraphQL schema before considering it production-ready.
  Future<bool> submitAssessment(
    String token,
    String courseId,
    List<Map<String, dynamic>> answers,
  ) async {
    if (courseId.isEmpty || answers.isEmpty) {
      throw const FormatException('Avaliação incompleta.');
    }
    const source = r'''
      mutation CorrectWorkerTest(
        $course_id: ID!,
        $answers: [CourseWorkerAnswer!]
      ) {
        correctWorkerTest(course_id: $course_id, answers: $answers) {
          approved
        }
      }
    ''';
    final data = await api.query(
      source,
      token: token,
      variables: {'course_id': courseId, 'answers': answers},
    );
    final result = object(data['correctWorkerTest']);
    if (result['approved'] is! bool) {
      throw const FormatException('Resultado não confirmado pelo iWof.');
    }
    return result['approved'] as bool;
  }

  /// Fetch the original answer key only when the user taps the pink plus.
  /// The results are not cached or used to submit an assessment.
  Future<List<PlusAnswerKey>> answerKey(String token, String id) async {
    const source = r'''
      query getCourseQuestions($course_id: ID!) {
        courseQuestions(course_id: $course_id) {
          questions {
            id enunciation correct_answer
            answersArray { position answer }
          }
        }
      }
    ''';
    final data = await api.query(source,
        token: token, variables: {'course_id': id});
    return records(object(data['courseQuestions'])['questions'])
        .map(PlusAnswerKey.fromJson)
        .toList();
  }

  /// No answer key, no score mutation. Preview only.
  Future<List<PlusQuestion>> questions(String token, String id) async {
    const source = r'''
      query getCourseQuestions($course_id: ID!) {
        courseQuestions(course_id: $course_id) {
          questions { id enunciation answersArray { position answer } }
        }
      }
    ''';
    final data = await api.query(source,
        token: token, variables: {'course_id': id});
    return records(object(data['courseQuestions'])['questions'])
        .map(PlusQuestion.fromJson).toList();
  }
}

class PlusWorker {
  const PlusWorker(this.id, this.name, this.score, this.balance,
      this.activated, this.blocked, this.attempts, {
        this.email = '',
        this.phone = '',
        this.image = '',
        this.birthdate = '',
        this.gender = '',
        this.address = '',
        this.neighborhood = '',
        this.complement = '',
        this.city = '',
        this.state = '',
        this.zipcode = '',
        this.civilStatus = '',
        this.schooling = '',
        this.experiences = const [],
        this.cpf = '',
        this.rg = '',
        this.pixKey = '',
        this.pixType = '',
        this.bank = '',
        this.accountType = '',
        this.account = '',
        this.accountCheckDigit = '',
        this.accountHolder = '',
        this.accountHolderCpf = '',
      });
  final String id, name;
  final double? score, balance;
  final bool? activated, blocked;
  final List<PlusAttempt> attempts;
  final String email, phone, image, birthdate, gender, address;
  final String neighborhood, complement, city, state, zipcode;
  final String civilStatus, schooling;
  final List<String> experiences;
  final String cpf, rg, pixKey, pixType, bank;
  final String accountType, account, accountCheckDigit;
  final String accountHolder, accountHolderCpf;

  PlusWorker withBankInformation(Map<String, dynamic> j) => PlusWorker(
    id, name, score, balance, activated, blocked, attempts,
    email: email, phone: phone, image: image, birthdate: birthdate,
    gender: gender, address: address, neighborhood: neighborhood,
    complement: complement, city: city, state: state, zipcode: zipcode,
    civilStatus: civilStatus, schooling: schooling, experiences: experiences,
    cpf: cpf, rg: rg, pixKey: '${j['pix_key'] ?? ''}',
    pixType: '${j['pix_type'] ?? ''}', bank: '${j['banco'] ?? ''}',
    accountType: '${j['conta_tipo'] ?? ''}', account: '${j['conta'] ?? ''}',
    accountCheckDigit: '${j['conta_digito_verificador'] ?? ''}',
    accountHolder: '${j['conta_nome_responsavel'] ?? ''}',
    accountHolderCpf: '${j['conta_cpf_responsavel'] ?? ''}',
  );

  factory PlusWorker.fromJson(Map<String, dynamic> j) {
    final state = j['state'] is Map ? PlusApi.object(j['state']) : const <String, dynamic>{};
    final civil = j['civilStatus'] is Map ? PlusApi.object(j['civilStatus']) : const <String, dynamic>{};
    final school = j['schooling'] is Map ? PlusApi.object(j['schooling']) : const <String, dynamic>{};
    final rawExperiences = j['professional_experiences'];
    return PlusWorker(
      '${j['id'] ?? ''}',
      '${j['name'] ?? 'Profissional'}',
      PlusApi.amount(j['score']), PlusApi.amount(j['balance']),
      j['activated'] is bool ? j['activated'] as bool : null,
      j['blockedByFault'] is bool ? j['blockedByFault'] as bool : null,
      j['courseAttempts'] is List
          ? PlusApi.records(j['courseAttempts'])
              .map(PlusAttempt.fromJson).toList() : [],
      email: '${j['email'] ?? ''}',
      phone: '${j['login'] ?? ''}',
      image: '${j['image'] ?? ''}',
      birthdate: '${j['birthdate'] ?? ''}',
      gender: '${j['gender'] ?? ''}',
      address: '${j['address'] ?? ''}',
      neighborhood: '${j['neighborhood'] ?? ''}',
      complement: '${j['complement'] ?? ''}',
      city: '${j['city'] ?? ''}',
      state: '${state['name'] ?? ''}',
      zipcode: '${j['zipcode'] ?? ''}',
      civilStatus: '${civil['name'] ?? ''}',
      schooling: '${school['name'] ?? ''}',
      experiences: rawExperiences is List
          ? rawExperiences.whereType<Map>()
              .map((item) => '${item['position'] ?? ''}')
              .where((item) => item.trim().isNotEmpty).toList()
          : const [],
      cpf: '${j['cpf'] ?? ''}',
      rg: '${j['rg'] ?? ''}',
      pixKey: '${j['pix_key'] ?? ''}',
      pixType: '${j['pix_type'] ?? ''}',
      bank: '${j['banco'] ?? ''}',
      accountType: '${j['conta_tipo'] ?? ''}',
      account: '${j['conta'] ?? ''}',
      accountCheckDigit: '${j['conta_digito_verificador'] ?? ''}',
      accountHolder: '${j['conta_nome_responsavel'] ?? ''}',
      accountHolderCpf: '${j['conta_cpf_responsavel'] ?? ''}',
    );
  }
}

class PlusAttempt {
  const PlusAttempt(
    this.courseId,
    this.name,
    this.approved,
    this.percentage,
    this.date,
  );
  final String courseId, name;
  final bool? approved;
  final double? percentage;
  final DateTime? date;

  factory PlusAttempt.fromJson(Map<String, dynamic> j) {
    final course = j['course'] is Map
        ? PlusApi.object(j['course'])
        : <String, dynamic>{};
    return PlusAttempt(
      '${course['id'] ?? ''}',
      '${course['name'] ?? 'Avaliação'}',
      j['approved'] is bool ? j['approved'] as bool : null,
      PlusApi.amount(j['percentage_correction']),
      PlusApi.date(j['updated_at']),
    );
  }

  /// Only the exact course is eligible; names can be duplicated or renamed.
  /// A record without a server timestamp cannot confirm a new submission.
  static PlusAttempt? confirmedForCourse(
    List<PlusAttempt> attempts,
    String courseId,
    DateTime submittedAt,
  ) {
    final matches = attempts.where((attempt) =>
        attempt.courseId == courseId &&
        attempt.date != null &&
        !attempt.date!.isBefore(
          submittedAt.subtract(const Duration(minutes: 2)),
        )).toList()
      ..sort((a, b) => b.date!.compareTo(a.date!));
    return matches.isEmpty ? null : matches.first;
  }
}

class PlusEntry {
  const PlusEntry(this.id, this.description, this.value,
      this.type, this.status, this.date);
  final String id, description, type, status;
  final double? value;
  final DateTime? date;
  factory PlusEntry.fromJson(Map<String, dynamic> j) => PlusEntry(
    '${j['order_id'] ?? ''}', '${j['description'] ?? 'Movimentação'}',
    PlusApi.amount(j['value']), '${j['type'] ?? 'Não informado'}',
    '${j['status'] ?? 'Não informado'}', PlusApi.date(j['date']),
  );
}

class PlusRegistration {
  const PlusRegistration(this.steps);
  final Map<String, String> steps;
  static const labels = {
    'regular_status': 'Dados pessoais',
    'complementary_data_status': 'Dados complementares',
    'bank_data_status': 'Dados bancários',
    'profile_picture_status': 'Foto de perfil',
    'documents_status': 'Documentos',
    'professional_profile_status': 'Perfil profissional',
  };
  static String statusLabel(dynamic value) {
    if (value is bool) return value ? 'Concluído' : 'Pendente';
    if (value == null) return 'Não informado';
    final label = value.toString().trim();
    if (label.toLowerCase() == 'true') return 'Concluído';
    if (label.toLowerCase() == 'false') return 'Pendente';
    return label.isEmpty ? 'Não informado' : label;
  }

  factory PlusRegistration.fromJson(Map<String, dynamic> j) =>
      PlusRegistration({
        for (final entry in labels.entries)
          entry.value: statusLabel(j[entry.key]),
      });
}

class PlusCompliance {
  const PlusCompliance(this.canAccept, this.missingDocuments);
  final bool? canAccept;
  final List<String> missingDocuments;
  factory PlusCompliance.fromJson(Map<String, dynamic> j) {
    final raw = j['missingDocuments'];
    return PlusCompliance(
      j['canAcceptNewSchedules'] is bool
          ? j['canAcceptNewSchedules'] as bool : null,
      raw is List
          ? raw.map((e) => '$e').toList()
          : raw is String && raw.trim().isNotEmpty ? [raw] : [],
    );
  }
}

class PlusCourse {
  const PlusCourse(this.id, this.name, this.status, this.type, this.pass);
  final String id, name, status, type;
  final double? pass;
  factory PlusCourse.fromJson(Map<String, dynamic> j) => PlusCourse(
    '${j['id'] ?? ''}', '${j['name'] ?? 'Curso'}',
    '${j['status'] ?? ''}', '${j['type'] ?? ''}',
    PlusApi.amount(j['percentage_to_pass']),
  );
}

class PlusCoursePage {
  const PlusCoursePage(this.items, this.total, this.nextPage);
  final List<PlusCourse> items;
  final int total;
  final int? nextPage;
  factory PlusCoursePage.fromJson(Map<String, dynamic> j) {
    final next = j['nextPage'];
    return PlusCoursePage(
      PlusApi.records(j['courses']).map(PlusCourse.fromJson).toList(),
      (j['totalResults'] as num?)?.toInt() ?? 0,
      next is num && next.toInt() > 0 ? next.toInt() : null,
    );
  }
}

class PlusVideo {
  const PlusVideo(this.title, this.link);
  final String title, link;
  factory PlusVideo.fromJson(Map<String, dynamic> j) =>
      PlusVideo('${j['title'] ?? 'Vídeo'}', '${j['video'] ?? ''}');
}

class PlusQuestion {
  const PlusQuestion(this.id, this.title, this.options, this.positions);
  final String id, title;
  final List<String> options;
  final List<int> positions;
  factory PlusQuestion.fromJson(Map<String, dynamic> j) {
    final raw = j['answersArray'];
    final values = raw is List ? PlusApi.records(raw) : <Map<String, dynamic>>[];
    return PlusQuestion(
      '${j['id'] ?? ''}',
      '${j['enunciation'] ?? ''}',
      values.map((a) => '${a['answer'] ?? ''}').toList(),
      values.map((a) => (a['position'] as num?)?.toInt() ?? -1).toList(),
    );
  }
}

class PlusAnswerKey {
  const PlusAnswerKey(this.question, this.answer);
  final String question, answer;

  factory PlusAnswerKey.fromJson(Map<String, dynamic> json) {
    final raw = json['correct_answer'];
    final entries = json['answersArray'];
    var answer = raw?.toString() ?? '';
    if (entries is List && raw != null) {
      for (final option in entries) {
        if (option is Map && option['position']?.toString() == answer) {
          answer = '${option['answer'] ?? answer}';
          break;
        }
      }
    }
    return PlusAnswerKey(
      '${json['enunciation'] ?? 'Questão'}',
      answer.isEmpty ? 'Gabarito não informado' : answer,
    );
  }
}
