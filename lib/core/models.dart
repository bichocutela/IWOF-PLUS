import 'package:intl/intl.dart';

String formatPhone(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  final number = digits.length == 13 && digits.startsWith('55')
      ? digits.substring(2)
      : digits;
  if (number.length != 11) {
    throw const FormatException('Informe o telefone com DDD e 11 dígitos.');
  }
  return '(${number.substring(0, 2)}) ${number.substring(2, 7)}-${number.substring(7)}';
}

String normalizeCity(String value) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'aaaaaeeeeiiiiooooouuuuc';
  var result = value.trim().toLowerCase();
  for (var i = 0; i < from.length; i++) {
    result = result.replaceAll(from[i], to[i]);
  }
  return result.replaceAll(RegExp(r'\s+'), ' ');
}

class Job {
  const Job({
    required this.id,
    required this.title,
    required this.store,
    required this.address,
    required this.start,
    required this.finish,
    this.image,
    this.value,
    this.percentage,
    this.description = '',
    this.epi = '',
    this.meetingPoint = '',
  });
  final String id, title, store, address, description, epi, meetingPoint;
  final String? image;
  /// Hourly rate from job_store.value.
  final double? value;
  final double? percentage;
  final DateTime? start, finish;

  int? get workedHours {
    if (start == null || finish == null) return null;
    final hours = finish!.difference(start!).inHours;
    return hours > 0 ? hours : 0;
  }

  /// Net shift value as calculated by the original iWof APK:
  /// hourly rate × whole hours × (1 − commission percentage).
  double? get totalValue {
    final hours = workedHours;
    if (value == null || hours == null) return null;
    final commission = percentage ?? 11.5;
    return value! * hours * (1 - commission / 100);
  }

  String get hourlyRateLabel => value == null
      ? 'Tarifa por hora não informada'
      : '${NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(value)} por hora';
  factory Job.fromJson(Map<String, dynamic> json) {
    final store = json['store'] as Map<String, dynamic>? ?? {};
    final details = json['job_store'] as Map<String, dynamic>? ?? {};
    DateTime? date(dynamic value) =>
        value == null ? null : DateTime.tryParse('$value');
    return Job(
      id: '${json['id'] ?? ''}',
      title: '${json['job']?['name'] ?? 'Oportunidade'}'.trim(),
      store: '${store['name'] ?? 'Empresa'}',
      address: '${store['address'] ?? ''}',
      image: store['image'] as String? ?? store['company']?['image'] as String?,
      value: (details['value'] as num?)?.toDouble(),
      percentage: (details['percentage'] as num?)?.toDouble(),
      start: date(json['start_at']),
      finish: date(json['finish_at']),
      description: '${details['description'] ?? ''}',
      epi: '${details['epi'] ?? ''}',
      meetingPoint: '${details['look_for'] ?? ''}',
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'job': {'name': title},
    'store': {'name': store, 'address': address, 'image': image},
    'job_store': {
      'value': value,
      'percentage': percentage,
      'description': description,
      'epi': epi,
      'look_for': meetingPoint,
    },
    'start_at': start?.toIso8601String(),
    'finish_at': finish?.toIso8601String(),
  };
  String get dateLabel => start == null
      ? 'Data a confirmar'
      : DateFormat('dd/MM • HH:mm').format(start!);
  String get valueLabel => totalValue == null
      ? (value == null ? 'Valor não informado' : hourlyRateLabel)
      : NumberFormat.currency(locale: 'pt_BR', symbol: r'R$').format(totalValue);
}

class JobPage {
  const JobPage(this.total, this.jobs);
  final int total;
  final List<Job> jobs;
}

class SessionExpired implements Exception {
  const SessionExpired();
  @override
  String toString() => 'Sua sessão expirou. Entre novamente para continuar.';
}
