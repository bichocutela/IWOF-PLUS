import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _accent = Color(0xFFD93F8F);

/// Manual comparison with the original app, without collecting account data.
class IntegrationChecksScreen extends StatefulWidget {
  const IntegrationChecksScreen({super.key});

  @override
  State<IntegrationChecksScreen> createState() =>
      _IntegrationChecksScreenState();
}

class _IntegrationChecksScreenState extends State<IntegrationChecksScreen> {
  static const sections = <String, String>{
    'Vagas': 'Confira vagas, região e detalhes.',
    'Agenda': 'Confira os serviços agendados.',
    'Histórico': 'Confira os serviços finalizados e cancelados.',
    'Carteira': 'Compare o saldo mostrado no iWof original.',
    'Extrato': 'Compare as movimentações, datas e situações.',
    'Cadastro': 'Confira as seis etapas cadastrais.',
    'Elegibilidade': 'Confira pendências para aceitar serviços.',
    'Cursos': 'Confira a lista e o carregamento de mais páginas.',
    'Vídeos': 'Confira se os vídeos abrem corretamente.',
    'Avaliações': 'Confira o histórico e as questões de estudo.',
    'Atualização': 'Confira a atualização em Sobre o IWOF PLUS.',
  };

  final Map<String, String> results = {};

  String buildReport() {
    final lines = <String>[
      'IWOF PLUS - validação manual v0.5.0',
      'Sem dados pessoais ou informações de acesso.',
      for (final name in sections.keys)
        '$name: ${results[name] ?? 'NÃO TESTADO'}',
    ];
    return lines.join('\n');
  }

  Future<void> copyReport() async {
    await Clipboard.setData(ClipboardData(text: buildReport()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Relatório copiado sem dados pessoais.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Validar integrações')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Teste cada área no seu aparelho',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Compare as informações com o iWof original. '
          'Marque Funcionou ou Deu erro somente após testar cada tela. '
          'Esta lista não executa alterações na sua conta.',
          style: TextStyle(color: Color(0xFF64748B), height: 1.5),
        ),
        const SizedBox(height: 16),
        for (final section in sections.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.key,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      section.value,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final choice in const [
                          'NÃO TESTADO',
                          'FUNCIONOU',
                          'DEU ERRO',
                        ])
                          ChoiceChip(
                            label: Text(choice),
                            selected:
                                (results[section.key] ?? 'NÃO TESTADO') ==
                                    choice,
                            selectedColor: const Color(0xFFFCE8F2),
                            onSelected: (_) => setState(
                              () => results[section.key] = choice,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: copyReport,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copiar relatório dos testes'),
          style: FilledButton.styleFrom(backgroundColor: _accent),
        ),
        const SizedBox(height: 12),
        const Text(
          'Compartilhe somente o relatório. '
          'Não envie senhas, códigos de acesso, documentos ou saldos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
      ],
    ),
  );
}
