# Habilitações reais por profissional — investigação de origem

## Objetivo
Mostrar **somente** funções habilitadas pelo servidor do iWof para a conta autenticada. Não confundir catálogo de funções, preferências, experiências, cursos realizados, aprovação cadastral ou possibilidade geral de agendar com habilitação para uma função específica.

## Evidências disponíveis
- O APK original legado **1.1.77** foi analisado anteriormente. A pista recuperada para o perfil é `worker.jobs { id name hash image }`. Não há ainda nesta sessão o arquivo APK 1.1.77 nem uma captura de rede da tela correspondente para revalidar a interpretação.
- O original **2.3.14** usa React Native/Hermes e o endpoint GraphQL de produção; sua auditoria estática identificou `Worker`, `getWorkerRegisterStatus` e `getWorkerSchedulingCompliance`, mas **não** uma operação inequívoca que declare aprovação individual por função.
- No PLUS, a consulta antiga `worker(id: $id) { id jobs { id name } }` **não traz flag de aprovação por função**. Mesmo que use o ID da sessão, uma lista retornada não é prova suficiente de habilitação.
- `getWorkerSchedulingCompliance.canAcceptNewSchedules` é informação geral de agendamento e `missingDocuments` sinaliza pendências documentais; nenhuma delas substitui autorização **por função**.
- O próprio serviço oficial diferencia aprovação de conta e habilitação necessária para aceitar vagas. Exemplos públicos:
  - https://www.reclameaqui.com.br/iwof/quero-trabalhar-e-iwof-demora_lffPgav9o6Js4jNn/
  - https://www.reclameaqui.com.br/iwof/dificuldade-no-agendamento-de-vagas-e-problemas-de-acesso-apos-treinamentos_O1mSMgUheZAVsNqR/

## Alteração defensiva deste PR
- Na conta, não mostrar `worker.jobs` como habilitações confirmadas.
- Conservar leitura apenas para diagnóstico técnico **sem gravar, exibir ou copiar** funções, identificadores de usuários e credenciais.
- Validar `worker.id` retornado contra o ID extraído da sessão; resposta de outra conta é inválida.
- Reportar separadamente: (a) acesso à origem `worker.jobs`, (b) habilitação individual **NÃO CONFIRMADA**.
- Preservar consulta de vagas, aceitar/agendar e outras funções do aplicativo sem alteração.

## Validação necessária antes de mostrar habilitações reais
1. Recuperar o **arquivo original** `br.com.iwof` versão 1.1.77 ou uma captura de tráfego autenticado da tela de habilitações do próprio titular, sem tokens/senhas.
2. Rastrear evento de navegação, função chamada, documento GraphQL exato e parser que alimenta essa tela. Distinguir leitura de lista geral `jobs` e de vínculo trabalhador-função.
3. Confirmar, com respostas de teste de contas autorizadas e dados mascarados, que duas contas distintas retornam conjuntos específicos corretos. Identificar tipo de vínculo/estado de aprovação sem adivinhar.
4. Implementar parser tipado e guardas de identidade/filtros reais. Não usar experiência profissional ou curso concluído para inferir habilitação.
5. Conferir no celular que funções exibidas no PLUS correspondem uma a uma ao aplicativo oficial; o servidor mantém a decisão final ao aceitar vaga.

**Estado:** consulta fonte `worker.jobs` conhecida; **regra de habilitação individual não comprovada**. Não classificar o PR como integração concluída até validação real.
