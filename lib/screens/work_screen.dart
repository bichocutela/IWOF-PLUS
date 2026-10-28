import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/work_models.dart';
import '../services/iwof_api.dart';

const workPink = Color(0xFFD93F8F);
const workMuted = Color(0xFF64748B);

class WorkScreen extends StatefulWidget {
  const WorkScreen({
    super.key,
    required this.api,
    required this.sessionToken,
    required this.active,
  });

  final IwofApi api;
  final String sessionToken;
  final bool active;

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  int selected = 0;
  int sessionRevision = 0;
  final Map<int, WorkCollection> results = {};
  final Map<int, String> errors = {};
  final Set<int> loading = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) unawaited(load(0));
    });
  }

  @override
  void didUpdateWidget(covariant WorkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionToken != widget.sessionToken) {
      sessionRevision++;
      results.clear();
      errors.clear();
      loading.clear();
    }
    if (widget.active &&
        (!oldWidget.active ||
            oldWidget.sessionToken != widget.sessionToken)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !results.containsKey(selected)) {
          unawaited(load(selected));
        }
      });
    }
  }

  Future<void> load(int kind) async {
    if (loading.contains(kind) || widget.sessionToken.isEmpty) return;
    final revision = sessionRevision;
    final token = widget.sessionToken;
    setState(() {
      loading.add(kind);
      errors.remove(kind);
    });
    try {
      final data = kind == 0
          ? await widget.api.workAgenda(token)
          : await widget.api.workHistory(token);
      if (!mounted ||
          revision != sessionRevision ||
          widget.sessionToken != token) {
        return;
      }
      setState(() => results[kind] = data);
    } catch (error) {
      if (!mounted ||
          revision != sessionRevision ||
          widget.sessionToken != token) {
        return;
      }
      setState(() {
        errors[kind] = error is SessionExpired
            ? 'Sua sessão expirou. Entre novamente para consultar seus trabalhos.'
            : 'Não foi possível consultar os trabalhos. Tente atualizar.';
      });
    } finally {
      if (mounted && revision == sessionRevision) {
        setState(() => loading.remove(kind));
      }
    }
  }

  void choose(int kind) {
    if (selected == kind) return;
    setState(() => selected = kind);
    if (!results.containsKey(kind) && !loading.contains(kind)) {
      unawaited(load(kind));
    }
  }

  Future<void> confirmCancel(WorkItem item) async {
    if (!item.isCancellable || widget.sessionToken.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar este agendamento?'),
        content: const Text(
          'Essa ação altera o agendamento na sua conta do iWof. '
          'Confira os dados antes de confirmar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Manter trabalho'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar cancelamento'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.api.cancelWork(widget.sessionToken, item.id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cancelamento confirmado pelo iWof.')),
      );
      unawaited(load(0));
      unawaited(load(1));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O cancelamento não foi confirmado. Confira sua Agenda '
            'antes de repetir a solicitação.',
          ),
        ),
      );
    }
  }

  void showDetails(WorkItem item) {
    final details = widget.api.detail(widget.sessionToken, item.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20, 8, 20,
              MediaQuery.viewInsetsOf(context).bottom + 32,
            ),
            children: [
              Text(item.title,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(item.store, style: const TextStyle(color: workMuted)),
              const Divider(height: 28),
              _detailsLine('Situação', item.statusLabel),
              _detailsLine('Início', item.dateLabel),
              _detailsLine('Término', item.finishLabel),
              _detailsLine('Valor previsto', WorkItem.money(item.estimatedValue)),
              if (selected == 1)
                _detailsLine('Valor efetivamente pago',
                    WorkItem.money(item.paidValue)),
              if (selected == 0 && item.isCancellable)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'O iWof informa que este agendamento permite cancelamento. '
                    'A solicitação exige sua confirmação e aprovação do servidor.',
                    style: TextStyle(color: workMuted, fontSize: 12),
                  ),
                ),
              if (selected == 0 && item.isCancellable)
                OutlinedButton.icon(
                  onPressed: () => confirmCancel(item),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('Cancelar agendamento'),
                ),
              const SizedBox(height: 16),
              FutureBuilder<Job>(
                future: details,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData) {
                    return const Text(
                      'Detalhes adicionais não disponíveis no momento.',
                      style: TextStyle(color: workMuted),
                    );
                  }
                  final job = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (job.address.isNotEmpty)
                        _detailsLine('Endereço', job.address),
                      if (job.description.isNotEmpty)
                        _detailsLine('Descrição', job.description),
                      if (job.epi.isNotEmpty)
                        _detailsLine('Equipamentos', job.epi),
                      if (job.meetingPoint.isNotEmpty)
                        _detailsLine('Onde procurar', job.meetingPoint),
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

  Widget _detailsLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 125,
          child: Text(label, style: const TextStyle(color: workMuted)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  Widget _itemCard(WorkItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showDetails(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFFCE8F2),
                    child: Icon(Icons.work_outline_rounded, color: workPink),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(item.store,
                            style: const TextStyle(color: workMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: workMuted),
                ],
              ),
              const SizedBox(height: 12),
              Text(item.statusLabel,
                  style: const TextStyle(
                    color: workPink,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.event_outlined, size: 16, color: workMuted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(item.dateLabel)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Previsto: ${WorkItem.money(item.estimatedValue)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (selected == 1)
                Text('Pago: ${WorkItem.money(item.paidValue)}',
                    style: const TextStyle(color: workMuted)),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final collection = results[selected];
    final error = errors[selected];
    final busy = loading.contains(selected);
    final items = collection?.items ?? <WorkItem>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Meus trabalhos',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 4),
              const Text(
                'Agendamentos e serviços anteriores da sua conta.',
                style: TextStyle(color: workMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Agenda'),
                      icon: Icon(Icons.calendar_month_outlined),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Histórico'),
                      icon: Icon(Icons.history_rounded),
                    ),
                  ],
                  selected: {selected},
                  onSelectionChanged: (values) => choose(values.first),
                ),
              ),
            ],
          ),
        ),
        if (busy && collection == null)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => load(selected),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 64),
              children: [
                if (error != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(error,
                          style: const TextStyle(color: Color(0xFFB91C1C))),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: busy ? null : () => load(selected),
                    child: const Text('Tentar novamente'),
                  ),
                ],
                if (collection != null) ...[
                  if (collection.mayBeIncomplete) ...[
                    const Text(
                      'A lista retornada pode estar incompleta. Confira todos '
                      'os trabalhos no iWof original.',
                      style: TextStyle(color: workMuted),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          const Icon(Icons.event_note_rounded,
                              color: workMuted, size: 44),
                          const SizedBox(height: 14),
                          Text(
                            selected == 0
                                ? 'Nenhum trabalho na agenda'
                                : 'Nenhum trabalho no histórico',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Puxe para atualizar quando desejar.',
                            style: TextStyle(color: workMuted),
                          ),
                        ],
                      ),
                    ),
                  for (final item in items) _itemCard(item),
                ],
                if (!busy && collection == null && error == null)
                  const Center(child: Text('Abra a aba para consultar seus trabalhos.')),
                if (collection != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Consulta somente leitura. Agendamentos e cancelamentos '
                      'continuam no serviço original.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: workMuted, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
