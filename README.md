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
