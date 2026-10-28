import 'dart:async';
import 'dart:io';
import '../core/models.dart';
import 'iwof_api.dart';
import 'plus_api.dart';

class ApiHealthResult {
  const ApiHealthResult(this.title, this.state, this.detail);
  final String title, state, detail;
}

class ApiHealth {
  const ApiHealth(this.api);
  final IwofApi api;

  Future<List<ApiHealthResult>> run(String token,
      {void Function(ApiHealthResult)? onStep}) async {
    final output = <ApiHealthResult>[];
    final plus = PlusApi(api);
    final workerId = PlusApi.workerIdFromSession(token);
    String? courseId;

    void add(String name, String status, String detail) {
      final result = ApiHealthResult(name, status, detail);
      output.add(result);
      onStep?.call(result);
    }

    Future<bool> check(String name, Future<void> Function() request) async {
      try {
        await request();
        add(name, 'OK', 'Consulta respondeu');
        return true;
      } on SessionExpired {
        add(name, 'FALHA', 'Sessão expirada; faça login novamente');
        return false;
      } on TimeoutException {
        add(name, 'FALHA', 'Tempo de resposta esgotado');
        return false;
      } on SocketException {
        add(name, 'FALHA', 'Sem conexão com o servidor');
        return false;
      } on FormatException {
        add(name, 'FALHA', 'Formato de resposta incompatível');
        return false;
      } catch (_) {
        add(name, 'FALHA', 'Consulta indisponível ou não compatível');
        return false;
      }
    }

    await check('Cidades', () async {
      await api.cities(token);
    });
    await check('Agenda', () async {
      await api.workAgenda(token);
    });
    await check('Histórico', () async {
      await api.workHistory(token);
    });
    final hasCourses = await check('Cursos', () async {
      final page = await plus.courses(token);
      if (page.items.isNotEmpty) {
        courseId = page.items.first.id;
      }
    });
    if (hasCourses && courseId != null && courseId!.isNotEmpty) {
      await check('Vídeos', () async {
        await plus.videos(token, courseId!);
      });
      await check('Questões', () async {
        await plus.questions(token, courseId!);
      });
    } else {
      add('Vídeos', 'NÃO TESTADO', 'Nenhum curso disponível para testar');
      add('Questões', 'NÃO TESTADO', 'Nenhum curso disponível para testar');
    }

    if (workerId == null) {
      for (final name in [
        'Perfil básico',
        'Extrato',
        'Cadastro',
        'Elegibilidade',
      ]) {
        add(name, 'NÃO TESTADO', 'Identificador ausente na sessão');
      }
    } else {
      await check('Perfil básico', () async {
        await plus.worker(token, workerId);
      });
      await check('Extrato', () async {
        await plus.extract(token, workerId);
      });
      await check('Cadastro', () async {
        await plus.registration(token, workerId);
      });
      await check('Elegibilidade', () async {
        await plus.compliance(token, workerId);
      });
    }
    return output;
  }

  static String report(List<ApiHealthResult> results) {
    final lines = [
      'IWOF PLUS - diagnóstico automático de leitura',
      'Sem nomes, valores, identificadores ou credenciais',
      for (final row in results)
        '${row.title}: ${row.state} - ${row.detail}',
    ];
    return lines.join('\n');
  }
}
