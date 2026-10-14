# Ativar notificações remotas

O APK atual funciona com monitoramento no aparelho. O envio remoto só fica ativo após concluir as etapas abaixo e gerar um APK com a configuração do seu projeto Firebase.

## 1. Firebase

Crie um projeto próprio e registre o aplicativo Android `br.com.iwofplus.iwof_plus`. Ative a API Firebase Cloud Messaging. Anote os identificadores públicos do aplicativo: API key, app ID, project ID e sender ID.

Crie uma conta de serviço com permissão para enviar mensagens FCM. Guarde o JSON privado somente como segredo do servidor. Não use credenciais do projeto original iWof e não envie esse JSON para issues ou commits.

## 2. Servidor Render

O arquivo `render.yaml` prepara um serviço Docker com uma instância, região Virginia e disco persistente de 1 GB. **Esse serviço exige plano pago. Confira e aprove o custo mostrado pelo Render antes de criar o Blueprint.** Nenhum serviço é criado apenas por publicar este arquivo no GitHub.

Importe o repositório como Blueprint e preencha `FIREBASE_SERVICE_ACCOUNT_JSON` com o JSON completo da conta de serviço. A chave `TOKEN_ENCRYPTION_KEY` é gerada pelo host. Preserve essa chave e o disco: trocar a chave impede a leitura das sessões já registradas. Não escale para várias instâncias; o banco SQLite e o agendador dependem de um único processo.

A implantação automática está desligada. Depois de criar o serviço, alterações futuras precisam de implantação manual. Confira no log de inicialização se o usuário do container tem acesso de escrita ao disco `/data`; isso ainda requer validação no serviço hospedado.

Use a URL HTTPS fornecida pelo Render. Consulte `/health`: deve retornar `ok: true` e `push_ready: true`. Esse estado indica que o Firebase foi inicializado; a entrega de uma mensagem ainda precisa ser testada no telefone.

## 3. APK conectado ao servidor

Configure estas Repository Variables no GitHub e execute o workflow Android:

| Variável | Valor |
|---|---|
| MONITOR_URL | URL HTTPS do seu servidor, sem `/health` |
| FIREBASE_API_KEY | API key pública do seu aplicativo Firebase |
| FIREBASE_APP_ID | App ID Android do seu aplicativo Firebase |
| FIREBASE_PROJECT_ID | ID do seu projeto Firebase |
| FIREBASE_SENDER_ID | Número do projeto / messaging sender ID |

A conta de serviço e a chave de criptografia **não** são variáveis do APK. Para atualizações distribuídas, configure também uma assinatura Android permanente conforme o README; o APK de teste usa assinatura de desenvolvimento.

## 4. Verificação no telefone

Instale o APK configurado, entre com sua conta iWof, conceda as permissões de localização e notificações e habilite os avisos. A primeira leitura da região é silenciosa. Uma vaga nova na região deve gerar um aviso após a próxima consulta do servidor, cujo intervalo mínimo é 15 minutos.

Confirme também a mudança de cidade: após a nova região ser confirmada pelo GPS, o servidor deve receber a região atual e criar uma nova base silenciosa. Avisos antigos de outra região não devem aparecer. Verifique o funcionamento com a tela bloqueada e com o aplicativo fechado normalmente.

Se a sessão expirar, entre novamente. Ao forçar a parada do aplicativo, o Android pode bloquear a entrega de mensagens até reabri-lo. Não confunda fechamento normal com force-stop.

## Referências

- https://render.com/docs/blueprint-spec
- https://render.com/docs/disks
- https://render.com/docs/configure-environment-variables
