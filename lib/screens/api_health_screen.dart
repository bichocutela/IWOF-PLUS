import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_health.dart';
import '../services/iwof_api.dart';

class ApiHealthScreen extends StatefulWidget {
  const ApiHealthScreen({
    super.key,
    required this.api,
    required this.token,
  });
  final IwofApi api;
  final String token;

  @override
  State<ApiHealthScreen> createState() => _ApiHealthScreenState();
}

class _ApiHealthScreenState extends State<ApiHealthScreen> {
  final List<ApiHealthResult> results = [];
  bool running = false;

  Future<void> runChecks() async {
    if (running || widget.token.isEmpty) return;
    setState(() {
      running = true;
      results.clear();
    });
    try {
      await ApiHealth(widget.api).run(
        widget.token,
        onStep: (result) {
          if (mounted) setState(() => results.add(result));
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível concluir o diagnóstico.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Future<void> copy() async {
    await Clipboard.setData(
      ClipboardData(text: ApiHealth.report(results)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Resultados copiados sem dados pessoais.'),
      ),
    );
  }

  IconData iconFor(ApiHealthResult result) => switch (result.state) {
    'OK' => Icons.check_circle_outline_rounded,
    'FALHA' => Icons.error_outline_rounded,
    _ => Icons.help_outline_rounded,
  };

  Color colorFor(ApiHealthResult result) => switch (result.state) {
    'OK' => const Color(0xFF15803D),
    'FALHA' => const Color(0xFFB91C1C),
    _ => const Color(0xFF64748B),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diagnóstico de APIs')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Verificar consultas de leitura',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Este diagnóstico faz consultas autenticadas usando a sessão '
          'já aberta no aparelho. Não cria, edita, cancela, exclui ou '
          'movimenta nada. Respostas privadas nunca são copiadas.',
          style: TextStyle(color: Color(0xFF64748B), height: 1.5),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: running ? null : runChecks,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(running
              ? 'Verificando consultas...'
              : 'Executar diagnóstico'),
        ),
        if (running) ...[
          const SizedBox(height: 18),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 16),
        for (final entry in results)
          Card(
            child: ListTile(
              leading: Icon(iconFor(entry), color: colorFor(entry)),
              title: Text(entry.title),
              subtitle: Text(entry.detail),
              trailing: Text(
                entry.state,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colorFor(entry),
                ),
              ),
            ),
          ),
        if (!running && results.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: copy,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar resultado seguro'),
          ),
        ],
        const SizedBox(height: 18),
        const Text(
          'Uma consulta OK confirma resposta ao contrato neste momento, '
          'mas não garante que os dados coincidem com o app original. '
          'Compare-os também pelo checklist manual.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
      ],
    ),
  );
}
