import 'package:intl/intl.dart';

enum WorkKind { agenda, history }

class WorkItem {
  const WorkItem({
    required this.id,
    required this.title,
    required this.store,
    required this.status,
    required this.start,
    required this.finish,
    required this.estimatedValue,
    required this.paidValue,
    required this.isCancellable,
  });

  final String id, title, store, status;
  final DateTime? start, finish;
  final double? estimatedValue, paidValue;
  final bool isCancellable;

  static double? _amount(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static Map<String, dynamic> _object(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};

  factory WorkItem.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const FormatException('O serviço retornou um trabalho sem ID.');
    }
    final job = _object(json['job']);
    final store = _object(json['store']);
    final offer = _object(json['job_store']);
    final worker = _object(json['requestWorker']);
    final status = worker['status']?.toString() ??
        json['status']?.toString() ??
        'NÃO INFORMADO';
    return WorkItem(
      id: id,
      title: job['name']?.toString() ?? 'Trabalho',
      store: store['name']?.toString() ?? 'Empresa não informada',
      status: status,
      start: DateTime.tryParse(json['start_at']?.toString() ?? ''),
      finish: DateTime.tryParse(json['finish_at']?.toString() ?? ''),
      estimatedValue: _amount(offer['value']),
      paidValue: _amount(worker['paid_value']),
      isCancellable: json['is_cancellable'] == true,
    );
  }

  String get statusLabel {
    const labels = {
      'AGENDADO': 'Agendado',
      'AGUARDANDO LIBERAR': 'Aguardando liberação',
      'EM ANDAMENTO': 'Em andamento',
      'EM REVISÃO': 'Em revisão',
      'FINALIZADO': 'Finalizado',
      'CANCELADO': 'Cancelado',
    };
    return labels[status.toUpperCase()] ?? status;
  }

  String get dateLabel => start == null
      ? 'Data não informada'
      : DateFormat('dd/MM/yyyy • HH:mm').format(start!.toLocal());

  String get finishLabel => finish == null
      ? 'Horário não informado'
      : DateFormat('dd/MM/yyyy • HH:mm').format(finish!.toLocal());

  static String money(double? amount) => amount == null
      ? 'Não informado'
      : NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(amount);
}

class WorkCollection {
  const WorkCollection(this.total, this.items);
  final int total;
  final List<WorkItem> items;

  bool get mayBeIncomplete => total > items.length;
}
