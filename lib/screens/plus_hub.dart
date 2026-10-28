import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/iwof_api.dart';
import '../services/plus_api.dart';

const plusPink = Color(0xFFD93F8F);
const plusMuted = Color(0xFF64748B);

String money(double? amount) => amount == null
    ? 'Não informado'
    : r'R$ ' + amount.toStringAsFixed(2).replaceAll('.', ',');

class PlusHub extends StatelessWidget {
  const PlusHub({
    super.key,
    required this.api,
    required this.token,
    required this.onAccountDeleted,
  });
  final IwofApi api;
  final String token;
  final Future<void> Function() onAccountDeleted;

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
            () => open(context, PlusAccount(
              api: plus,
              token: token,
              onAccountDeleted: onAccountDeleted,
            )),
          ),
          _feature(
            context, Icons.school_outlined,
            'Cursos e avaliações', 'Cursos, vídeos, materiais e resultados',
            () => open(context, PlusCourses(api: plus, token: token)),
          ),
          _feature(
            context, Icons.support_agent_outlined,
            'Suporte', 'Chamados da sua conta no iWof',
            () => open(context, PlusSupport(api: plus, token: token)),
          ),
          _feature(
            context, Icons.event_available_outlined,
            'Treinamentos presenciais', 'Agendamentos e histórico de presença',
            () => open(context, PlusClassrooms(api: plus, token: token)),
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
  Future<List<Map<String, dynamic>>>? withdrawals;
  String selectedStatus = 'Todos';
  bool withdrawalBusy = false;
  String? get id => resolveWorker(widget.token);

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> requestWithdrawal(PlusWorker current) async {
    if (withdrawalBusy) return;
    final amountController = TextEditingController();
    final form = GlobalKey<FormState>();
    final amount = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Solicitar saque'),
        content: Form(key: form, child: TextFormField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Valor em reais', prefixText: 'R\$ '),
          validator: (value) {
            final parsed = PlusApi.amount(value?.trim());
            if (parsed == null || !parsed.isFinite || parsed <= 0) {
              return 'Informe um valor válido.';
            }
            if (current.balance != null && parsed > current.balance!) {
              return 'O valor excede o saldo informado pelo iWof.';
            }
            return null;
          },
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(d, PlusApi.amount(amountController.text.trim()));
            }
          }, child: const Text('Revisar')),
        ],
      ),
    );
    amountController.dispose();
    if (amount == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Confirmar solicitação de saque'),
        content: Text('Enviar ao iWof a solicitação de ' + money(amount) + '?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Solicitar saque')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => withdrawalBusy = true);
    try {
      await widget.api.requestWithdrawal(widget.token, amount);
      reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitação recebida pelo iWof. Confira o extrato para acompanhar.')),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O iWof não confirmou o saque. Confira o extrato antes de tentar novamente.')),
      );
    } finally {
      if (mounted) setState(() => withdrawalBusy = false);
    }
  }

  void reload() {
    if (id == null) { return; }
    setState(() {
      worker = widget.api.workerWithBankInformation(widget.token, id!);
      entries = widget.api.extract(widget.token, id!);
      withdrawals = widget.api.withdrawals(widget.token, id!);
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
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: withdrawalBusy || snapshot.data!.balance == null
                            ? null : () => requestWithdrawal(snapshot.data!),
                        icon: withdrawalBusy
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.payments_outlined),
                        label: const Text('Solicitar saque'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          const Text('Histórico de saques',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: withdrawals,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return errorPanel('o histórico de saques', reload);
              }
              if (snapshot.data!.isEmpty) {
                return const ListTile(title: Text('Nenhum saque informado pelo iWof.'));
              }
              return Column(children: [
                for (final item in snapshot.data!)
                  Card(child: ListTile(
                    title: Text(money(PlusApi.amount(item['amount']))),
                    subtitle: Text('${item['status'] ?? 'Não informado'} · ${item['type'] ?? 'Saque'}'
                        '${PlusApi.date(item['created_at']) == null ? '' : ' · ${PlusApi.date(item['created_at'])!.day.toString().padLeft(2, '0')}/${PlusApi.date(item['created_at'])!.month.toString().padLeft(2, '0')}/${PlusApi.date(item['created_at'])!.year}'}'),
                  )),
              ]);
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
            'A solicitação é enviada ao iWof e não significa transferência imediata. '
            'Confira a situação no extrato.',
            style: TextStyle(color: plusMuted, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

Widget _profileField(String label, String value, {bool sensitive = false}) {
  if (value.trim().isEmpty) return const SizedBox.shrink();
  return Builder(builder: (context) {
    final state = context.findAncestorStateOfType<_PlusAccountState>();
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(!sensitive || (state?.showSensitive ?? false)
          ? value : '••••••••'),
      leading: Icon(sensitive ? Icons.lock_outline : Icons.person_pin_circle_outlined,
          color: plusPink),
    );
  });
}

class PlusSupport extends StatefulWidget {
  const PlusSupport({super.key, required this.api, required this.token});
  final PlusApi api;
  final String token;

  @override
  State<PlusSupport> createState() => _PlusSupportState();
}

class _PlusSupportState extends State<PlusSupport> {
  Future<List<Map<String, dynamic>>>? tickets;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    final id = resolveWorker(widget.token);
    if (id != null) setState(() {
      tickets = widget.api.supportTickets(widget.token, id);
    });
  }

  bool creating = false;

  Future<void> createTicket() async {
    if (creating) return;
    final subject = TextEditingController();
    final message = TextEditingController();
    final values = await showDialog<(String, String)>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Novo chamado'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: subject,
              decoration: const InputDecoration(labelText: 'Assunto')),
            TextField(controller: message, maxLines: 5,
              decoration: const InputDecoration(labelText: 'Descreva o problema')),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            final title = subject.text.trim();
            final body = message.text.trim();
            if (title.isNotEmpty && body.isNotEmpty) Navigator.pop(d, (title, body));
          }, child: const Text('Enviar chamado')),
        ],
      ),
    );
    subject.dispose();
    message.dispose();
    if (values == null || !mounted) return;
    setState(() => creating = true);
    try {
      await widget.api.createSupportTicket(widget.token, values.$1, values.$2);
      if (!mounted) return;
      reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chamado enviado ao iWof.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O iWof não confirmou a abertura. Atualize a lista antes de tentar novamente.')));
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Suporte'), actions: [
      IconButton(
        tooltip: 'Novo chamado',
        onPressed: creating || resolveWorker(widget.token) == null ? null : createTicket,
        icon: const Icon(Icons.add_comment_outlined),
      ),
      IconButton(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
    ]),
    body: resolveWorker(widget.token) == null ? noWorkerId() :
      FutureBuilder<List<Map<String, dynamic>>>(
        future: tickets,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return errorPanel('os chamados', reload);
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('Nenhum chamado informado pelo iWof.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
            children: [
              for (final ticket in snapshot.data!)
                Card(child: ListTile(
                  leading: const Icon(Icons.support_agent_outlined, color: plusPink),
                  title: Text('${ticket['subject'] ?? 'Chamado'}'),
                  subtitle: Text('${ticket['status'] ?? 'Situação não informada'}'),
                  onTap: () {
                    final id = '${ticket['ticket_id'] ?? ''}';
                    if (id.isNotEmpty) {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => PlusTicketDetail(
                          api: widget.api, token: widget.token, ticketId: id),
                      )).then((_) => reload());
                    }
                  },
                )),
            ],
          );
        },
      ),
  );
}

class PlusTicketDetail extends StatefulWidget {
  const PlusTicketDetail({super.key, required this.api, required this.token, required this.ticketId});
  final PlusApi api;
  final String token, ticketId;
  @override
  State<PlusTicketDetail> createState() => _PlusTicketDetailState();
}

class _PlusTicketDetailState extends State<PlusTicketDetail> {
  late Future<Map<String, dynamic>> ticket;
  bool sending = false;
  @override
  void initState() {
    super.initState();
    ticket = widget.api.supportTicket(widget.token, widget.ticketId);
  }

  void reload() => setState(() {
    ticket = widget.api.supportTicket(widget.token, widget.ticketId);
  });

  Future<void> openAttachment(String value) async {
    final url = Uri.tryParse(value);
    if (url == null || url.scheme != 'https' || url.host.isEmpty ||
        !await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o anexo.')));
    }
  }

  Future<void> reply() async {
    if (sending) return;
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context, builder: (d) => AlertDialog(
        title: const Text('Responder chamado'),
        content: TextField(controller: controller, maxLines: 5,
          decoration: const InputDecoration(labelText: 'Mensagem')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(d, value);
          }, child: const Text('Enviar')),
        ],
      ),
    );
    controller.dispose();
    if (message == null || !mounted) return;
    setState(() => sending = true);
    try {
      await widget.api.replyToTicket(widget.token, widget.ticketId, message);
      if (!mounted) return;
      reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resposta enviada ao iWof.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O iWof não confirmou o envio. Atualize o chamado antes de tentar novamente.')));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chamado'), actions: [
      IconButton(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
    ]),
    body: FutureBuilder<Map<String, dynamic>>(
      future: ticket,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) return errorPanel('o chamado', reload);
        final data = snapshot.data!;
        final raw = data['comments'];
        final comments = raw is List ? raw.whereType<Map>().toList() : <Map>[];
        return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 72), children: [
          Text('${data['subject'] ?? 'Chamado'}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text('${data['status'] ?? 'Situação não informada'}'),
          const SizedBox(height: 16),
          for (final comment in comments)
            Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ListTile(
                title: Text('${comment['author'] ?? 'Suporte'}'),
                subtitle: Text('${comment['plain_body'] ?? ''}'),
              ),
              if (comment['attachments'] is List)
                for (final attachment in (comment['attachments'] as List).whereType<Map>())
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.attach_file, color: plusPink),
                    title: Text('${attachment['name'] ?? 'Anexo'}'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => openAttachment('${attachment['url'] ?? ''}'),
                  ),
            ])),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: sending ? null : reply,
            icon: const Icon(Icons.reply), label: const Text('Responder chamado')),
        ]);
      },
    ),
  );
}

class PlusClassrooms extends StatefulWidget {
  const PlusClassrooms({super.key, required this.api, required this.token});
  final PlusApi api;
  final String token;
  @override
  State<PlusClassrooms> createState() => _PlusClassroomsState();
}

class _PlusClassroomsState extends State<PlusClassrooms> {
  late Future<List<Map<String, dynamic>>> scheduled;
  late Future<List<Map<String, dynamic>>> history;
  late Future<List<Map<String, dynamic>>> available;
  bool enrolling = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    setState(() {
      available = widget.api.availableClassrooms(widget.token);
      scheduled = widget.api.classroomPresences(widget.token, history: false);
      history = widget.api.classroomPresences(widget.token, history: true);
    });
  }

  Future<void> enroll(Map<String, dynamic> classroom) async {
    if (enrolling) return;
    final id = '${classroom['id'] ?? ''}';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Agendar treinamento?'),
        content: Text('Enviar sua inscrição em ${classroom['name'] ?? 'treinamento'} ao iWof?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Agendar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => enrolling = true);
    try {
      await widget.api.enrollClassroom(widget.token, id);
      if (!mounted) return;
      refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agendamento confirmado pelo iWof.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O iWof não confirmou. Confira os agendamentos antes de tentar novamente.')));
    } finally {
      if (mounted) setState(() => enrolling = false);
    }
  }

  Widget availableSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Turmas disponíveis', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: available,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) return errorPanel('as turmas', refresh);
          if (snapshot.data!.isEmpty) {
            return const ListTile(title: Text('Nenhuma turma informada pelo iWof.'));
          }
          return Column(children: [
            for (final item in snapshot.data!)
              Card(child: ListTile(
                leading: const Icon(Icons.school_outlined, color: plusPink),
                title: Text('${item['name'] ?? 'Treinamento'}'),
                subtitle: Text([
                  if (item['classroom_date'] != null) '${item['classroom_date']}',
                  if (item['time_start'] != null) '${item['time_start']}',
                  if (item['vacancies'] != null) '${item['vacancies']} vagas',
                ].join(' · ')),
                trailing: TextButton(onPressed: enrolling ? null : () => enroll(item),
                  child: const Text('Agendar')),
              )),
          ]);
        },
      ),
    ],
  );

  Widget section(String title, Future<List<Map<String, dynamic>>> data) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return errorPanel(title.toLowerCase(), refresh);
          }
          if (snapshot.data!.isEmpty) {
            return const ListTile(title: Text('Nenhum registro informado pelo iWof.'));
          }
          return Column(children: [
            for (final record in snapshot.data!)
              Builder(builder: (context) {
                final raw = record['classroom'];
                final classroom = raw is Map ? raw : const {};
                final date = PlusApi.date(classroom['classroom_date']);
                final dateLabel = date == null ? '' :
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                return Card(child: ListTile(
                  leading: const Icon(Icons.event_available_outlined, color: plusPink),
                  title: Text('${classroom['name'] ?? 'Treinamento'}'),
                  subtitle: Text([
                    if (dateLabel.isNotEmpty) dateLabel,
                    if (classroom['time_start'] != null) '${classroom['time_start']}',
                    if (classroom['time_end'] != null) '${classroom['time_end']}',
                    if (record['status'] != null) '${record['status']}',
                  ].join(' · ')),
                ));
              }),
          ]);
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Treinamentos presenciais'), actions: [
      IconButton(onPressed: refresh, icon: const Icon(Icons.refresh_rounded)),
    ]),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 72), children: [
      availableSection(),
      const SizedBox(height: 22),
      section('Agendados', scheduled),
      const SizedBox(height: 22),
      section('Histórico', history),
    ]),
  );
}

class PlusAccount extends StatefulWidget {
  const PlusAccount({
    super.key,
    required this.api,
    required this.token,
    required this.onAccountDeleted,
  });
  final PlusApi api;
  final String token;
  final Future<void> Function() onAccountDeleted;
  @override
  State<PlusAccount> createState() => _PlusAccountState();
}

class _PlusAccountState extends State<PlusAccount> {
  Future<PlusWorker>? worker;
  Future<PlusRegistration>? registration;
  Future<PlusCompliance>? compliance;
  Future<List<String>>? qualifications;
  bool busy = false, showSensitive = false;
  final ImagePicker imagePicker = ImagePicker();
  String? get id => resolveWorker(widget.token);

  @override
  void initState() { super.initState(); reload(); }

  void reload() {
    if (id == null) return;
    setState(() {
      worker = widget.api.worker(widget.token, id!);
      registration = widget.api.registration(widget.token, id!);
      compliance = widget.api.compliance(widget.token, id!);
      qualifications = widget.api.qualifications(widget.token, id!);
    });
  }

  void message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Future<void> updateBankInformation(PlusWorker current) async {
    if (busy) return;
    final f = <String, TextEditingController>{
      'pix_key': TextEditingController(text: current.pixKey),
      'banco': TextEditingController(text: current.bank),
      'conta': TextEditingController(text: current.account),
      'conta_digito_verificador': TextEditingController(text: current.accountCheckDigit),
      'conta_tipo': TextEditingController(text: current.accountType),
      'conta_nome_responsavel': TextEditingController(text: current.accountHolder),
      'conta_cpf_responsavel': TextEditingController(text: current.accountHolderCpf),
    };
    final form = GlobalKey<FormState>();
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Atualizar dados bancários'),
        content: SizedBox(width: 420, child: SingleChildScrollView(
          child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min,
            children: [for (final e in f.entries) TextFormField(
              controller: e.value,
              obscureText: e.key == 'conta_cpf_responsavel',
              keyboardType: e.key.contains('cpf') ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(labelText: switch (e.key) {
                'pix_key' => 'Chave Pix (opcional)',
                'banco' => 'Banco',
                'conta' => 'Conta',
                'conta_digito_verificador' => 'Dígito',
                'conta_tipo' => 'Tipo da conta',
                'conta_nome_responsavel' => 'Titular',
                _ => 'CPF do titular',
              }),
              validator: e.key == 'pix_key' ? null : (v) =>
                  v == null || v.trim().isEmpty ? 'Obrigatório' : null,
            )],
          )),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(d, {for (final e in f.entries) e.key: e.value.text.trim()});
            }
          }, child: const Text('Revisar')),
        ],
      ),
    );
    for (final c in f.values) { c.dispose(); }
    if (values == null || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Confirmar dados bancários'),
      content: const Text('Os dados atuais serão substituídos pelos informados.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Salvar no iWof')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.saveBankInformation(widget.token,
        pixKey: values['pix_key'] ?? '', bank: values['banco']!,
        account: values['conta']!, accountCheckDigit: values['conta_digito_verificador']!,
        accountType: values['conta_tipo']!, accountHolder: values['conta_nome_responsavel']!,
        accountHolderCpf: values['conta_cpf_responsavel']!);
      reload(); message('Dados bancários confirmados pelo iWof.');
    } catch (_) { message('Não foi possível atualizar os dados bancários.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> updateProfilePhoto() async {
    if (busy) return;
    final image = await imagePicker.pickImage(
      source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800, maxHeight: 1800);
    if (image == null || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Atualizar foto de perfil'),
      content: Text('Enviar ' + image.name + ' como foto da sua conta iWof?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enviar foto')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      final url = await widget.api.uploadImage(widget.token,
        filename: image.name, bytes: await image.readAsBytes());
      await widget.api.setWorkerProfilePhoto(widget.token, url);
      reload(); message('Foto de perfil confirmada pelo iWof.');
    } catch (_) { message('Não foi possível atualizar a foto.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> updateRgImages() async {
    if (busy) return;
    final front = await imagePicker.pickImage(
      source: ImageSource.gallery, imageQuality: 90, maxWidth: 2400, maxHeight: 2400);
    if (front == null || !mounted) return;
    final back = await imagePicker.pickImage(
      source: ImageSource.gallery, imageQuality: 90, maxWidth: 2400, maxHeight: 2400);
    if (back == null || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Enviar imagens do RG'),
      content: Text('Enviar frente (' + front.name + ') e verso (' + back.name +
          ') para os documentos da sua conta iWof?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Revisar imagens')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enviar documentos')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      final frontUrl = await widget.api.uploadImage(widget.token,
        filename: front.name, bytes: await front.readAsBytes());
      final backUrl = await widget.api.uploadImage(widget.token,
        filename: back.name, bytes: await back.readAsBytes());
      await widget.api.setWorkerRgImages(widget.token,
        frontImage: frontUrl, backImage: backUrl);
      reload(); message('Documentos RG enviados ao iWof.');
    } catch (_) { message('Não foi possível enviar os documentos RG.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> updateProfileDetails(PlusWorker current) async {
    if (id == null || busy) return;
    final fields = <String, TextEditingController>{
      'rg': TextEditingController(text: current.rg),
      'gender': TextEditingController(text: current.gender),
      'zipcode': TextEditingController(text: current.zipcode),
      'address': TextEditingController(text: current.address),
      'complement': TextEditingController(text: current.complement),
      'neighborhood': TextEditingController(text: current.neighborhood),
      'city': TextEditingController(text: current.city),
    };
    final form = GlobalKey<FormState>();
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Editar dados do perfil'),
        content: SizedBox(width: 420, child: SingleChildScrollView(
          child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in fields.entries)
                TextFormField(
                  controller: e.value,
                  keyboardType: e.key == 'zipcode' || e.key == 'rg'
                      ? TextInputType.text : TextInputType.text,
                  decoration: InputDecoration(labelText: switch (e.key) {
                    'rg' => 'RG',
                    'gender' => 'Gênero',
                    'zipcode' => 'CEP',
                    'address' => 'Endereço',
                    'complement' => 'Complemento',
                    'neighborhood' => 'Bairro',
                    _ => 'Cidade',
                  }),
                ),
            ],
          )),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d,
            {for (final e in fields.entries) e.key: e.value.text.trim()}),
            child: const Text('Revisar')),
        ],
      ),
    );
    for (final c in fields.values) { c.dispose(); }
    if (values == null || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Confirmar alteração de perfil'),
      content: const Text('Os campos informados serão enviados à sua conta iWof.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Salvar no iWof')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.updateWorkerProfile(widget.token, id!,
        rg: values['rg']!, gender: values['gender']!, zipcode: values['zipcode']!,
        address: values['address']!, complement: values['complement']!,
        neighborhood: values['neighborhood']!, city: values['city']!);
      reload(); message('Perfil confirmado pelo iWof.');
    } catch (_) { message('Não foi possível atualizar o perfil.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> updateEmail() async {
    if (id == null || busy) return;
    final c = TextEditingController();
    final email = await showDialog<String>(context: context, builder: (d) => AlertDialog(
      title: const Text('Atualizar e-mail'),
      content: TextField(controller: c, keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Novo e-mail')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          final v = c.text.trim();
          if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) Navigator.pop(d, v);
        }, child: const Text('Continuar')),
      ],
    ));
    c.dispose();
    if (email == null || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Confirmar e-mail'),
      content: Text('Alterar o e-mail do iWof para ' + email + ' e enviar código?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enviar código')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.updateWorkerEmail(widget.token, id!, email);
      await widget.api.sendEmailVerification(widget.token, email);
      if (!mounted) return;
      final codeC = TextEditingController();
      final code = await showDialog<String>(context: context, builder: (d) => AlertDialog(
        title: const Text('Verificar e-mail'),
        content: TextField(controller: codeC, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Código recebido')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fazer depois')),
          FilledButton(onPressed: () {
            if (codeC.text.trim().isNotEmpty) Navigator.pop(d, codeC.text.trim());
          }, child: const Text('Confirmar')),
        ],
      ));
      codeC.dispose();
      if (code == null) message('Código enviado; conclua a verificação para finalizar.');
      else {
        await widget.api.verifyWorkerEmail(widget.token, id!, email, code);
        message('E-mail confirmado pelo iWof.');
      }
      reload();
    } catch (_) { message('Não foi possível concluir a alteração de e-mail.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> openOfficialPage(String page) async {
    try {
      final url = await widget.api.signupHandoffUrl(widget.token, page: page);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Não foi possível abrir a página oficial.');
      }
    } catch (_) {
      message('Não foi possível abrir a página oficial do iWof. Tente novamente.');
    }
  }

  Future<void> deleteAccount() async {
    if (busy || id == null) return;
    final confirmation = TextEditingController();
    var acknowledged = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Excluir conta do iWof?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A exclusão é permanente e será enviada ao iWof. '
                  'Ela pode remover seus dados, histórico e acesso aos serviços.',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: acknowledged,
                  onChanged: (value) => setDialogState(
                    () => acknowledged = value == true,
                  ),
                  title: const Text('Entendo que esta ação não pode ser desfeita.'),
                ),
                TextField(
                  controller: confirmation,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Digite EXCLUIR CONTA para confirmar',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
              ),
              onPressed: acknowledged && confirmation.text.trim() == 'EXCLUIR CONTA'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Excluir permanentemente'),
            ),
          ],
        ),
      ),
    );
    confirmation.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.deleteWorkerApp(widget.token, id!);
      await widget.onAccountDeleted();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      message('O iWof não confirmou a exclusão. A sessão foi mantida.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addExperience() async {
    if (busy) return;
    final p = TextEditingController(), c = TextEditingController();
    final form = GlobalKey<FormState>();
    DateTime? start, end;
    final result = await showDialog<(String, String, DateTime, DateTime?)>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, setD) => AlertDialog(
        title: const Text('Adicionar experiência'),
        content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: p, decoration: const InputDecoration(labelText: 'Função'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Informe a função' : null),
          TextFormField(controller: c, decoration: const InputDecoration(labelText: 'Empresa'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Informe a empresa' : null),
          TextButton(onPressed: () async {
            final v = await showDatePicker(context: d, initialDate: start ?? DateTime.now(),
              firstDate: DateTime(1950), lastDate: DateTime.now());
            if (v != null) setD(() => start = v);
          }, child: Text(start == null ? 'Escolher início' : start!.toIso8601String().substring(0, 10))),
          TextButton(onPressed: () async {
            final v = await showDatePicker(context: d, initialDate: end ?? DateTime.now(),
              firstDate: start ?? DateTime(1950), lastDate: DateTime.now());
            if (v != null) setD(() => end = v);
          }, child: Text(end == null ? 'Término opcional' : end!.toIso8601String().substring(0, 10))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            if (form.currentState!.validate() && start != null &&
                (end == null || !end!.isBefore(start!))) {
              Navigator.pop(d, (p.text.trim(), c.text.trim(), start!, end));
            }
          }, child: const Text('Continuar')),
        ],
      )),
    );
    p.dispose(); c.dispose();
    if (result == null || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Confirmar experiência'),
      content: Text('Enviar ' + result.$1 + ' na empresa ' + result.$2 + ' ao iWof?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enviar')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.addProfessionalExperience(widget.token, position: result.$1,
        companyName: result.$2, startDate: result.$3, endDate: result.$4);
      reload(); message('Experiência confirmada pelo iWof.');
    } catch (_) { message('Não foi possível adicionar a experiência.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Minha conta'), actions: [
      IconButton(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
    ]),
    body: id == null ? noWorkerId() : ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
      children: [
        FutureBuilder<List<String>>(
          future: qualifications,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Card(child: ListTile(
                title: Text('Habilitações'),
                trailing: CircularProgressIndicator(),
              ));
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return errorPanel('as habilitações', reload);
            }
            final items = snapshot.data!;
            return Card(
              child: ExpansionTile(
                leading: const Icon(Icons.verified_outlined, color: plusPink),
                title: const Text('Habilitações', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(items.isEmpty
                    ? 'Nenhuma habilitação informada'
                    : '${items.length} ${items.length == 1 ? 'habilitação' : 'habilitações'}'),
                children: [
                  for (final name in items)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      leading: const Icon(Icons.check_circle_outline, color: plusPink),
                      title: Text(name),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        const Text('Perfil profissional', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        FutureBuilder<PlusWorker>(future: worker, builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData) return errorPanel('o perfil', reload);
          final p = snap.data!;
          return Card(child: Column(children: [
            ListTile(
              leading: p.image.isEmpty ? const CircleAvatar(child: Icon(Icons.person_outline))
                  : CircleAvatar(backgroundImage: NetworkImage(p.image)),
              title: Text(p.name),
              subtitle: Text('Pontuação: ' + (p.score?.toStringAsFixed(1) ?? 'não informada')),
            ),
            OutlinedButton.icon(onPressed: busy ? null : updateProfilePhoto,
              icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Atualizar foto de perfil')),
            _profileField('Telefone', p.phone),
            _profileField('E-mail', p.email),
            _profileField('Nascimento', p.birthdate),
            _profileField('Gênero', p.gender),
            _profileField('Endereço', [p.address, p.complement, p.neighborhood, p.city, p.state, p.zipcode]
                .where((v) => v.trim().isNotEmpty).join(' · ')),
            _profileField('Estado civil', p.civilStatus),
            _profileField('Escolaridade', p.schooling),
            for (final e in p.experiences) _profileField('Experiência profissional', e),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: busy ? null : () => updateProfileDetails(p),
                icon: const Icon(Icons.edit_outlined), label: const Text('Editar dados do perfil')),
              OutlinedButton.icon(onPressed: busy ? null : updateEmail,
                icon: const Icon(Icons.alternate_email), label: const Text('Atualizar e-mail')),
              OutlinedButton.icon(onPressed: busy ? null : addExperience,
                icon: const Icon(Icons.work_outline), label: const Text('Adicionar experiência')),
            ]),
            OutlinedButton.icon(
              onPressed: busy ? null : () => openOfficialPage('perfil'),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Abrir perfil completo no iWof'),
            ),
            const Divider(),
            ListTile(title: const Text('Dados pessoais e bancários'),
              subtitle: const Text('Campos sensíveis ocultos até solicitar exibição.'),
              trailing: IconButton(onPressed: () => setState(() => showSensitive = !showSensitive),
                icon: Icon(showSensitive ? Icons.visibility_off : Icons.visibility))),
            _profileField('CPF', p.cpf, sensitive: true),
            _profileField('RG', p.rg, sensitive: true),
            _profileField('Chave Pix', p.pixKey, sensitive: true),
            _profileField('Tipo Pix', p.pixType, sensitive: true),
            _profileField('Banco', p.bank, sensitive: true),
            _profileField('Tipo de conta', p.accountType, sensitive: true),
            _profileField('Conta', p.account + '-' + p.accountCheckDigit, sensitive: true),
            _profileField('Titular', p.accountHolder, sensitive: true),
            _profileField('CPF do titular', p.accountHolderCpf, sensitive: true),
            OutlinedButton.icon(onPressed: busy ? null : () => updateBankInformation(p),
              icon: const Icon(Icons.account_balance), label: const Text('Atualizar dados bancários')),
            ListTile(title: const Text('Situação do cadastro'),
              subtitle: Text(p.activated == null ? 'Não informada' : p.activated! ? 'Ativo' : 'Inativo')),
            if (p.blocked == true) const ListTile(
              leading: Icon(Icons.warning_amber, color: Colors.orange),
              title: Text('Existe um bloqueio informado pelo serviço')),
          ]));
        }),
        const SizedBox(height: 22),
        const Text('Etapas de cadastro', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        FutureBuilder<PlusRegistration>(future: registration, builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData) return errorPanel('o cadastro', reload);
          return Card(child: Column(children: [
            for (final e in snap.data!.steps.entries)
              ListTile(title: Text(e.key), subtitle: Text(e.value),
                leading: const Icon(Icons.fact_check_outlined, color: plusPink)),
          ]));
        }),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: busy ? null : updateRgImages,
          icon: const Icon(Icons.badge_outlined),
          label: const Text('Enviar frente e verso do RG')),
        const SizedBox(height: 22),
        const Text('Posso aceitar novos serviços?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        FutureBuilder<PlusCompliance>(future: compliance, builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData) return errorPanel('a elegibilidade', reload);
          final v = snap.data!;
          return Card(child: Column(children: [
            ListTile(leading: Icon(v.canAccept == true ? Icons.verified_outlined : Icons.info_outline, color: plusPink),
              title: Text(v.canAccept == null ? 'Situação não informada' :
                  v.canAccept! ? 'Elegível segundo o serviço' : 'Pendências para agendamento')),
            for (final item in v.missingDocuments)
              ListTile(leading: const Icon(Icons.description_outlined), title: Text(item)),
          ]));
        }),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: busy ? null : deleteAccount,
          icon: const Icon(Icons.delete_forever_outlined, color: Color(0xFFB91C1C)),
          label: const Text('Excluir minha conta do iWof'),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
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

  Future<void> openOfficialCourses() async {
    try {
      final url = await widget.api.signupHandoffUrl(widget.token, page: 'cursos');
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Não foi possível abrir os cursos oficiais.');
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Não foi possível abrir os cursos oficiais do iWof.');
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
        OutlinedButton.icon(
          onPressed: openOfficialCourses,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Abrir cursos no site oficial do iWof'),
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
