import 'package:flutter/material.dart';

class ApiCatalogScreen extends StatelessWidget {
  const ApiCatalogScreen({super.key});

  static const categories = <String, List<String>>{
    'Trabalhos': ['workerRequestsNewApp', 'workerRequests', 'request(id)', 'AcceptRequest', 'DeleteRequest'],
    'Carteira e pagamentos': ['Worker.balance', 'getExtract', 'CreateWorkerBankInformation', 'RequestWithdraw'],
    'Cadastro e documentos': ['getWorkerRegisterStatus', 'getWorkerSchedulingCompliance', 'CreateSignupHandoff', 'CreateWorkerRegularInformationNewApp', 'CreateWorkerComplementaryInformation', 'SetWorkerRGImages', 'uploadFile'],
    'Perfil profissional': ['Worker', 'UpdateWorker', 'UpdateWorkerEmail', 'SetWorkerProfilePhoto', 'setWorkerProfileImage', 'CreateWorkerProfessionalExperience'],
    'Cursos e avaliações': ['Query (courses)', 'getCourseVideos', 'getCourseQuestions', 'CorrectWorkerTest'],
    'Acesso e segurança': ['LoginWorker', 'WorkerResetPassword', 'SendCodeToResetPasswordByPhone', 'SendVerification', 'VerifyEmail', 'DeleteWorkerApp'],
    'Regiões': ['citiesOperation'],
    'Biblioteca': ['IntrospectionQuery'],
  };

  static const integrated = <String>{
    'workerRequestsNewApp', 'workerRequests', 'request(id)',
    'Worker.balance', 'getExtract', 'getWorkerRegisterStatus',
    'getWorkerSchedulingCompliance', 'Worker', 'Query (courses)',
    'getCourseVideos', 'getCourseQuestions', 'LoginWorker', 'citiesOperation',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mapa de APIs do iWof')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Funcionalidades por área',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Inventário das operações identificadas no APK original. '
          'Integrada significa disponível em código, não validada na conta real. '
          'Funções que alteram dados permanecem protegidas.',
          style: TextStyle(color: Color(0xFF64748B), height: 1.5),
        ),
        const SizedBox(height: 16),
        for (final section in categories.entries)
          Card(
            child: ExpansionTile(
              title: Text(section.key),
              subtitle: Text('${section.value.length} operações'),
              children: [
                for (final name in section.value)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      integrated.contains(name)
                          ? Icons.check_circle_outline
                          : Icons.lock_outline,
                      color: integrated.contains(name)
                          ? const Color(0xFF15803D)
                          : const Color(0xFF64748B),
                    ),
                    title: Text(name),
                    subtitle: Text(integrated.contains(name)
                        ? 'Integrada • validação real pendente'
                        : 'Protegida ou apenas catalogada'),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Não são executadas operações financeiras ou alterações de conta '
          'a partir deste inventário.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
      ],
    ),
  );
}
