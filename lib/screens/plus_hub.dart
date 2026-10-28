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
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Tudo organizado em um só lugar',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          const SizedBox(height: 5),
          const Text(
            'Serviços oficiais consultados com a sua sessão. '
            'Somente leitura, sem operações financeiras ou cancelamentos.',
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
          const SizedBox(height: 12),
          const Card(
            child: ExpansionTile(
              title: Text('Operações protegidas'),
              subtitle: Text('Disponíveis no iWof original'),
              leading: Icon(Icons.lock_outline, color: plusPink),
              childrenPadding: EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                Text(
                  'Aceitar ou cancelar serviços, solicitar saques, '
                  'enviar documentos, editar dados bancários, '
                  'redefinir senha e excluir conta exigem validação '
                  'específica do servidor e confirmações de segurança. '
                  'Essas ações não são executadas pelo IWOF PLUS nesta versão.',
                  style: TextStyle(color: plusMuted, height: 1.5),
                ),
              ],
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
        padding: const EdgeInsets.all(20),
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
              return Column(
                children: [
                  for (final item in snapshot.data!)
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

class _PlusAccountState extends State<PlusAccount> {
  Future<PlusWorker>? worker;
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
      padding: const EdgeInsets.all(20),
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
                    leading: const Icon(Icons.person_outline, color: plusPink),
                    title: Text(p.name),
                    subtitle: Text('Pontuação: ${p.score?.toStringAsFixed(1) ?? 'Não informada'}'),
                  ),
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
    if (reset) {
      items.clear();
      nextPage = 1;
      visited.clear();
    }
    final page = nextPage;
    if (page == null || visited.contains(page)) { return; }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.courses(widget.token, page: page);
      if (!mounted) { return; }
      setState(() {
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
      padding: const EdgeInsets.all(20),
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
        if (error != null) errorPanel('os cursos', () => load()),
        for (final course in items)
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
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlusCourseDetail(
                      api: widget.api, token: widget.token, course: course),
                  ),
                ),
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

  @override
  void initState() {
    super.initState();
    videos = widget.api.videos(widget.token, widget.course.id);
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
      padding: const EdgeInsets.all(20),
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
          'Visualização de estudo. Não mostra gabarito, não envia respostas '
          'nem modifica resultados no iWof.',
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final question in snapshot.data!)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(question.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            for (final option in question.options)
                              Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: Text('• $option'),
                              ),
                          ],
                        ),
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
