# IWOF PLUS — Roteiro de expansão

**0.2.1:** assinatura Android definitiva, GitHub Releases, atualização pelo app.

**0.3.0:** Vagas/Salvas/Avisos preservados; aba Trabalhos: Agenda e Histórico.

**0.4.0:** Central PLUS em Perfil: Carteira e Extrato, Situação cadastral e Elegibilidade, Cursos, Vídeos, Questões sem gabarito, Histórico de avaliações. Somente leitura, consultas sob demanda.

## Ações protegidas ainda sem liberação

Aceitação/cancelamento de trabalho, solicitação de saque, envio de documentos, atualização de dados bancários, envio de provas, redefinição de senha, alteração de perfil, exclusão de conta e cadastro. A presença de mutações no APK original não prova a autorização ou segurança de seu uso em aplicativo independente. Precisamos validar efeitos da API, autorização real, confirmação do usuário e comportamento de repetição antes de executar essas ações.

## Regras

Preservar 5 abas principais, manter assinatura permanente e versionCode crescente; testes Flutter/Python, build Android e release verde; consultas sem dados sensíveis desnecessários e sem persistência local; tratar ID do profissional apenas se presente de forma explícita no token; não confundir mocks automatizados com validação real no dispositivo.


**0.5.0:** filtro de extrato por situação, carregamento resiliente de cursos, assinatura GraphQL de cursos alinhada ao APK original e checklist manual com relatório sem dados sensíveis. Validação real depende de abrir as telas em um celular com a conta do titular. Não habilitar mutações sem testar efeitos e permissões.

**0.6.0 — Diagnóstico automático:** usuário dispara consultas em sua sessão, sem mutations, com relatório de status anônimo. Acompanhado de testes com MockClient. Não equiparar execução verde no CI a validação contratual em produção.
