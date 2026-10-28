# IWOF PLUS — roteiro de expansão

Versão estável de referência: 0.2.1, primeira release com assinatura permanente.

## Etapas independentes

1. v0.3.0 **Trabalhos, Agenda e Histórico**: implementado em código. Consultas originais workerRequests, com status, horários, valor previsto e valor efetivamente pago separados. Sem mutações.
2. Carteira e extrato: planejado. Consulta mínima de saldo, entradas, saídas e estados financeiros, sem guardar dados bancários.
3. Cadastro e elegibilidade: planejado. Situação dos documentos, pendências e autorização de agendar, com minimização de informações pessoais.
4. Cursos: planejado. Lista, vídeos, progresso e resultados, sem submissão de provas nesta fase.
5. Ações que modificam a conta (aceitar/cancelar serviços, perfil, saques): somente após validação autenticada e confirmação explícita dentro do app.

## Regras permanentes

- Preservar vagas, salvas, localização, monitor, notificações, login, configurações e acesso à tela Sobre.
- Toda versão nova deve aumentar versionName/versionCode, usar a mesma chave de release e passar nos testes de GitHub Actions.
- API original não é pública nem contratualmente garantida; o código foi recuperado do APK 2.3.14. Testes automatizados verificam mocks, não contas reais.
- A Agenda/Histórico só consultam quando a aba é aberta ou atualizada. O monitor automático de vagas não foi modificado.
- Valores previstos não são apresentados como valores pagos. Respostas incompletas não são tratadas como listas totalmente vazias.
- Credenciais, dados bancários e documentos não entram no repositório, na telemetria ou no cache do novo recurso.
- Falha de autenticação e ausência de rede devem ser tratadas sem apagar dados ou bloquear o restante do aplicativo.
