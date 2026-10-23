/// Cuándo avisar de las facturas pendientes. Se guarda en el teléfono.
class ConfigRecordatorios {
  const ConfigRecordatorios({
    this.hora = 9,
    this.minuto = 0,
    this.diasAntes = const {1, 0},
    this.insistirVencidas = false,
  });

  /// Opciones que se ofrecen en Ajustes (0 = el día del vencimiento).
  static const opcionesDias = [0, 1, 2, 3, 5, 7, 15];

  /// Días seguidos que se sigue avisando de una factura vencida.
  static const diasInsistiendo = 7;

  final int hora;
  final int minuto;

  /// Cuántos días antes del vencimiento avisar (0 = el mismo día).
  final Set<int> diasAntes;

  /// Seguir avisando cada día mientras la factura siga vencida.
  final bool insistirVencidas;

  /// La hora del aviso como fecha de hoy (para formatearla).
  DateTime get comoFecha {
    final hoy = DateTime.now();
    return DateTime(hoy.year, hoy.month, hoy.day, hora, minuto);
  }

  ConfigRecordatorios copyWith({
    int? hora,
    int? minuto,
    Set<int>? diasAntes,
    bool? insistirVencidas,
  }) {
    return ConfigRecordatorios(
      hora: hora ?? this.hora,
      minuto: minuto ?? this.minuto,
      diasAntes: diasAntes ?? this.diasAntes,
      insistirVencidas: insistirVencidas ?? this.insistirVencidas,
    );
  }

  /// "El mismo día, 1 y 3 días antes".
  String get descripcionDias {
    if (diasAntes.isEmpty && !insistirVencidas) return 'Sin avisos';

    final ordenados = diasAntes.toList()..sort();
    final partes = <String>[if (ordenados.contains(0)) 'el mismo día'];
    final antes = ordenados.where((d) => d > 0).toList();
    if (antes.length == 1 && antes.single == 1) {
      partes.add('el día antes');
    } else if (antes.isNotEmpty) {
      final numeros = antes.map((d) => '$d').toList();
      final lista = numeros.length == 1
          ? numeros.single
          : '${numeros.sublist(0, numeros.length - 1).join(', ')} y ${numeros.last}';
      partes.add('$lista día${antes.last == 1 ? '' : 's'} antes');
    }
    if (insistirVencidas) partes.add('a diario si se vence');

    final texto = partes.join(', ');
    return texto[0].toUpperCase() + texto.substring(1);
  }

  Map<String, dynamic> toJson() => {
    'hora': hora,
    'minuto': minuto,
    'diasAntes': diasAntes.toList()..sort(),
    'insistirVencidas': insistirVencidas,
  };

  factory ConfigRecordatorios.fromJson(Map<String, dynamic> json) {
    return ConfigRecordatorios(
      hora: (json['hora'] as int? ?? 9).clamp(0, 23),
      minuto: (json['minuto'] as int? ?? 0).clamp(0, 59),
      diasAntes: {
        ...(json['diasAntes'] as List? ?? [1, 0]).cast<int>(),
      },
      insistirVencidas: json['insistirVencidas'] as bool? ?? false,
    );
  }
}
