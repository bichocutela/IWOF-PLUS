import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../services/remote_push.dart';
import '../services/plus_api.dart';
import 'about_screen.dart';
import 'work_screen.dart';
import 'plus_hub.dart';

const pink = Color(0xFFD93F8F);
const muted = Color(0xFF64748B);

class PlusLogo extends StatelessWidget {
  const PlusLogo({super.key, this.large = false});
  final bool large;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: large ? 52 : 34,
        height: large ? 52 : 34,
        decoration: const BoxDecoration(color: pink, shape: BoxShape.circle),
        child: Icon(
          Icons.add_rounded,
          color: Colors.white,
          size: large ? 38 : 26,
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'iwof',
        style: TextStyle(
          fontSize: large ? 46 : 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -2,
          color: pink,
        ),
      ),
      const SizedBox(width: 7),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFCE8F2),
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Text(
          'PLUS',
          style: TextStyle(
            color: pink,
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
      ),
    ],
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phone = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool hidden = true, recovering = false;
  @override
  void dispose() {
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    try {
      await widget.controller.login(phone.text, password.text);
      password.clear();
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> recoverPassword() async {
    final emailController = TextEditingController();
    final email = await showDialog<String>(context: context, builder: (d) => AlertDialog(
      title: const Text('Recuperar senha'),
      content: TextField(controller: emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'E-mail cadastrado')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          final value = emailController.text.trim();
          if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) Navigator.pop(d, value);
        }, child: const Text('Enviar código')),
      ],
    ));
    emailController.dispose();
    if (email == null || !mounted) return;
    setState(() => recovering = true);
    try {
      await widget.controller.api.sendPasswordResetCode(email);
      if (!mounted) return;
      final codeController = TextEditingController();
      final passwordController = TextEditingController();
      final confirmController = TextEditingController();
      final form = GlobalKey<FormState>();
      final credentials = await showDialog<(String, String)>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Definir nova senha'),
          content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: codeController,
              decoration: const InputDecoration(labelText: 'Código recebido'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Informe o código.' : null),
            TextFormField(controller: passwordController, obscureText: true,
              decoration: const InputDecoration(labelText: 'Nova senha'),
              validator: (v) => v == null || v.isEmpty ? 'Informe a senha.' : null),
            TextFormField(controller: confirmController, obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmar nova senha'),
              validator: (v) => v != passwordController.text ? 'As senhas não coincidem.' : null),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
            FilledButton(onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(d, (codeController.text.trim(), passwordController.text));
              }
            }, child: const Text('Redefinir senha')),
          ],
        ),
      );
      codeController.clear();
      passwordController.clear();
      confirmController.clear();
      codeController.dispose();
      passwordController.dispose();
      confirmController.dispose();
      if (credentials == null || !mounted) return;
      await widget.controller.api.resetWorkerPassword(
        email: email, code: credentials.$1, newPassword: credentials.$2);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha alterada pelo iWof. Entre novamente.')),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível redefinir a senha. Confira o código e tente novamente.')),
      );
    } finally {
      if (mounted) setState(() => recovering = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PlusLogo(large: true),
                  const SizedBox(height: 42),
                  const Text(
                    'Sua próxima\noportunidade.',
                    style: TextStyle(
                      fontSize: 35,
                      fontWeight: FontWeight.w800,
                      height: 1.16,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Vagas da sua região. Avisos que acompanham você.',
                    style: TextStyle(fontSize: 16, color: muted, height: 1.5),
                  ),
                  const SizedBox(height: 34),
                  const Text(
                    'Entre com sua conta iWof',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(13),
                    ],
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(
                      labelText: 'Telefone com DDD',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (value) {
                      try {
                        formatPhone(value ?? '');
                        return null;
                      } catch (_) {
                        return 'Informe seu telefone com DDD.';
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: password,
                    obscureText: hidden,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: hidden ? 'Mostrar senha' : 'Ocultar senha',
                        onPressed: () => setState(() => hidden = !hidden),
                        icon: Icon(
                          hidden
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Informe sua senha.'
                        : null,
                  ),
                  if (widget.controller.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        widget.controller.error!,
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: widget.controller.busy ? null : submit,
                      child: widget.controller.busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Entrar',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: recovering ? null : recoverPassword,
                    child: const Text('Esqueci minha senha'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sua senha não é salva. A sessão fica protegida no aparelho.',
                    style: TextStyle(fontSize: 12, color: muted, height: 1.5),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Cliente independente. As oportunidades e a disponibilidade são fornecidas pelo iWof.',
                    style: TextStyle(fontSize: 11, color: muted, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  bool opening = false;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(handleTap);
    WidgetsBinding.instance.addPostFrameCallback((_) => handleTap());
  }

  @override
  void dispose() {
    c.removeListener(handleTap);
    super.dispose();
  }

  void handleTap() {
    if (c.pendingJobId == null || opening || !mounted) return;
    final id = c.pendingJobId!;
    c.consumeJob();
    opening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await openDetail(id);
      opening = false;
      handleTap();
    });
  }

  Future<void> openDetail(String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => JobDetail(controller: c, id: id),
    ),
  );
  bool acceptingFromList = false;
  Future<void> acceptFromList(Job job) async {
    if (acceptingFromList) return;
    acceptingFromList = true;
    try {
      final confirmed = await confirmJobDialog(context, job);
      if (!confirmed || !mounted || c.token == null) return;
      await c.api.acceptJob(c.token!, job.id, workerId: PlusApi.workerIdFromSession(c.token!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agendamento confirmado pelo iWof.')));
      unawaited(c.refresh());
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('O iWof não confirmou o agendamento. Verifique a Agenda antes de tentar novamente.')));
    } finally {
      acceptingFromList = false;
    }
  }

  Future<void> guarded(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppController.cleanError(e))));
      }
    }
  }

  Future<void> regionPicker() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CityPicker(cities: c.cities, current: c.region),
    );
    if (chosen == '__gps__') {
      await c.locate(prompt: true);
    } else if (chosen != null) {
      await c.chooseRegion(chosen);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const PlusLogo(),
      actions: [
        IconButton(
          tooltip: 'Atualizar vagas',
          onPressed: c.busy
              ? null
              : () => guarded(() async {
                  await c.refresh();
                  await c.checkNew();
                }),
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: IndexedStack(
        index: tab,
        children: [
          explore(),
          saved(),
          WorkScreen(
            api: c.api,
            sessionToken: c.token ?? '',
            active: tab == 2,
          ),
          alerts(),
          settings(),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      height: 80,
      selectedIndex: tab,
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFFCE8F2),
      onDestinationSelected: (index) => setState(() => tab = index),
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.work_outline_rounded),
          selectedIcon: Icon(Icons.work_rounded),
          label: 'Vagas',
        ),
        const NavigationDestination(
          icon: Icon(Icons.bookmark_outline_rounded),
          selectedIcon: Icon(Icons.bookmark_rounded),
          label: 'Salvas',
        ),
        const NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month_rounded),
          label: 'Trabalhos',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: c.unread > 0,
            label: Text('${c.unread}'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
          label: 'Avisos',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'Perfil',
        ),
      ],
    ),
  );
  Widget explore() => RefreshIndicator(
    onRefresh: () async {
      await c.refresh();
      await c.checkNew();
    },
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 72),
      children: [
        InkWell(
          onTap: regionPicker,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE8F2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: pink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.automatic ? 'SUA REGIÃO • GPS' : 'REGIÃO SELECIONADA',
                        style: const TextStyle(
                          color: pink,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.region ?? 'Encontrar minha região',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: pink),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Oportunidades\nperto de você',
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w800,
            height: 1.18,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          c.region == null
              ? 'Ative o GPS ou escolha uma cidade para começar.'
              : '${c.total} vagas encontradas em ${c.region}',
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 22),
        TextField(
          onChanged: (value) {
            c.search = value;
            setState(() {});
          },
          decoration: const InputDecoration(
            hintText: 'Buscar função ou empresa',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('Todas'),
                  selected: c.selectedRole.isEmpty,
                  onSelected: (_) {
                    c.selectedRole = '';
                    setState(() {});
                  },
                ),
              ),
              ...c.roles.map(
                (role) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(role),
                    selected: c.selectedRole == role,
                    onSelected: (_) {
                      c.selectedRole = role;
                      setState(() {});
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!c.alertsEnabled && c.region != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Card(
              color: const Color(0xFFF1F5F9),
              child: ListTile(
                leading: const Icon(
                  Icons.notifications_active_outlined,
                  color: pink,
                ),
                title: const Text(
                  'Saiba quando chegar uma vaga',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                trailing: TextButton(
                  onPressed: () => guarded(() => c.setAlerts(true)),
                  child: const Text('Ativar'),
                ),
              ),
            ),
          ),
        const SizedBox(height: 18),
        if (c.error != null) errorCard(c.error!),
        if (c.busy && c.jobs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (c.visibleJobs.isEmpty)
          empty(
            Icons.work_outline,
            c.region == null
                ? 'Escolha sua região'
                : 'Nenhuma vaga por aqui agora',
            'Você pode consultar outras cidades ou atualizar mais tarde.',
            action: regionPicker,
            label: 'Escolher cidade',
          )
        else
          ...c.visibleJobs.map(
            (job) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: JobCard(
                job: job,
                saved: c.saved.any((j) => j.id == job.id),
                onSave: () => c.toggleSaved(job),
                onTap: () => openDetail(job.id),
                onAccept: () => acceptFromList(job),
              ),
            ),
          ),
        if (c.jobs.length < c.total)
          OutlinedButton(
            onPressed: c.loadingMore ? null : c.loadMore,
            child: Text(
              c.loadingMore
                  ? 'Carregando…'
                  : 'Carregar mais vagas (${c.jobs.length}/${c.total})',
            ),
          ),
        if (c.jobs.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Disponibilidade sujeita a alteração. O valor exibido é o informado pelo serviço.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ),
      ],
    ),
  );
  Widget saved() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
    children: [
      sectionTitle(
        'Suas vagas salvas',
        'Guarde as oportunidades que combinam com você.',
      ),
      if (c.saved.isEmpty)
        empty(
          Icons.bookmark_border,
          'Sua lista começa aqui',
          'Abra os detalhes de uma vaga para guardá-la.',
        )
      else
        ...c.saved.map(
          (job) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: JobCard(
              job: job,
              saved: true,
              onSave: () => c.toggleSaved(job),
              onTap: () => openDetail(job.id),
                onAccept: () => acceptFromList(job),
            ),
          ),
        ),
    ],
  );
  Widget alerts() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
    children: [
      sectionTitle('Seus avisos', 'Novas oportunidades na região acompanhada.'),
      if (c.alerts.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: c.unread == 0 ? null : () => guarded(c.markAllAlertsRead),
            icon: const Icon(Icons.done_all),
            label: const Text('Marcar todos como lidos'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('Excluir todos os avisos?'),
                  content: const Text('Isso apaga os avisos desta lista no aparelho.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Excluir avisos')),
                  ],
                ),
              );
              if (confirmed == true && mounted) await guarded(c.deleteAllAlerts);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir todos'),
          ),
        ]),
      const SizedBox(height: 12),
      if (c.alerts.isEmpty)
        empty(
          Icons.notifications_none,
          'Tudo tranquilo por enquanto',
          c.alertsEnabled
              ? 'As vagas existentes são a referência inicial. Novas vagas aparecerão aqui.'
              : 'Ative os avisos no Perfil para acompanhar novidades.',
        )
      else
        ...c.alerts.map((alert) {
          final job = c.alertJob(alert);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                onTap: () => c.readAlert(alert),
                leading: CircleAvatar(
                  backgroundColor: alert['read'] == 0
                      ? const Color(0xFFFCE8F2)
                      : const Color(0xFFF1F5F9),
                  child: const Icon(Icons.work_outline, color: pink),
                ),
                title: Text(
                  job.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${job.store}\n${c.alertRegion(alert)} • ${job.dateLabel}',
                ),
                isThreeLine: true,
                trailing: alert['read'] == 0
                    ? const Icon(Icons.circle, size: 8, color: pink)
                    : null,
              ),
            ),
          );
        }),
    ],
  );
  Widget settings() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 72),
    children: [
      sectionTitle(
        'Do seu jeito',
        'Sua região, seus avisos, suas oportunidades.',
      ),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.location_on_outlined, color: pink),
              title: const Text('Região atual'),
              subtitle: Text(c.region ?? 'Não identificada'),
              trailing: const Icon(Icons.chevron_right),
              onTap: regionPicker,
            ),
            SwitchListTile(
              title: const Text('Região automática'),
              subtitle: const Text(
                'O GPS identifica a cidade e acompanha mudanças.',
              ),
              value: c.automatic,
              onChanged: (value) => guarded(() async {
                if (value) {
                  await c.locate(prompt: true);
                } else {
                  c.automatic = false;
                  await c.prefs!.setBool('automaticRegion', false);
                  await c.startLocationStream();
                  setState(() {});
                }
              }),
            ),
            SwitchListTile(
              title: const Text('Acompanhar com o app minimizado'),
              subtitle: const Text(
                'Exige localização “o tempo todo”. Uma indicação ficará na notificação do Android.',
              ),
              value: c.backgroundLocation,
              onChanged: (value) =>
                  guarded(() => c.setBackgroundLocation(value)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Avisos de novas vagas'),
              subtitle: Text(
                c.region == null
                    ? 'Escolha uma região primeiro.'
                    : 'Acompanhar oportunidades em ${c.region}.',
              ),
              value: c.alertsEnabled,
              onChanged: (value) => guarded(() => c.setAlerts(value)),
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined, color: pink),
              title: Text(
                c.remoteActive
                    ? 'Avisos pelo servidor'
                    : 'Verificação no aparelho',
              ),
              subtitle: Text(
                c.remoteActive
                    ? 'Servidor conectado para enviar notificações.'
                    : 'Verificações periódicas a partir de 15 minutos. O Android pode adiar por bateria ou conexão.',
              ),
            ),
            ListTile(
              title: const Text('Última verificação'),
              subtitle: Text(
                c.prefs
                        ?.getString('lastCheck')
                        ?.replaceFirst('T', ' ')
                        .split('.')
                        .first ??
                    'Ainda não realizada',
              ),
            ),
            if (c.prefs?.getString('monitorError') != null)
              ListTile(
                subtitle: Text(
                  c.prefs!.getString('monitorError')!,
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'Se o GPS ficar indisponível, a última região será mantida. Ao forçar a parada do app, o Android suspende o monitoramento local até você abrir novamente.',
            style: TextStyle(color: muted, height: 1.5, fontSize: 12),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.dashboard_customize_outlined, color: pink),
          title: const Text('Central PLUS'),
          subtitle: const Text('Carteira, extrato, cadastro e cursos'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlusHub(
                api: c.api,
                token: c.token ?? '',
                onAccountDeleted: () => c.logout(unregisterRemote: false),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.system_update_alt_rounded, color: pink),
          title: const Text('Sobre o IWOF PLUS'),
          subtitle: const Text('Versão do app e atualizações'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
          ),
        ),
      ),
      const SizedBox(height: 22),
      OutlinedButton.icon(
        onPressed: () => guarded(c.logout),
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sair da conta'),
      ),
      const SizedBox(height: 18),
      const Center(
        child: Text(
          'IWOF PLUS • Cliente independente',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ),
      if (!pushConfigured)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Avisos pelo servidor serão disponibilizados após a configuração do serviço de push.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ),
    ],
  );
  Widget sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: muted, height: 1.5)),
      ],
    ),
  );
  Widget errorCard(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      color: const Color(0xFFFFF1F2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(color: Color(0xFF9F1239))),
            TextButton(
              onPressed: c.refresh,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    ),
  );
  Widget empty(
    IconData icon,
    String title,
    String text, {
    VoidCallback? action,
    String? label,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 54, color: pink),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, height: 1.5),
        ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: FilledButton(onPressed: action, child: Text(label!)),
          ),
      ],
    ),
  );
}

Future<bool> confirmJobDialog(BuildContext context, Job job) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aceitar este trabalho?'),
        content: Text('Confirme a vaga de ${job.title} na empresa ${job.store}. '
            'O agendamento será enviado à sua conta no iWof.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmar agendamento')),
        ],
      ),
    ) == true;

class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.saved,
    required this.onSave,
    required this.onTap,
    required this.onAccept,
  });
  final Job job;
  final bool saved;
  final VoidCallback onSave, onTap, onAccept;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: job.image == null
                        ? const ColoredBox(
                            color: Color(0xFFFCE8F2),
                            child: Icon(Icons.storefront_outlined, color: pink),
                          )
                        : Image.network(
                            job.image!,
                            fit: BoxFit.contain,
                            cacheWidth: 144,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Color(0xFFFCE8F2),
                              child: Icon(
                                Icons.storefront_outlined,
                                color: pink,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.store,
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        job.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (job.flameCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Semantics(
                      label: '${job.flameCount} ${job.flameCount == 1 ? 'destaque' : 'destaques'} da função',
                      child: Text(List.filled(job.flameCount, '🔥').join(),
                        style: const TextStyle(fontSize: 20)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 16, color: pink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    job.scheduleLabel,
                    style: const TextStyle(fontSize: 12, color: pink, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    job.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: onAccept, child: const Text('Aceitar vaga')),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  job.valueLabel,
                  style: const TextStyle(
                    color: pink,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Ver vaga',
                  style: TextStyle(
                    color: pink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 16, color: pink),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class CityPicker extends StatefulWidget {
  const CityPicker({super.key, required this.cities, this.current});
  final List<String> cities;
  final String? current;
  @override
  State<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<CityPicker> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.cities
        .where(
          (city) => normalizeCity(city).contains(normalizeCity(input.text)),
        )
        .toList();
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Onde você quer trabalhar?',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, '__gps__'),
                    icon: const Icon(Icons.my_location),
                    label: const Text('Usar minha localização'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: input,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Buscar ou digitar cidade',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  if (input.text.trim().isNotEmpty &&
                      !filtered.any(
                        (city) =>
                            normalizeCity(city) == normalizeCity(input.text),
                      ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Consultar “${input.text.trim()}”'),
                      subtitle: const Text(
                        'A lista do serviço pode não incluir todas as cidades.',
                      ),
                      onTap: () => Navigator.pop(context, input.text.trim()),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
            sliver: SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(filtered[index]),
                trailing:
                    normalizeCity(widget.current ?? '') ==
                            normalizeCity(filtered[index])
                        ? const Icon(Icons.check_circle, color: pink)
                        : null,
                onTap: () => Navigator.pop(context, filtered[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class JobDetail extends StatefulWidget {
  const JobDetail({super.key, required this.controller, required this.id});
  final AppController controller;
  final String id;
  @override
  State<JobDetail> createState() => _JobDetailState();
}

class _JobDetailState extends State<JobDetail> {
  late Future<Job> future;
  bool accepting = false;

  Future<void> confirmAccept(Job job) async {
    final confirmed = await confirmJobDialog(context, job);
    if (confirmed != true || !mounted || accepting) {
      return;
    }
    final token = widget.controller.token;
    if (token == null) {
      return;
    }
    setState(() => accepting = true);
    try {
      await widget.controller.api.acceptJob(
        token,
        job.id,
        workerId: PlusApi.workerIdFromSession(token),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agendamento confirmado pelo iWof.')),
      );
      Navigator.of(context).pop();
      unawaited(widget.controller.refresh());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O iWof não confirmou o agendamento. Verifique '
                'a Agenda antes de tentar novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => accepting = false);
      }
    }
  }
  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<Job> load() async {
    final token = widget.controller.token;
    if (token == null) throw const SessionExpired();
    return widget.controller.api.detail(token, widget.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalhes da vaga')),
    body: FutureBuilder<Job>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppController.cleanError(snapshot.error!),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() => future = load()),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final job = snapshot.data!;
        Widget block(String title, String text) => text.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      text,
                      style: const TextStyle(color: muted, height: 1.6),
                    ),
                  ],
                ),
              );
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              job.store,
              style: const TextStyle(color: pink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              job.title,
              style: const TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFFFCE8F2),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.valueLabel,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: pink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(job.dateLabel),
                    if (job.finish != null)
                      Text(
                        'Término: ${job.finish!.hour.toString().padLeft(2, '0')}:${job.finish!.minute.toString().padLeft(2, '0')}',
                      ),
                    const SizedBox(height: 8),
                    Text(
                      job.totalValue == null
                          ? job.hourlyRateLabel
                          : '${job.hourlyRateLabel} × ${job.workedHours} h − comissão do iWof',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: accepting ? null : () => confirmAccept(job),
              icon: accepting
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Aceitar esta vaga'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  const channel = MethodChannel('br.com.iwofplus.iwof_plus/share');
                  await channel.invokeMethod<void>('shareText', {'text': job.shareText});
                } catch (_) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não foi possível abrir o compartilhamento.')));
                }
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartilhar vaga'),
            ),
            block('Sobre a oportunidade', job.description),
            block('Endereço', job.address),
            block('Apresentação', job.meetingPoint),
            block('Vestimenta e orientações', job.epi),
            const SizedBox(height: 30),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final opened = await launchUrl(
                  Uri.parse(
                    'https://iwof.com.br/job/${Uri.encodeComponent(job.id)}',
                  ),
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Não foi possível abrir a vaga.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir no iWof'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await widget.controller.toggleSaved(job);
                if (mounted) setState(() {});
              },
              icon: Icon(
                widget.controller.saved.any((j) => j.id == job.id)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
              label: const Text('Guardar na minha lista'),
            ),
            const SizedBox(height: 18),
            const Text(
              'O botão Aceitar solicita o agendamento diretamente ao iWof. ' 
              'A confirmação depende do servidor e da disponibilidade.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        );
      },
    ),
  );
}
