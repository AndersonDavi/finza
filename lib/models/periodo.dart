import '../utils/fechas.dart';
import '../utils/formato.dart';

enum TipoPeriodo { mes, anio, rangoMeses, rangoFechas, total }

const nombresMeses = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// Periodo de tiempo que muestran Inicio y Estadísticas: un mes, un año, un
/// rango de meses, un rango de fechas o todo el historial.
///
/// Se guarda como [inicio, fin): [fin] es el primer instante que ya no entra.
class Periodo {
  const Periodo._(this.tipo, this.inicio, this.fin);

  final TipoPeriodo tipo;
  final DateTime? inicio;
  final DateTime? fin;

  factory Periodo.mes(int anio, int mes) =>
      Periodo._(TipoPeriodo.mes, DateTime(anio, mes), DateTime(anio, mes + 1));

  factory Periodo.mesActual({DateTime? hoy}) {
    final ahora = hoy ?? DateTime.now();
    return Periodo.mes(ahora.year, ahora.month);
  }

  factory Periodo.anio(int anio) =>
      Periodo._(TipoPeriodo.anio, DateTime(anio), DateTime(anio + 1));

  /// De [desde] a [hasta], los dos meses completos incluidos.
  factory Periodo.rangoMeses(DateTime desde, DateTime hasta) {
    if (hasta.isBefore(desde)) (desde, hasta) = (hasta, desde);
    return Periodo._(
      TipoPeriodo.rangoMeses,
      DateTime(desde.year, desde.month),
      DateTime(hasta.year, hasta.month + 1),
    );
  }

  /// De [desde] a [hasta], los dos días completos incluidos.
  factory Periodo.rangoFechas(DateTime desde, DateTime hasta) {
    if (hasta.isBefore(desde)) (desde, hasta) = (hasta, desde);
    final fin = soloFecha(hasta);
    return Periodo._(
      TipoPeriodo.rangoFechas,
      soloFecha(desde),
      DateTime(fin.year, fin.month, fin.day + 1),
    );
  }

  static const total = Periodo._(TipoPeriodo.total, null, null);

  bool contiene(DateTime fecha) =>
      tipo == TipoPeriodo.total ||
      (!fecha.isBefore(inicio!) && fecha.isBefore(fin!));

  /// Último día incluido (para mostrarlo o para filtrar Movimientos).
  DateTime? get ultimoDia =>
      fin == null ? null : DateTime(fin!.year, fin!.month, fin!.day - 1);

  int get _meses =>
      (fin!.year - inicio!.year) * 12 + fin!.month - inicio!.month;

  int get _dias => DateTime.utc(
    fin!.year,
    fin!.month,
    fin!.day,
  ).difference(DateTime.utc(inicio!.year, inicio!.month, inicio!.day)).inDays;

  /// El periodo de la misma duración inmediatamente antes (o después, con
  /// [pasos] positivo). Para comparar y para las flechas ‹ ›.
  Periodo desplazar(int pasos) {
    switch (tipo) {
      case TipoPeriodo.total:
        return this;
      case TipoPeriodo.mes:
        return Periodo.mes(inicio!.year, inicio!.month + pasos);
      case TipoPeriodo.anio:
        return Periodo.anio(inicio!.year + pasos);
      case TipoPeriodo.rangoMeses:
        final meses = _meses * pasos;
        return Periodo._(
          tipo,
          DateTime(inicio!.year, inicio!.month + meses),
          DateTime(fin!.year, fin!.month + meses),
        );
      case TipoPeriodo.rangoFechas:
        final dias = _dias * pasos;
        return Periodo._(
          tipo,
          DateTime(inicio!.year, inicio!.month, inicio!.day + dias),
          DateTime(fin!.year, fin!.month, fin!.day + dias),
        );
    }
  }

  Periodo get anterior => desplazar(-1);
  Periodo get siguiente => desplazar(1);

  /// Nombre para mostrar: `Octubre 2026`, `2026`, `Ago – Oct 2026`…
  String get etiqueta {
    switch (tipo) {
      case TipoPeriodo.total:
        return 'Todo el historial';
      case TipoPeriodo.mes:
        return '${nombresMeses[inicio!.month - 1]} ${inicio!.year}';
      case TipoPeriodo.anio:
        return '${inicio!.year}';
      case TipoPeriodo.rangoMeses:
        final ultimo = ultimoDia!;
        String corto(DateTime f) => nombresMeses[f.month - 1].substring(0, 3);
        if (inicio!.year == ultimo.year) {
          if (inicio!.month == ultimo.month) {
            return '${nombresMeses[ultimo.month - 1]} ${ultimo.year}';
          }
          return '${corto(inicio!)} – ${corto(ultimo)} ${ultimo.year}';
        }
        return '${corto(inicio!)} ${inicio!.year} – '
            '${corto(ultimo)} ${ultimo.year}';
      case TipoPeriodo.rangoFechas:
        final ultimo = ultimoDia!;
        if (ultimo == inicio) return formatearFecha(ultimo);
        return '${formatearFecha(inicio!)} – ${formatearFecha(ultimo)}';
    }
  }

  /// Para frases como "Balance de octubre" o "Balance del periodo".
  String get nombreCorto {
    switch (tipo) {
      case TipoPeriodo.mes:
        return 'de ${nombresMeses[inicio!.month - 1].toLowerCase()}';
      case TipoPeriodo.anio:
        return 'de ${inicio!.year}';
      case TipoPeriodo.total:
        return 'total';
      case TipoPeriodo.rangoMeses:
      case TipoPeriodo.rangoFechas:
        return 'del periodo';
    }
  }

  /// Los meses y años se guardan como "el actual" (al abrir la app al mes
  /// siguiente se ve el mes nuevo); los rangos, con sus fechas exactas.
  Map<String, dynamic> toJson() => {
    'tipo': tipo.name,
    'inicio': inicio?.toIso8601String(),
    'fin': fin?.toIso8601String(),
  };

  factory Periodo.fromJson(Map<String, dynamic> json, {DateTime? hoy}) {
    final ahora = hoy ?? DateTime.now();
    final tipo = TipoPeriodo.values.asNameMap()[json['tipo']];

    switch (tipo) {
      case TipoPeriodo.total:
        return Periodo.total;
      case TipoPeriodo.anio:
        return Periodo.anio(ahora.year);
      case TipoPeriodo.rangoMeses:
      case TipoPeriodo.rangoFechas:
        final inicio = DateTime.tryParse(json['inicio'] as String? ?? '');
        final fin = DateTime.tryParse(json['fin'] as String? ?? '');
        if (inicio == null || fin == null || !fin.isAfter(inicio)) break;
        return Periodo._(tipo!, inicio, fin);
      case TipoPeriodo.mes:
      case null:
        break;
    }
    return Periodo.mesActual(hoy: ahora);
  }

  @override
  bool operator ==(Object other) =>
      other is Periodo &&
      other.tipo == tipo &&
      other.inicio == inicio &&
      other.fin == fin;

  @override
  int get hashCode => Object.hash(tipo, inicio, fin);
}
