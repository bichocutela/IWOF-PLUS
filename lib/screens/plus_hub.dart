import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/iwof_api.dart';
import '../services/plus_api.dart';

const plusPink = Color(0xFFD93F8F);
const plusMuted = Color(0xFF64748B);

String money(double? amount) => amount == null
    ? 'Não informado'
    : r'R$ ' + amount.toStringAsFixed(2).replaceAll('.', ',');

class PlusHub extends StatelessWidget {
  const PlusHub({super.key, required this.api, required this.token});
  final IwofApi api;
  final String token;

  void open(BuildContext context, Widget child) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plus = PlusApi(api);
    return Scaffold(
      appBar: AppBar(title: const Text('Central PLUS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
        children: [
          const Text('Tudo organizado em um só lugar',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          const SizedBox(height: 5),
          const Text(
            'Vagas, cursos, avaliações, carteira e situação cadastral '
            'organizados com os dados da sua conta.',
            style: TextStyle(color: plusMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          _feature(
            context, Icons.account_balance_wallet_outlined,
            'Carteira e extrato', 'Saldo e histórico de movimentações',
            () => open(context, PlusFinance(api: plus, token: token)),
          ),
          _feature(
            context, Icons.verified_user_outlined,
            'Minha conta', 'Situação cadastral, documentos e elegibilidade',
            () => open(context, PlusAccount(api: plus, token: token)),
          ),
          _feature(
            context, Icons.school_outlined,
            'Cursos e avaliações', 'Cursos, vídeos, materiais e resultados',
            () => open(context, PlusCourses(api: plus, token: token)),
          ),
          if (PlusApi.workerIdFromSession(token) == null)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline_rounded, color: plusPink),
                title: Text('Algumas consultas exigem identificação da conta'),
                subtitle: Text(
                  'A sessão atual não informa o identificador do profissional. '
                  'Carteira e cadastro podem ficar indisponíveis; '
                  'não tentaremos consultar outra conta.',
                ),
              ),
            ),

        ],
      ),
    );
  }

  Widget _feature(BuildContext context, IconData icon, String title,
      String description, VoidCallback action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 18, vertical: 10),
          leading: Icon(icon, color: plusPink, size: 29),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(description),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: action,
        ),
      ),
    );
  }
}

String? resolveWorker(String token) => PlusApi.workerIdFromSession(token);

Widget noWorkerId() => const Padding(
  padding: EdgeInsets.all(20),
  child: Text(
    'Esta sessão não informou o identificador do profissional. '
    'Não vamos adivinhar um ID ou consultar dados de outra conta. '
    'Você continua podendo consultar vagas e cursos. '
    'Abra novamente sua sessão se o serviço atualizar a autenticação.',
    style: TextStyle(height: 1.5, color: plusMuted),
  ),
);

Widget errorPanel(String what, VoidCallback retry) => Card(
  child: Padding(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Não foi possível consultar $what.',
            style: const TextStyle(color: Color(0xFFB91C1C))),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: retry,
          child: const Text('Tentar novamente'),
        ),
      ],
    ),
  ),
);

class PlusFinance extends StatefulWidget {
  const PlusFinance({super.key, required this.api, required this.token});
  final PlusApi api;
  final String token;

  @override
  State<PlusFinance> createState() => _PlusFinanceState();
}

class _PlusFinanceState extends State<PlusFinance> {
  Future<PlusWorker>? worker;
  Future<List<PlusEntry>>? entries;
  String selectedStatus = 'Todos';
  String? get id => resolveWorker(widget.token);

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> updateEmail() async {
    if (id == null || mutationInProgress) return;
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Atualizar e-mail'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Novo e-mail'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+
    if (id == null) { return; }
    setState(() {
      worker = widget.api.worker(widget.token, id!);
      entries = widget.api.extract(widget.token, id!);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Carteira e extrato'),
      actions: [
        IconButton(
          tooltip: 'Atualizar valores',
          onPressed: reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: id == null ? noWorkerId() : RefreshIndicator(
      onRefresh: () async {
        reload();
        await Future.wait<dynamic>([
          worker!.catchError((Object _) => throw StateError('Saldo indisponível')),
          entries!.catchError((Object _) => throw StateError('Extrato indisponível')),
        ]).catchError((Object _) => <dynamic>[]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
        children: [
          const Text('Saldo informado pelo iWof',
              style: TextStyle(color: plusMuted)),
          const SizedBox(height: 10),
          FutureBuilder<PlusWorker>(
            future: worker,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return errorPanel('o saldo', reload);
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(money(snapshot.data!.balance),
                          style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      const Text('Informação consultiva. Não representa '
                          'pagamento já transferido para seu banco.',
                          style: TextStyle(color: plusMuted, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          const Text('Movimentações',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FutureBuilder<List<PlusEntry>>(
            future: entries,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData) {
                return errorPanel('o extrato', reload);
              }
              if (snapshot.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhuma movimentação retornada.',
                      style: TextStyle(color: plusMuted)),
                );
              }
              final values = snapshot.data!;
              final statuses = values
                  .map((item) => item.status.trim())
                  .where((status) => status.isNotEmpty)
                  .toSet()
                  .toList()..sort();
              final selected = statuses.contains(selectedStatus)
                  ? selectedStatus : 'Todos';
              final visible = selected == 'Todos'
                  ? values
                  : values.where((item) => item.status.trim() == selected)
                      .toList();
              return Column(
                children: [
                  if (statuses.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selected,
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'Todos',
                            child: Text('Todos os status'),
                          ),
                          for (final status in statuses)
                            DropdownMenuItem<String>(
                              value: status,
                              child: Text(status),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => selectedStatus = value);
                          }
                        },
                      ),
                    ),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Nenhuma movimentação com este status.'),
                    ),
                  for (final item in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          title: Text(item.description),
                          subtitle: Text(
                            '${item.type} · ${item.status}'
                            '${item.date == null ? '' : ' · ${item.date!.day.toString().padLeft(2, '0')}/${item.date!.month.toString().padLeft(2, '0')}/${item.date!.year}'}',
                          ),
                          trailing: Text(money(item.value),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'Solicitações de saque e alterações bancárias não são '
            'realizadas pelo IWOF PLUS nesta etapa.',
            style: TextStyle(color: plusMuted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class PlusAccount extends StatefulWidget {
  const PlusAccount({super.key, required this.api, required this.token});
  final PlusApi api;
  final String token;

  @override
  State<PlusAccount> createState() => _PlusAccountState();
}

Widget _profileField(String label, String value, {bool sensitive = false}) {
  if (value.trim().isEmpty) return const SizedBox.shrink();
  return Builder(builder: (context) {
    final state = context.findAncestorStateOfType<_PlusAccountState>();
    final visible = !sensitive || (state?.showSensitive ?? false);
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(visible ? value : '••••••••'),
      leading: Icon(
        sensitive ? Icons.lock_outline : Icons.person_pin_circle_outlined,
        color: plusPink,
      ),
    );
  });
}

class _PlusAccountState extends State<PlusAccount> {
  bool mutationInProgress = false;
  Future<PlusWorker>? worker;
  bool showSensitive = false;
  Future<PlusRegistration>? registration;
  Future<PlusCompliance>? compliance;
  String? get id => resolveWorker(widget.token);

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    if (id == null) { return; }
    setState(() {
      worker = widget.api.worker(widget.token, id!);
      registration = widget.api.registration(widget.token, id!);
      compliance = widget.api.compliance(widget.token, id!);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Minha conta'),
      actions: [
        IconButton(
          tooltip: 'Atualizar situação',
          onPressed: reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: id == null ? noWorkerId() : ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
      children: [
        const Text('Perfil profissional',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FutureBuilder<PlusWorker>(
          future: worker,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) { return errorPanel('o perfil', reload); }
            final p = snapshot.data!;
            return Card(
              child: Column(
                children: [
                  ListTile(
                    leading: p.image.trim().isEmpty
                        ? const CircleAvatar(
                            backgroundColor: Color(0xFFFCE8F2),
                            child: Icon(Icons.person_outline, color: plusPink),
                          )
                        : CircleAvatar(
                            backgroundImage: NetworkImage(p.image),
                            onBackgroundImageError: (_, __) {},
                          ),
                    title: Text(p.name),
                    subtitle: Text('Pontuação: ${p.score?.toStringAsFixed(1) ?? 'Não informada'}'),
                  ),
                  _profileField('Telefone de acesso', p.phone),
                  _profileField('E-mail', p.email),
                  _profileField('Nascimento', p.birthdate),
                  _profileField('Gênero', p.gender),
                  _profileField('Endereço', [
                    p.address, p.complement, p.neighborhood,
                    p.city, p.state, p.zipcode,
                  ].where((value) => value.trim().isNotEmpty).join(' · ')),
                  _profileField('Estado civil', p.civilStatus),
                  _profileField('Escolaridade', p.schooling),
                  for (final experience in p.experiences)
                    _profileField('Experiência profissional', experience),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: mutationInProgress ? null : updateEmail,
                          icon: const Icon(Icons.alternate_email_rounded),
                          label: const Text('Atualizar e-mail'),
                        ),
                        OutlinedButton.icon(
                          onPressed: mutationInProgress ? null : addExperience,
                          icon: const Icon(Icons.work_outline_rounded),
                          label: const Text('Adicionar experiência'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  ListTile(
                    title: const Text('Dados pessoais e bancários'),
                    subtitle: const Text(
                      'Ocultos até você tocar no botão. Não são salvos pelo PLUS.',
                    ),
                    trailing: IconButton(
                      tooltip: showSensitive ? 'Ocultar dados' : 'Revelar dados',
                      onPressed: () => setState(
                        () => showSensitive = !showSensitive,
                      ),
                      icon: Icon(showSensitive
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                    ),
                  ),
                  _profileField('CPF', p.cpf, sensitive: true),
                  _profileField('RG', p.rg, sensitive: true),
                  _profileField('Chave Pix', p.pixKey, sensitive: true),
                  _profileField('Tipo da chave Pix', p.pixType, sensitive: true),
                  _profileField('Banco', p.bank, sensitive: true),
                  _profileField('Tipo de conta', p.accountType, sensitive: true),
                  _profileField('Conta', [
                    p.account, p.accountCheckDigit,
                  ].where((value) => value.trim().isNotEmpty).join('-'),
                      sensitive: true),
                  _profileField('Titular da conta', p.accountHolder,
                      sensitive: true),
                  _profileField('CPF do titular', p.accountHolderCpf,
                      sensitive: true),
                  ListTile(
                    title: const Text('Situação do cadastro'),
                    subtitle: Text(p.activated == null
                        ? 'Não informada' : p.activated! ? 'Ativo' : 'Inativo'),
                  ),
                  if (p.blocked == true)
                    const ListTile(
                      title: Text('Existe um bloqueio informado pelo serviço'),
                      leading: Icon(Icons.warning_amber, color: Colors.orange),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        const Text('Etapas de cadastro',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FutureBuilder<PlusRegistration>(
          future: registration,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) { return errorPanel('o cadastro', reload); }
            return Card(
              child: Column(
                children: [
                  for (final step in snapshot.data!.steps.entries)
                    ListTile(
                      title: Text(step.key),
                      subtitle: Text(step.value),
                      leading: const Icon(Icons.fact_check_outlined,
                          color: plusPink),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        const Text('Posso aceitar novos serviços?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FutureBuilder<PlusCompliance>(
          future: compliance,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return errorPanel('a elegibilidade', reload);
            }
            final result = snapshot.data!;
            return Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      result.canAccept == true
                          ? Icons.verified_outlined
                          : Icons.info_outline,
                      color: plusPink,
                    ),
                    title: Text(result.canAccept == null
                        ? 'Situação não informada'
                        : result.canAccept!
                            ? 'Elegível segundo o serviço'
                            : 'Pendências para agendamento'),
                  ),
                  for (final document in result.missingDocuments)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(document),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text(
          'O PLUS não solicita sua senha. Dados de identidade e banco exibidos '
          'nesta tela ficam ocultos até você revelar. Alterações só são enviadas '
          'após confirmação; comprovantes e documentos serão tratados em etapas próprias.',
          style: TextStyle(color: plusMuted, fontSize: 12),
        ),
      ],
    ),
  );
}

class PlusCourses extends StatefulWidget {
  const PlusCourses({super.key, required this.api, required this.token});
  final PlusApi api;
  final String token;

  @override
  State<PlusCourses> createState() => _PlusCoursesState();
}

class _PlusCoursesState extends State<PlusCourses> {
  final List<PlusCourse> items = [];
  final Set<int> visited = {};
  String courseFilter = '';
  bool busy = false;
  String? error;
  int? nextPage = 1;
  Future<PlusWorker>? worker;

  @override
  void initState() {
    super.initState();
    unawaited(load());
    final workerId = resolveWorker(widget.token);
    if (workerId != null) {
      worker = widget.api.worker(widget.token, workerId);
    }
  }

  Future<void> load({bool reset = false}) async {
    if (busy) { return; }
    final page = reset ? 1 : nextPage;
    if (page == null || (!reset && visited.contains(page))) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.courses(widget.token, page: page);
      if (!mounted) { return; }
      setState(() {
        // Keep the previous list visible if the refresh request fails.
        if (reset) {
          items.clear();
          visited.clear();
        }
        visited.add(page);
        final known = items.map((e) => e.id).toSet();
        for (final course in result.items) {
          if (known.add(course.id)) { items.add(course); }
        }
        nextPage = result.nextPage == page ? null : result.nextPage;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível carregar os cursos.');
      }
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  Future<void> showAnswerKey(PlusCourse course) async {
    final result = widget.api.answerKey(widget.token, course.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .8,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Text(
                'Gabarito • ${course.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Respostas de estudo fornecidas pela API do iWof. '
                'Nenhuma prova ou resultado será alterado.',
                style: TextStyle(color: plusMuted),
              ),
              const SizedBox(height: 14),
              FutureBuilder<List<PlusAnswerKey>>(
                future: result,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Text(
                      'Não foi possível consultar o gabarito deste curso.',
                    );
                  }
                  if (snapshot.data!.isEmpty) {
                    return const Text('Nenhuma questão disponível.');
                  }
                  return Column(
                    children: [
                      for (var index = 0;
                          index < snapshot.data!.length;
                          index++)
                        Card(
                          child: ListTile(
                            title: Text(
                              '${index + 1}. ${snapshot.data![index].question}',
                            ),
                            subtitle: Text(
                              snapshot.data![index].answer,
                              style: const TextStyle(
                                color: plusPink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cursos e avaliações'),
      actions: [
        IconButton(
          tooltip: 'Atualizar cursos',
          onPressed: busy ? null : () => load(reset: true),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
      children: [
        const Text('Cursos disponíveis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Vídeos, materiais e questões para consulta. '
          'Não enviamos avaliações automaticamente.',
          style: TextStyle(color: plusMuted),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) => setState(() => courseFilter = value),
          decoration: const InputDecoration(
            labelText: 'Buscar nos cursos carregados',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 14),
        if (error != null) errorPanel('os cursos', () => load(reset: true)),
        for (final course in items.where(
          (course) => course.name.toLowerCase().contains(
            courseFilter.trim().toLowerCase(),
          ),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.play_circle_outline,
                    color: plusPink),
                title: Text(course.name),
                subtitle: Text(
                  'Status: ${course.status.isEmpty ? 'Não informado' : course.status}'
                  '${course.pass == null ? '' : ' · Aprovação: ${course.pass}%'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Ver gabarito de ${course.name}',
                      onPressed: () => showAnswerKey(course),
                      icon: const Icon(
                        Icons.add_circle_rounded,
                        color: plusPink,
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlusCourseDetail(
                        api: widget.api,
                        token: widget.token,
                        course: course,
                      ),
                    ),
                  );
                  if (mounted) {
                    load(reset: true);
                  }
                },
              ),
            ),
          ),
        if (busy)
          const Center(child: Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(),
          )),
        if (!busy && items.isEmpty && error == null)
          const Text('Nenhum curso retornado.'),
        if (!busy && nextPage != null)
          OutlinedButton.icon(
            onPressed: () => load(),
            icon: const Icon(Icons.expand_more),
            label: const Text('Carregar mais cursos'),
          ),
        const SizedBox(height: 28),
        const Text('Minhas avaliações',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (worker == null)
          const Text('Histórico de avaliações indisponível nesta sessão.',
              style: TextStyle(color: plusMuted))
        else
          FutureBuilder<PlusWorker>(
            future: worker,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator();
              }
              if (!snapshot.hasData) {
                return const Text('Não foi possível consultar avaliações.',
                    style: TextStyle(color: plusMuted));
              }
              final attempts = snapshot.data!.attempts;
              if (attempts.isEmpty) {
                return const Text('Nenhuma avaliação retornada.');
              }
              return Column(
                children: [
                  for (final attempt in attempts)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          attempt.approved == true
                              ? Icons.check_circle_outline
                              : Icons.assignment_outlined,
                          color: plusPink,
                        ),
                        title: Text(attempt.name),
                        subtitle: Text(attempt.approved == null
                            ? 'Resultado não informado'
                            : attempt.approved! ? 'Aprovado' : 'Não aprovado'),
                        trailing: Text(attempt.percentage == null
                            ? '—' : '${attempt.percentage!.toStringAsFixed(1)}%'),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    ),
  );
}

class PlusCourseDetail extends StatefulWidget {
  const PlusCourseDetail({
    super.key, required this.api, required this.token, required this.course,
  });
  final PlusApi api;
  final String token;
  final PlusCourse course;

  @override
  State<PlusCourseDetail> createState() => _PlusCourseDetailState();
}

class _PlusCourseDetailState extends State<PlusCourseDetail> {
  late Future<List<PlusVideo>> videos;
  Future<List<PlusQuestion>>? questions;
  final Map<int, int> chosenAnswers = {};
  bool submitting = false;
  bool? officialResult;
  DateTime? officialSubmittedAt;
  Future<PlusWorker>? officialHistory;

  void refreshOfficialHistory() {
    final id = resolveWorker(widget.token);
    if (id == null) {
      return;
    }
    setState(() {
      officialHistory = widget.api.worker(widget.token, id);
    });
  }

  int answeredCount(int total) => chosenAnswers.keys
      .where((index) => index >= 0 && index < total).length;

  @override
  void initState() {
    super.initState();
    videos = widget.api.videos(widget.token, widget.course.id);
  }

  Future<void> submitOfficial(List<PlusQuestion> questionsList) async {
    if (submitting || officialResult != null ||
        chosenAnswers.length != questionsList.length ||
        questionsList.isEmpty) {
      return;
    }
    final answers = <Map<String, dynamic>>[];
    for (var i = 0; i < questionsList.length; i++) {
      final selected = chosenAnswers[i];
      final question = questionsList[i];
      if (selected == null || question.id.isEmpty ||
          selected >= question.positions.length ||
          question.positions[selected] < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Há respostas inválidas ou incompletas.')),
        );
        return;
      }
      answers.add({
        'questionId': question.id,
        'answer': question.positions[selected],
      });
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar avaliação oficial?'),
        content: const Text(
          'Suas respostas serão enviadas ao iWof original. '
          'A avaliação poderá ser contabilizada pelo servidor. '
          'Confira todas as respostas antes de confirmar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Revisar respostas'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enviar avaliação'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final startedAt = DateTime.now().toUtc();
    setState(() => submitting = true);
    try {
      final approved = await widget.api.submitAssessment(
        widget.token, widget.course.id, answers,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        officialResult = approved;
        officialSubmittedAt = startedAt;
      });
      refreshOfficialHistory();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approved
            ? 'Avaliação confirmada pelo iWof: aprovado.'
            : 'Avaliação confirmada pelo iWof: não aprovado.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível confirmar o envio. Confira o histórico '
              'no iWof antes de tentar novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  Future<void> openVideo(String value) async {
    final url = Uri.tryParse(value);
    if (url == null || url.scheme != 'https') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Endereço de vídeo indisponível.')),
      );
      return;
    }
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vídeo não pôde ser aberto.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.course.name)),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
      children: [
        const Text('Vídeos do curso',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        FutureBuilder<List<PlusVideo>>(
          future: videos,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return errorPanel('os vídeos', () => setState(() =>
                  videos = widget.api.videos(widget.token, widget.course.id)));
            }
            if (snapshot.data!.isEmpty) {
              return const Text('Nenhum vídeo disponível.');
            }
            return Column(
              children: [
                for (final video in snapshot.data!)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.play_circle_outline,
                          color: plusPink),
                      title: Text(video.title),
                      subtitle: const Text('Abrir em aplicativo externo'),
                      onTap: () => openVideo(video.link),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const Text('Questões disponíveis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Responda todas as questões para enviar a avaliação oficial. '
          'O resultado será informado pelo servidor iWof.',
          style: TextStyle(color: plusMuted),
        ),
        const SizedBox(height: 14),
        if (questions == null)
          OutlinedButton(
            onPressed: () => setState(() {
              questions = widget.api.questions(widget.token, widget.course.id);
            }),
            child: const Text('Ver questões de estudo'),
          )
        else
          FutureBuilder<List<PlusQuestion>>(
            future: questions,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData) {
                return errorPanel('as questões', () => setState(() {
                  questions = widget.api.questions(
                      widget.token, widget.course.id);
                }));
              }
              final questionsList = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Respondidas neste estudo: '
                    '${answeredCount(questionsList.length)} de '
                    '${questionsList.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < questionsList.length; index++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${index + 1}. ${questionsList[index].title}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (var optionIndex = 0;
                                optionIndex < questionsList[index].options.length;
                                optionIndex++)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  chosenAnswers[index] == optionIndex
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: chosenAnswers[index] == optionIndex
                                      ? plusPink : plusMuted,
                                ),
                                title: Text(
                                  questionsList[index].options[optionIndex],
                                ),
                                onTap: () => setState(
                                  () => chosenAnswers[index] = optionIndex,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (officialResult != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_outlined, color: plusPink),
                        title: const Text('Resultado confirmado pelo iWof'),
                        subtitle: Text(officialResult! ? 'Aprovado' : 'Não aprovado'),
                      ),
                    )
                  else if (questionsList.isNotEmpty)
                    FilledButton.icon(
                      onPressed: submitting ||
                              chosenAnswers.length != questionsList.length
                          ? null
                          : () => submitOfficial(questionsList),
                      icon: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('Enviar avaliação oficial'),
                    ),
                  if (officialResult != null) ...[
                    const SizedBox(height: 12),
                    if (resolveWorker(widget.token) == null)
                      const Text(
                        'O resultado foi confirmado pela operação de avaliação. '
                        'O histórico detalhado não pode ser consultado porque '
                        'esta sessão não informou o identificador da conta.',
                        style: TextStyle(color: plusMuted),
                      )
                    else ...[
                      OutlinedButton.icon(
                        onPressed: refreshOfficialHistory,
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Atualizar histórico oficial'),
                      ),
                      if (officialHistory != null)
                        FutureBuilder<PlusWorker>(
                          future: officialHistory,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Text(
                                'Histórico indisponível no momento. '
                                'A confirmação da avaliação foi recebida.',
                                style: TextStyle(color: plusMuted),
                              );
                            }
                            final latest = officialSubmittedAt == null
                                ? null
                                : PlusAttempt.confirmedForCourse(
                                    snapshot.data!.attempts,
                                    widget.course.id,
                                    officialSubmittedAt!,
                                  );
                            if (latest == null) {
                              return const Text(
                                'O servidor respondeu à avaliação, mas ainda '
                                'não há uma tentativa recente deste curso no '
                                'histórico oficial. Atualize novamente mais '
                                'tarde; tentativas antigas não são usadas '
                                'como confirmação.',
                                style: TextStyle(color: plusMuted),
                              );
                            }
                            return Card(
                              child: ListTile(
                                title: const Text('Tentativa recente no histórico oficial'),
                                subtitle: Text(
                                  '${latest.approved == true ? 'Aprovado' : latest.approved == false ? 'Não aprovado' : 'Sem resultado'}'
                                  '${latest.percentage == null ? '' : ' · ${latest.percentage!.toStringAsFixed(0)}%'}',
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                  if (chosenAnswers.isNotEmpty && officialResult == null)
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => chosenAnswers.clear()),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reiniciar estudo local'),
                    ),
                  const Text(
                    'Somente a confirmação do servidor representa '
                    'uma avaliação registrada. Não reenvie em caso '
                    'de falha sem verificar o histórico.',
                    style: TextStyle(color: plusMuted, fontSize: 12),
                  ),
                ],
              );
            },
          ),
      ],
    ),
  );
}
).hasMatch(value)) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar alteração'),
        content: Text(
          'O e-mail da conta iWof será alterado para $email. '
          'O serviço enviará um código para esse endereço.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enviar código'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => mutationInProgress = true);
    try {
      await widget.api.updateWorkerEmail(widget.token, id!, email);
      await widget.api.sendEmailVerification(widget.token, email);
      if (!mounted) return;
      final codeController = TextEditingController();
      final code = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Verificar e-mail'),
          content: TextField(
            controller: codeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Código recebido'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fazer depois'),
            ),
            FilledButton(
              onPressed: () {
                final value = codeController.text.trim();
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              child: const Text('Confirmar código'),
            ),
          ],
        ),
      );
      codeController.dispose();
      if (code != null && code.isNotEmpty) {
        await widget.api.verifyWorkerEmail(widget.token, id!, email, code);
        _accountMessage('E-mail confirmado pelo iWof.');
      } else {
        _accountMessage('Código enviado. Conclua a verificação para finalizar.');
      }
      reload();
    } catch (_) {
      _accountMessage('Não foi possível concluir a alteração de e-mail.');
    } finally {
      if (mounted) setState(() => mutationInProgress = false);
    }
  }

  Future<void> addExperience() async {
    if (mutationInProgress) return;
    final positionController = TextEditingController();
    final companyController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? startDate;
    DateTime? endDate;
    final result = await showDialog<(String, String, DateTime, DateTime?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Adicionar experiência'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: positionController,
                    decoration: const InputDecoration(labelText: 'Função'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Informe a função.' : null,
                  ),
                  TextFormField(
                    controller: companyController,
                    decoration: const InputDecoration(labelText: 'Empresa'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Informe a empresa.' : null,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final value = await showDatePicker(
                        context: dialogContext,
                        initialDate: startDate ?? DateTime.now(),
                        firstDate: DateTime(1950),
                        lastDate: DateTime.now(),
                      );
                      if (value != null) setDialogState(() => startDate = value);
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(startDate == null
                        ? 'Escolher início'
                        : 'Início: ${startDate!.day.toString().padLeft(2, '0')}/${startDate!.month.toString().padLeft(2, '0')}/${startDate!.year}'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final value = await showDatePicker(
                        context: dialogContext,
                        initialDate: endDate ?? DateTime.now(),
                        firstDate: startDate ?? DateTime(1950),
                        lastDate: DateTime.now(),
                      );
                      if (value != null) setDialogState(() => endDate = value);
                    },
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(endDate == null
                        ? 'Término (opcional)'
                        : 'Término: ${endDate!.day.toString().padLeft(2, '0')}/${endDate!.month.toString().padLeft(2, '0')}/${endDate!.year}'),
                  ),
                  if (endDate != null && startDate != null &&
                      endDate!.isBefore(startDate!))
                    const Text(
                      'O término precisa ser posterior ao início.',
                      style: TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate() ||
                    startDate == null ||
                    (endDate != null && endDate!.isBefore(startDate!))) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  (
                    positionController.text.trim(),
                    companyController.text.trim(),
                    startDate!,
                    endDate,
                  ),
                );
              },
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    positionController.dispose();
    companyController.dispose();
    if (result == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar envio'),
        content: Text(
          'Adicionar “${result.$1}” na empresa “${result.$2}” '
          'ao seu perfil do iWof?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => mutationInProgress = true);
    try {
      await widget.api.addProfessionalExperience(
        widget.token,
        position: result.$1,
        companyName: result.$2,
        startDate: result.$3,
        endDate: result.$4,
      );
      reload();
      _accountMessage('Experiência registrada pelo iWof.');
    } catch (_) {
      _accountMessage('Não foi possível registrar a experiência.');
    } finally {
      if (mounted) setState(() => mutationInProgress = false);
    }
  }

  void _accountMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void reload() {
    if (id == null) { return; }
    setState(() {
      worker = widget.api.worker(widget.token, id!);
      entries = widget.api.extract(widget.token, id!);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Carteira e extrato'),
      actions: [
        IconButton(
          tooltip: 'Atualizar valores',
          onPressed: reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: id == null ? noWorkerId() : RefreshIndicator(
      onRefresh: () async {
        reload();
        await Future.wait<dynamic>([
          worker!.catchError((Object _) => throw StateError('Saldo indisponível')),
          entries!.catchError((Object _) => throw StateError('Extrato indisponível')),
        ]).catchError((Object _) => <dynamic>[]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
        children: [
          const Text('Saldo informado pelo iWof',
              style: TextStyle(color: plusMuted)),
          const SizedBox(height: 10),
          FutureBuilder<PlusWorker>(
            future: worker,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return errorPanel('o saldo', reload);
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(money(snapshot.data!.balance),
                          style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      const Text('Informação consultiva. Não representa '
                          'pagamento já transferido para seu banco.',
                          style: TextStyle(color: plusMuted, fontSize: 12)),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          const Text('Movimentações',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          FutureBuilder<List<PlusEntry>>(
            future: entries,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData) {
                return errorPanel('o extrato', reload);
              }
              if (snapshot.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhuma movimentação retornada.',
                      style: TextStyle(color: plusMuted)),
                );
              }
              final values = snapshot.data!;
              final statuses = values
                  .map((item) => item.status.trim())
                  .where((status) => status.isNotEmpty)
                  .toSet()
                  .toList()..sort();
              final selected = statuses.contains(selectedStatus)
                  ? selectedStatus : 'Todos';
              final visible = selected == 'Todos'
                  ? values
                  : values.where((item) => item.status.trim() == selected)
                      .toList();
              return Column(
                children: [
                  if (statuses.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selected,
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'Todos',
                            child: Text('Todos os status'),
                          ),
                          for (final status in statuses)
                            DropdownMenuItem<String>(
                              value: status,
                              child: Text(status),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => selectedStatus = value);
                          }
                        },
                      ),
                    ),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Nenhuma movimentação com este status.'),
                    ),
                  for (final item in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          title: Text(item.description),
                          subtitle: Text(
                            '${item.type} · ${item.status}'
                            '${item.date == null ? '' : ' · ${item.date!.day.toString().padLeft(2, '0')}/${item.date!.month.toString().padLeft(2, '0')}/${item.date!.year}'}',
                          ),
                          trailing: Text(money(item.value),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'Solicitações de saque e alterações bancárias não são '
            'realizadas pelo IWOF PLUS nesta etapa.',
            style: TextStyle(color: plusMuted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class PlusAccount extends StatefulWidget {
  const PlusAccount({super.key, required this.api, required this.token});
  final PlusApi api;
  final String token;

  @override
  State<PlusAccount> createState() => _PlusAccountState();
}

Widget _profileField(String label, String value, {bool sensitive = false}) {
  if (value.trim().isEmpty) return const SizedBox.shrink();
  return Builder(builder: (context) {
    final state = context.findAncestorStateOfType<_PlusAccountState>();
    final visible = !sensitive || (state?.showSensitive ?? false);
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(visible ? value : '••••••••'),
      leading: Icon(
        sensitive ? Icons.lock_outline : Icons.person_pin_circle_outlined,
        color: plusPink,
      ),
    );
  });
}

class _PlusAccountState extends State<PlusAccount> {
  bool mutationInProgress = false;
  Future<PlusWorker>? worker;
  bool showSensitive = false;
  Future<PlusRegistration>? registration;
  Future<PlusCompliance>? compliance;
  String? get id => resolveWorker(widget.token);

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    if (id == null) { return; }
    setState(() {
      worker = widget.api.worker(widget.token, id!);
      registration = widget.api.registration(widget.token, id!);
      compliance = widget.api.compliance(widget.token, id!);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Minha conta'),
      actions: [
        IconButton(
          tooltip: 'Atualizar situação',
          onPressed: reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: id == null ? noWorkerId() : ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
      children: [
        const Text('Perfil profissional',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FutureBuilder<PlusWorker>(
          future: worker,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) { return errorPanel('o perfil', reload); }
            final p = snapshot.data!;
            return Card(
              child: Column(
                children: [
                  ListTile(
                    leading: p.image.trim().isEmpty
                        ? const CircleAvatar(
                            backgroundColor: Color(0xFFFCE8F2),
                            child: Icon(Icons.person_outline, color: plusPink),
                          )
                        : CircleAvatar(
                            backgroundImage: NetworkImage(p.image),
                            onBackgroundImageError: (_, __) {},
                          ),
                    title: Text(p.name),
                    subtitle: Text('Pontuação: ${p.score?.toStringAsFixed(1) ?? 'Não informada'}'),
                  ),
                  _profileField('Telefone de acesso', p.phone),
                  _profileField('E-mail', p.email),
                  _profileField('Nascimento', p.birthdate),
                  _profileField('Gênero', p.gender),
                  _profileField('Endereço', [
                    p.address, p.complement, p.neighborhood,
                    p.city, p.state, p.zipcode,
                  ].where((value) => value.trim().isNotEmpty).join(' · ')),
                  _profileField('Estado civil', p.civilStatus),
                  _profileField('Escolaridade', p.schooling),
                  for (final experience in p.experiences)
                    _profileField('Experiência profissional', experience),
                  const Divider(height: 24),
                  ListTile(
                    title: const Text('Dados pessoais e bancários'),
                    subtitle: const Text(
                      'Ocultos até você tocar no botão. Não são salvos pelo PLUS.',
                    ),
                    trailing: IconButton(
                      tooltip: showSensitive ? 'Ocultar dados' : 'Revelar dados',
                      onPressed: () => setState(
                        () => showSensitive = !showSensitive,
                      ),
                      icon: Icon(showSensitive
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                    ),
                  ),
                  _profileField('CPF', p.cpf, sensitive: true),
                  _profileField('RG', p.rg, sensitive: true),
                  _profileField('Chave Pix', p.pixKey, sensitive: true),
                  _profileField('Tipo da chave Pix', p.pixType, sensitive: true),
                  _profileField('Banco', p.bank, sensitive: true),
                  _profileField('Tipo de conta', p.accountType, sensitive: true),
                  _profileField('Conta', [
                    p.account, p.accountCheckDigit,
                  ].where((value) => value.trim().isNotEmpty).join('-'),
                      sensitive: true),
                  _profileField('Titular da conta', p.accountHolder,
                      sensitive: true),
                  _profileField('CPF do titular', p.accountHolderCpf,
                      sensitive: true),
                  ListTile(
                    title: const Text('Situação do cadastro'),
                    subtitle: Text(p.activated == null
                        ? 'Não informada' : p.activated! ? 'Ativo' : 'Inativo'),
                  ),
                  if (p.blocked == true)
                    const ListTile(
                      title: Text('Existe um bloqueio informado pelo serviço'),
                      leading: Icon(Icons.warning_amber, color: Colors.orange),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        const Text('Etapas de cadastro',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FutureBuilder<PlusRegistration>(
          future: registration,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) { return errorPanel('o cadastro', reload); }
            return Card(
              child: Column(
                children: [
                  for (final step in snapshot.data!.steps.entries)
                    ListTile(
                      title: Text(step.key),
                      subtitle: Text(step.value),
                      leading: const Icon(Icons.fact_check_outlined,
                          color: plusPink),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        const Text('Posso aceitar novos serviços?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FutureBuilder<PlusCompliance>(
          future: compliance,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return errorPanel('a elegibilidade', reload);
            }
            final result = snapshot.data!;
            return Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      result.canAccept == true
                          ? Icons.verified_outlined
                          : Icons.info_outline,
                      color: plusPink,
                    ),
                    title: Text(result.canAccept == null
                        ? 'Situação não informada'
                        : result.canAccept!
                            ? 'Elegível segundo o serviço'
                            : 'Pendências para agendamento'),
                  ),
                  for (final document in result.missingDocuments)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(document),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text(
          'Dados bancários, CPF, imagens de documentos e senha não são '
          'solicitados por esta tela.',
          style: TextStyle(color: plusMuted, fontSize: 12),
        ),
      ],
    ),
  );
}

class PlusCourses extends StatefulWidget {
  const PlusCourses({super.key, required this.api, required this.token});
  final PlusApi api;
  final String token;

  @override
  State<PlusCourses> createState() => _PlusCoursesState();
}

class _PlusCoursesState extends State<PlusCourses> {
  final List<PlusCourse> items = [];
  final Set<int> visited = {};
  String courseFilter = '';
  bool busy = false;
  String? error;
  int? nextPage = 1;
  Future<PlusWorker>? worker;

  @override
  void initState() {
    super.initState();
    unawaited(load());
    final workerId = resolveWorker(widget.token);
    if (workerId != null) {
      worker = widget.api.worker(widget.token, workerId);
    }
  }

  Future<void> load({bool reset = false}) async {
    if (busy) { return; }
    final page = reset ? 1 : nextPage;
    if (page == null || (!reset && visited.contains(page))) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.courses(widget.token, page: page);
      if (!mounted) { return; }
      setState(() {
        // Keep the previous list visible if the refresh request fails.
        if (reset) {
          items.clear();
          visited.clear();
        }
        visited.add(page);
        final known = items.map((e) => e.id).toSet();
        for (final course in result.items) {
          if (known.add(course.id)) { items.add(course); }
        }
        nextPage = result.nextPage == page ? null : result.nextPage;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível carregar os cursos.');
      }
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  Future<void> showAnswerKey(PlusCourse course) async {
    final result = widget.api.answerKey(widget.token, course.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .8,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Text(
                'Gabarito • ${course.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Respostas de estudo fornecidas pela API do iWof. '
                'Nenhuma prova ou resultado será alterado.',
                style: TextStyle(color: plusMuted),
              ),
              const SizedBox(height: 14),
              FutureBuilder<List<PlusAnswerKey>>(
                future: result,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Text(
                      'Não foi possível consultar o gabarito deste curso.',
                    );
                  }
                  if (snapshot.data!.isEmpty) {
                    return const Text('Nenhuma questão disponível.');
                  }
                  return Column(
                    children: [
                      for (var index = 0;
                          index < snapshot.data!.length;
                          index++)
                        Card(
                          child: ListTile(
                            title: Text(
                              '${index + 1}. ${snapshot.data![index].question}',
                            ),
                            subtitle: Text(
                              snapshot.data![index].answer,
                              style: const TextStyle(
                                color: plusPink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cursos e avaliações'),
      actions: [
        IconButton(
          tooltip: 'Atualizar cursos',
          onPressed: busy ? null : () => load(reset: true),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
      children: [
        const Text('Cursos disponíveis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Vídeos, materiais e questões para consulta. '
          'Não enviamos avaliações automaticamente.',
          style: TextStyle(color: plusMuted),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (value) => setState(() => courseFilter = value),
          decoration: const InputDecoration(
            labelText: 'Buscar nos cursos carregados',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 14),
        if (error != null) errorPanel('os cursos', () => load(reset: true)),
        for (final course in items.where(
          (course) => course.name.toLowerCase().contains(
            courseFilter.trim().toLowerCase(),
          ),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.play_circle_outline,
                    color: plusPink),
                title: Text(course.name),
                subtitle: Text(
                  'Status: ${course.status.isEmpty ? 'Não informado' : course.status}'
                  '${course.pass == null ? '' : ' · Aprovação: ${course.pass}%'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Ver gabarito de ${course.name}',
                      onPressed: () => showAnswerKey(course),
                      icon: const Icon(
                        Icons.add_circle_rounded,
                        color: plusPink,
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlusCourseDetail(
                        api: widget.api,
                        token: widget.token,
                        course: course,
                      ),
                    ),
                  );
                  if (mounted) {
                    load(reset: true);
                  }
                },
              ),
            ),
          ),
        if (busy)
          const Center(child: Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(),
          )),
        if (!busy && items.isEmpty && error == null)
          const Text('Nenhum curso retornado.'),
        if (!busy && nextPage != null)
          OutlinedButton.icon(
            onPressed: () => load(),
            icon: const Icon(Icons.expand_more),
            label: const Text('Carregar mais cursos'),
          ),
        const SizedBox(height: 28),
        const Text('Minhas avaliações',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (worker == null)
          const Text('Histórico de avaliações indisponível nesta sessão.',
              style: TextStyle(color: plusMuted))
        else
          FutureBuilder<PlusWorker>(
            future: worker,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator();
              }
              if (!snapshot.hasData) {
                return const Text('Não foi possível consultar avaliações.',
                    style: TextStyle(color: plusMuted));
              }
              final attempts = snapshot.data!.attempts;
              if (attempts.isEmpty) {
                return const Text('Nenhuma avaliação retornada.');
              }
              return Column(
                children: [
                  for (final attempt in attempts)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          attempt.approved == true
                              ? Icons.check_circle_outline
                              : Icons.assignment_outlined,
                          color: plusPink,
                        ),
                        title: Text(attempt.name),
                        subtitle: Text(attempt.approved == null
                            ? 'Resultado não informado'
                            : attempt.approved! ? 'Aprovado' : 'Não aprovado'),
                        trailing: Text(attempt.percentage == null
                            ? '—' : '${attempt.percentage!.toStringAsFixed(1)}%'),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    ),
  );
}

class PlusCourseDetail extends StatefulWidget {
  const PlusCourseDetail({
    super.key, required this.api, required this.token, required this.course,
  });
  final PlusApi api;
  final String token;
  final PlusCourse course;

  @override
  State<PlusCourseDetail> createState() => _PlusCourseDetailState();
}

class _PlusCourseDetailState extends State<PlusCourseDetail> {
  late Future<List<PlusVideo>> videos;
  Future<List<PlusQuestion>>? questions;
  final Map<int, int> chosenAnswers = {};
  bool submitting = false;
  bool? officialResult;
  DateTime? officialSubmittedAt;
  Future<PlusWorker>? officialHistory;

  void refreshOfficialHistory() {
    final id = resolveWorker(widget.token);
    if (id == null) {
      return;
    }
    setState(() {
      officialHistory = widget.api.worker(widget.token, id);
    });
  }

  int answeredCount(int total) => chosenAnswers.keys
      .where((index) => index >= 0 && index < total).length;

  @override
  void initState() {
    super.initState();
    videos = widget.api.videos(widget.token, widget.course.id);
  }

  Future<void> submitOfficial(List<PlusQuestion> questionsList) async {
    if (submitting || officialResult != null ||
        chosenAnswers.length != questionsList.length ||
        questionsList.isEmpty) {
      return;
    }
    final answers = <Map<String, dynamic>>[];
    for (var i = 0; i < questionsList.length; i++) {
      final selected = chosenAnswers[i];
      final question = questionsList[i];
      if (selected == null || question.id.isEmpty ||
          selected >= question.positions.length ||
          question.positions[selected] < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Há respostas inválidas ou incompletas.')),
        );
        return;
      }
      answers.add({
        'questionId': question.id,
        'answer': question.positions[selected],
      });
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar avaliação oficial?'),
        content: const Text(
          'Suas respostas serão enviadas ao iWof original. '
          'A avaliação poderá ser contabilizada pelo servidor. '
          'Confira todas as respostas antes de confirmar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Revisar respostas'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enviar avaliação'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final startedAt = DateTime.now().toUtc();
    setState(() => submitting = true);
    try {
      final approved = await widget.api.submitAssessment(
        widget.token, widget.course.id, answers,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        officialResult = approved;
        officialSubmittedAt = startedAt;
      });
      refreshOfficialHistory();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approved
            ? 'Avaliação confirmada pelo iWof: aprovado.'
            : 'Avaliação confirmada pelo iWof: não aprovado.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível confirmar o envio. Confira o histórico '
              'no iWof antes de tentar novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  Future<void> openVideo(String value) async {
    final url = Uri.tryParse(value);
    if (url == null || url.scheme != 'https') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Endereço de vídeo indisponível.')),
      );
      return;
    }
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vídeo não pôde ser aberto.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.course.name)),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
      children: [
        const Text('Vídeos do curso',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        FutureBuilder<List<PlusVideo>>(
          future: videos,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return errorPanel('os vídeos', () => setState(() =>
                  videos = widget.api.videos(widget.token, widget.course.id)));
            }
            if (snapshot.data!.isEmpty) {
              return const Text('Nenhum vídeo disponível.');
            }
            return Column(
              children: [
                for (final video in snapshot.data!)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.play_circle_outline,
                          color: plusPink),
                      title: Text(video.title),
                      subtitle: const Text('Abrir em aplicativo externo'),
                      onTap: () => openVideo(video.link),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const Text('Questões disponíveis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Responda todas as questões para enviar a avaliação oficial. '
          'O resultado será informado pelo servidor iWof.',
          style: TextStyle(color: plusMuted),
        ),
        const SizedBox(height: 14),
        if (questions == null)
          OutlinedButton(
            onPressed: () => setState(() {
              questions = widget.api.questions(widget.token, widget.course.id);
            }),
            child: const Text('Ver questões de estudo'),
          )
        else
          FutureBuilder<List<PlusQuestion>>(
            future: questions,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData) {
                return errorPanel('as questões', () => setState(() {
                  questions = widget.api.questions(
                      widget.token, widget.course.id);
                }));
              }
              final questionsList = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Respondidas neste estudo: '
                    '${answeredCount(questionsList.length)} de '
                    '${questionsList.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < questionsList.length; index++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${index + 1}. ${questionsList[index].title}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (var optionIndex = 0;
                                optionIndex < questionsList[index].options.length;
                                optionIndex++)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  chosenAnswers[index] == optionIndex
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: chosenAnswers[index] == optionIndex
                                      ? plusPink : plusMuted,
                                ),
                                title: Text(
                                  questionsList[index].options[optionIndex],
                                ),
                                onTap: () => setState(
                                  () => chosenAnswers[index] = optionIndex,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (officialResult != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_outlined, color: plusPink),
                        title: const Text('Resultado confirmado pelo iWof'),
                        subtitle: Text(officialResult! ? 'Aprovado' : 'Não aprovado'),
                      ),
                    )
                  else if (questionsList.isNotEmpty)
                    FilledButton.icon(
                      onPressed: submitting ||
                              chosenAnswers.length != questionsList.length
                          ? null
                          : () => submitOfficial(questionsList),
                      icon: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('Enviar avaliação oficial'),
                    ),
                  if (officialResult != null) ...[
                    const SizedBox(height: 12),
                    if (resolveWorker(widget.token) == null)
                      const Text(
                        'O resultado foi confirmado pela operação de avaliação. '
                        'O histórico detalhado não pode ser consultado porque '
                        'esta sessão não informou o identificador da conta.',
                        style: TextStyle(color: plusMuted),
                      )
                    else ...[
                      OutlinedButton.icon(
                        onPressed: refreshOfficialHistory,
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Atualizar histórico oficial'),
                      ),
                      if (officialHistory != null)
                        FutureBuilder<PlusWorker>(
                          future: officialHistory,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Text(
                                'Histórico indisponível no momento. '
                                'A confirmação da avaliação foi recebida.',
                                style: TextStyle(color: plusMuted),
                              );
                            }
                            final latest = officialSubmittedAt == null
                                ? null
                                : PlusAttempt.confirmedForCourse(
                                    snapshot.data!.attempts,
                                    widget.course.id,
                                    officialSubmittedAt!,
                                  );
                            if (latest == null) {
                              return const Text(
                                'O servidor respondeu à avaliação, mas ainda '
                                'não há uma tentativa recente deste curso no '
                                'histórico oficial. Atualize novamente mais '
                                'tarde; tentativas antigas não são usadas '
                                'como confirmação.',
                                style: TextStyle(color: plusMuted),
                              );
                            }
                            return Card(
                              child: ListTile(
                                title: const Text('Tentativa recente no histórico oficial'),
                                subtitle: Text(
                                  '${latest.approved == true ? 'Aprovado' : latest.approved == false ? 'Não aprovado' : 'Sem resultado'}'
                                  '${latest.percentage == null ? '' : ' · ${latest.percentage!.toStringAsFixed(0)}%'}',
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                  if (chosenAnswers.isNotEmpty && officialResult == null)
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => chosenAnswers.clear()),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Reiniciar estudo local'),
                    ),
                  const Text(
                    'Somente a confirmação do servidor representa '
                    'uma avaliação registrada. Não reenvie em caso '
                    'de falha sem verificar o histórico.',
                    style: TextStyle(color: plusMuted, fontSize: 12),
                  ),
                ],
              );
            },
          ),
      ],
    ),
  );
}
