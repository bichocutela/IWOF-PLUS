# IWOF PLUS — Matriz de APIs do APK original 2.3.14

29 operações GraphQL nomeadas, incluindo uma operação de biblioteca. Leitura de código estática; APIs reais ainda dependem de testes no aparelho.

| Operação | Tipo | Área | Situação |
|---|---|---|---|
| `Worker` | Leitura | Minha Conta / Carteira / Avaliações | Integrada em 0.4.0 |
| `getCourseQuestions` | Leitura | Cursos | Integrada, sem gabarito |
| `SetWorkerRGImages` | Mutação | Documentos | Protegida |
| `DeleteRequest` | Mutação | Trabalhos | Protegida |
| `CorrectWorkerTest` | Mutação | Cursos | Protegida |
| `SetWorkerProfilePhoto` | Mutação | Perfil | Protegida |
| `CreateWorkerProfessionalExperience` | Mutação | Perfil | Protegida |
| `WorkerResetPassword` | Mutação | Acesso | Protegida |
| `CreateSignupHandoff` | Mutação | Cadastro | Protegida |
| `UpdateWorkerEmail` | Mutação | Perfil | Protegida |
| `CreateWorkerComplementaryInformation` | Mutação | Cadastro | Protegida |
| `Query (courses)` | Leitura | Cursos | Integrada em 0.4.0 |
| `uploadFile` | Mutação | Documentos | Protegida |
| `SendCodeToResetPasswordByPhone` | Mutação | Acesso | Protegida |
| `IntrospectionQuery` | Biblioteca | Infraestrutura | Não aplicável à interface |
| `getWorkerRegisterStatus` | Leitura | Minha Conta | Integrada em 0.4.0 |
| `getExtract` | Leitura | Carteira | Integrada em 0.4.0 |
| `CreateWorkerBankInformation` | Mutação | Carteira | Protegida |
| `DeleteWorkerApp` | Mutação | Conta | Protegida (destrutiva) |
| `AcceptRequest` | Mutação | Trabalhos | Protegida |
| `SendVerification` | Mutação | Acesso | Protegida |
| `VerifyEmail` | Mutação | Acesso | Protegida |
| `UpdateWorker` | Mutação | Perfil | Protegida |
| `CreateWorkerRegularInformationNewApp` | Mutação | Cadastro | Protegida |
| `LoginWorker` | Autenticação | Entrar | Integrada |
| `setWorkerProfileImage` | Mutação | Perfil | Protegida |
| `RequestWithdraw` | Mutação | Carteira | Protegida (financeira) |
| `getCourseVideos` | Leitura | Cursos | Integrada em 0.4.0 |
| `getWorkerSchedulingCompliance` | Leitura | Minha Conta | Integrada em 0.4.0 |

## Outras consultas encontradas

- workerRequestsNewApp: Vagas, implementada
- citiesOperation: cidades, implementada
- request(id): detalhes da vaga, implementada
- workerRequests: Agenda e Histórico, implementada em 0.3.0
- worker.balance e courseAttempts: Central PLUS, integrada em 0.4.0

## Regras

Integrada significa código + mocks; não significa que a API respondeu com sucesso em uma conta real. Mutações financeiras ou destrutivas precisam de validação com o titular e confirmação forte antes de disponibilização.

Não solicitar password, CPF, dados bancários ou gabaritos de avaliação. Não executar mutações de outras contas ou sem autorização. Guardar tokens apenas no secure storage existente.