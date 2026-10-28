# IWOF PLUS

Cliente Android independente em Flutter para consultar vagas do iWof com a conta do usuário e acompanhar novidades por região. Visual inspirado no original: rosa `#D93F8F`, fonte Manrope, fundo claro e cartões arredondados.

## Implementado

- Login reproduzindo o formato telefônico do aplicativo original; senha não persistida.
- Token em armazenamento protegido Android, backup do app desativado e rede somente HTTPS.
- Vagas reais, paginação, busca por função/empresa, filtros de função e cidade, imagens e detalhes.
- GPS identifica a cidade; registro da última região, fallback manual e confirmação de mudança por dois minutos.
- Acompanhamento opcional em segundo plano por localização, indicado em notificação persistente.
- Vagas salvas e histórico local de avisos.
- Monitor local com WorkManager: primeira sincronização silenciosa, deduplicação por ID e descarte de respostas de regiões anteriores.
- Serviço Python com snapshots completos por região, sessão criptografada, fila persistente de envio e Firebase Cloud Messaging opcional.
- CI com análise Flutter, testes e APK instalável de teste nos artefatos de Actions.

## Executar

Flutter 3.35.4 / Dart 3.9.2, Java 17, Android SDK 36. Android mínimo 7 (API 24).

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

O APK de teste é gerado após push em `main`, em **Actions → Flutter Android → Artifacts → IWOF-PLUS-android-test**. O APK é otimizado em modo release para aparelhos ARM64 (como o Redmi Note 13 Pro 5G), mas o build inicial usa assinatura de debug, destinada a testes. Antes de distribuição/atualizações definitivas, configure uma chave de release persistente em Secrets; não publique um keystore privado no repositório.

## Região e notificações

Ao registrar a primeira região, o app solicita permissão para notificações e inicia o acompanhamento se autorizado. A escolha pode ser alterada no Perfil. A lista de cidades é carregada do serviço; o GPS também pode consultar uma cidade que não esteja nessa lista. O monitor acompanha a região atual. Trocar cidade cria uma referência silenciosa das vagas existentes; somente novidades posteriores geram avisos. IDs já vistos são preservados para evitar repetição ao reaparecer uma vaga.

No Android, WorkManager executa a partir de 15 minutos, sem garantia de horário exato: bateria, rede e restrições do fabricante podem adiar. Com o app visível, há verificações a cada dois minutos. GPS usa precisão balanceada e distância mínima de 1 km; a confirmação periódica também permite reconhecer a nova cidade após parar de se deslocar. A permissão de localização em segundo plano é opcional, apresentada no Perfil e concedida pelo usuário nas configurações do Android. Sem essa permissão o app acompanha a localização enquanto está em uso e mantém a última região quando fechado.

Forçar a parada do app suspende as tarefas Android até reabrir. Avisos pelo servidor continuam para a última região registrada, desde que o serviço esteja ativo, o push configurado e a sessão válida. Não há promessa de rastreamento contínuo após force-stop.

## Push independente do app aberto

O cliente funciona com monitor local sem Firebase configurado. Para ativar o envio por servidor:

1. Hospede `server/` como processo persistente atrás de HTTPS, com volume permanente `/data` e **um único worker**. SQLite e o scheduler incluído não são adequados a instâncias serverless efêmeras ou múltiplas réplicas.
2. Gere `TOKEN_ENCRYPTION_KEY` (Fernet) e monte uma conta de serviço Firebase fora do repositório em `GOOGLE_APPLICATION_CREDENTIALS`. Preserve a chave de criptografia entre reinícios.
3. Cadastre o app Android `br.com.iwofplus.iwof_plus` em seu projeto Firebase.
4. Configure as Repository Variables `MONITOR_URL`, `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_SENDER_ID` e gere outro APK.

Esses identificadores Firebase de cliente são configuração pública. A chave privada da conta de serviço permanece somente no servidor; senha iWof não é enviada a ele. O servidor recebe a sessão após autenticação, valida-a no serviço de vagas e a armazena criptografada. Registra somente cidade e token de push, sem coordenadas GPS.

```bash
cd server
pip install -r requirements.txt
# configure as variáveis de server/.env.example no ambiente
uvicorn app:app --host 0.0.0.0 --port 8080 --workers 1 --no-access-log
```

`GET /health` informa `push_ready`; `/devices` registra/atualiza região e sessão. Cada instalação recebe segredo próprio para atualizações, consulta de status e remoção. APIs administrativas e documentação pública estão desativadas. Proteja o proxy HTTPS com limite de requisições e use volumes protegidos para banco e credenciais. O intervalo mínimo do servidor é 900 segundos; não acelere chamadas sem conhecer os limites do iWof.

**O serviço e as credenciais Firebase ainda precisam ser provisionados.** Incluir o código no repositório não significa que o push remoto já esteja funcionando. A interface informa quando opera por monitoramento no aparelho.

## Testes

```bash
flutter test
PYTHONPATH=server python -m pytest server/tests -q
```

Cobertura de comportamento: formato do login, paginação completa, falha em respostas incompletas, sessão expirada, imprecisão do GPS, confirmação de cidade, referência inicial silenciosa, deduplicação e rejeição de respostas antigas. A entrega de push, GPS real e restrições de bateria precisam ser testados em dispositivo.

## Integração

O contrato foi encontrado no APK 2.3.14 e a leitura autenticada de vagas foi validada durante o desenvolvimento. A API não tem garantia de compatibilidade; pode mudar ou impor limites. Este projeto não agenda trabalho, aceita vagas, efetua saques ou altera dados da conta. O botão de agendamento abre o serviço original.

Não adicione senhas, tokens, documentos pessoais, capturas de conta, bancos locais ou credenciais de infraestrutura a este repositório público. Sem vínculo oficial com o iWof. Manrope é distribuída sob SIL Open Font License, incluída em `assets/fonts/OFL.txt`.

## Implantação preparada

Consulte [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) para configurar Firebase, o Blueprint Render e validar o push no telefone. O arquivo `render.yaml` requer um serviço pago com disco persistente; nenhuma infraestrutura foi criada automaticamente.


## Atualização pelo aplicativo (a partir de 0.2.0)

Em **Perfil → Sobre o IWOF PLUS**: conferir versão instalada, consultar GitHub Releases, baixar o APK e solicitar a instalação pelo sistema Android. O APK é verificado pelo SHA-256 publicado pelo GitHub antes de abrir o instalador; o usuário confirma a instalação. O botão funciona com releases publicadas do repositório oficial.

Uma release só é publicada quando configurados os quatro segredos de Actions: `ANDROID_KEYSTORE_BASE64` (keystore JKS em base64), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Guarde a chave fora do repositório, em local privado e com backup. A assinatura permanente precisa continuar a mesma para permitir instalação por cima das versões futuras. Aumente a versão e build number em `pubspec.yaml` para cada publicação. Sem esses segredos, o Actions gera apenas um artefato APK de teste assinado com a chave debug efêmera; não publica uma release potencialmente incompatível.

O identificador Android é preservado (`br.com.iwofplus.iwof_plus`), mas os APKs antigos assinados com chaves debug diferentes **não podem ser atualizados por cima** de APKs com nova assinatura. Nesse caso é necessária uma desinstalação única após confirmar a recuperação de login e dados. Depois da migração, mantenha a mesma chave definitiva em todas as versões.


## Meus trabalhos (v0.3.0)

A aba **Trabalhos** apresenta **Agenda** (agendado, aguardando liberação e em andamento) e **Histórico** (em revisão, finalizado e cancelado). Os dados vêm de duas consultas GraphQL encontradas no aplicativo original iWof 2.3.14. Exibe horários, empresa, situação, valor previsto e, no histórico, o valor efetivamente pago de forma independente. Não aceita, cancela, agenda ou saca dinheiro.

O carregamento acontece quando a aba é aberta, com atualização manual por gesto; os dados são mantidos somente em memória durante a sessão. A API de terceiros pode mudar ou bloquear a leitura: testes automatizados validam contratos fictícios, mas as respostas reais ainda precisam ser conferidas com o titular no celular. Consulte docs/IMPLEMENTATION_ROADMAP.md para as próximas etapas.


## Central PLUS (0.4.0)

Em Perfil → Central PLUS: (1) Carteira/Extrato com saldo e movimentações separados; (2) Minha Conta com situação do cadastro, documentos e elegibilidade; (3) Cursos/Avaliações com catálogo paginado, vídeos, questões de estudo sem gabarito e histórico de tentativas. As consultas são realizadas sob demanda, somente leitura. Nenhuma mutação de pagamento, cancelamento, documentos, prova, login ou conta é executada. A sessão só é usada para dados pessoais se contiver identificador explícito do trabalhador. Ver docs/API_INVENTORY.md.


## v0.5.0 — Validação assistida

Em **Perfil → Central PLUS → Validar integrações**, um checklist local permite conferir Vagas, Agenda, Histórico, Carteira, Extrato, Cadastro, Elegibilidade, Cursos, Vídeos, Avaliações e Atualização comparando com o aplicativo original. O relatório copiado contém **somente os estados escolhidos pelo próprio usuário**, sem credenciais ou dados pessoais. Isso não substitui um teste de resposta real da API, mas organiza as verificações e os erros encontrados no celular. O extrato também permite filtrar pelo status informado pelo servidor, e a lista de cursos não é apagada quando uma atualização falha. A consulta paginada de cursos usa a assinatura exata do GraphQL original, com argumento `filter` opcional. A assinatura permanente permanece inalterada.


## v0.6.0 — Diagnóstico automático de leitura

Em Perfil → Central PLUS → Diagnóstico automático, o usuário inicia explicitamente uma bateria de consultas **somente leitura** de cidades, agenda, histórico, cursos, vídeos, questões, perfil, extrato, cadastro e elegibilidade. O serviço exibe exclusivamente o resultado funcional por área: OK, FALHA ou NÃO TESTADO. Não copia valores de conta, tokens, IDs, respostas de conteúdo nem dados pessoais. Falhas não executam mutações nem alteram configurações, trabalhos ou dados financeiros. O relatório pode ser copiado para depurar uma API sem enviar informações confidenciais.


## Integração funcional das APIs

O inventário em `docs/API_INVENTORY.md` é documentação interna de desenvolvimento e **não deve aparecer como tela para o usuário**. As operações recuperadas do APK original devem se tornar funcionalidades nas telas correspondentes após confirmar argumentos, autorização, efeitos e respostas reais. Ações financeiras, exclusões e alterações de conta requerem validação e confirmação explícita antes da execução.


## 0.7.0 — Trabalhos com ações reais

A operação GraphQL original `AcceptRequest` é chamada **somente** depois de o usuário confirmar **Aceitar esta vaga** nos detalhes. A operação `DeleteRequest` é chamada **somente** após a confirmação de cancelamento em **Agenda**, quando o serviço informa `is_cancellable=true`. O aplicativo não agenda nem cancela automaticamente, não repete mutações quando há erro e não declara sucesso sem resposta positiva. O detalhe de serviços agora usa também a consulta `request(id)` para mostrar endereço e orientações dentro do app. Os contratos foram extraídos do APK iWof 2.3.14 e estão sujeitos à autorização e às regras do servidor original.


## 0.7.1 — Acessibilidade em telas pequenas

Detalhes de trabalhos usam lista rolável com limite de altura para exibir conteúdo longo. O seletor Agenda/Histórico aceita rolagem horizontal quando necessário, a seleção de cidades considera o teclado, e páginas de Perfil/Trabalhos recebem espaço inferior para alcançar os últimos itens. O layout mantém a navegação e as funções existentes.


## 0.8.0 — Estudo interativo e pesquisa de cursos

A área Cursos permite buscar entre os cursos já carregados e responder às perguntas do curso localmente, selecionando uma alternativa por questão e acompanhando quantas foram respondidas. É possível reiniciar o estudo. A funcionalidade não envia provas, não calcula aprovação nem consulta gabaritos; o backend é usado apenas para cursos, vídeos e questões de estudo. O estado das respostas permanece somente na tela.


## 0.8.1 — Gabarito de estudo sob demanda

Um botão **+ rosa** aparece ao lado de cada curso. Ao tocar, é feita uma consulta autenticada e somente leitura às questões do curso com `correct_answer` e alternativas, exibindo o gabarito em um balão rolável. A consulta não acontece ao listar cursos; não envia respostas, avaliações nem altera notas. Caso a API não forneça o gabarito, a tela informa a indisponibilidade.


## 0.9.0 — Avaliações oficiais

A interface envia uma avaliação ao servidor GraphQL do iWof via `CorrectWorkerTest` após confirmar as respostas. O retorno `approved` apresenta o resultado confirmado. Em caso de falha, não há retry automático. O formato dos objetos `CourseWorkerAnswer` ainda precisa ser validado ao vivo; a compilação por si só não comprova a aceitação do backend. A consulta do gabarito no + rosa permanece independente e somente leitura.


## 0.10.0 — Sincronização de avaliações

O envio oficial utiliza a mutação original `CorrectWorkerTest` e requer confirmação do usuário. As respostas incluem o identificador `questionId` (coerente com o histórico `answersObject` do APK original) e a posição `answer` recebida pela API; a posição zero é válida. O resultado só é exibido se o servidor retornar `approved` booleano. Ao retornar à lista, o PLUS recarrega os cursos. Em caso de erro de rede ou contrato, não reenvia automaticamente para evitar duplicidade. O contrato de entrada ainda necessita validação autenticada com o serviço real.
