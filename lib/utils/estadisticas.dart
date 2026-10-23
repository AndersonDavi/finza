import '../models/movimiento.dart';
import '../models/periodo.dart';

/// Totales de un periodo. Lo usan Inicio y Estadísticas.
class ResumenPeriodo {
  ResumenPeriodo._(this.ingresos, this.gastos, this.gastosPorCategoria);

  factory ResumenPeriodo.de(List<Movimiento> movimientos, Periodo periodo) {
    var ingresos = 0.0;
    var gastos = 0.0;
    final porCategoria = <String, double>{};

    for (final m in movimientos) {
      if (!periodo.contiene(m.fecha)) continue;
      if (m.esIngreso) {
        ingresos += m.monto;
      } else {
        gastos += m.monto;
        porCategoria[m.categoria] = (porCategoria[m.categoria] ?? 0) + m.monto;
      }
    }

    final ordenadas = Map.fromEntries(
      porCategoria.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return ResumenPeriodo._(ingresos, gastos, ordenadas);
  }

  final double ingresos;
  final double gastos;

  /// De mayor a menor gasto.
  final Map<String, double> gastosPorCategoria;

  double get balance => ingresos - gastos;

  /// Qué parte de lo que entró se gastó (0.72 = 72 %). Null si no hubo
  /// ingresos.
  double? get proporcionGastada => ingresos == 0 ? null : gastos / ingresos;
}

/// Ingresos y gastos de cada uno de los [cantidad] meses que terminan en el
/// mes de [hasta] (incluido), del más antiguo al más reciente.
List<({DateTime mes, double ingresos, double gastos})> totalesPorMes(
  List<Movimiento> movimientos, {
  required DateTime hasta,
  int cantidad = 6,
}) {
  final meses = [
    for (var i = cantidad - 1; i >= 0; i--)
      DateTime(hasta.year, hasta.month - i),
  ];
  final ingresos = List.filled(cantidad, 0.0);
  final gastos = List.filled(cantidad, 0.0);

  for (final m in movimientos) {
    final indice = meses.indexWhere(
      (mes) => mes.year == m.fecha.year && mes.month == m.fecha.month,
    );
    if (indice == -1) continue;
    if (m.esIngreso) {
      ingresos[indice] += m.monto;
    } else {
      gastos[indice] += m.monto;
    }
  }

  return [
    for (var i = 0; i < cantidad; i++)
      (mes: meses[i], ingresos: ingresos[i], gastos: gastos[i]),
  ];
}

/// Variación porcentual de [anterior] a [actual] (0.12 = +12 %). Null si
/// antes era 0 (no hay con qué comparar).
double? variacion(double actual, double anterior) =>
    anterior == 0 ? null : (actual - anterior) / anterior;

/// Categorías cuyo gasto más subió respecto al periodo anterior, de mayor a
/// menor aumento (solo las que subieron).
List<({String categoria, double actual, double anterior})>
categoriasQueCrecieron(
  ResumenPeriodo actual,
  ResumenPeriodo anterior, {
  int maximo = 3,
}) {
  final resultado = [
    for (final entrada in actual.gastosPorCategoria.entries)
      if (entrada.value > (anterior.gastosPorCategoria[entrada.key] ?? 0))
        (
          categoria: entrada.key,
          actual: entrada.value,
          anterior: anterior.gastosPorCategoria[entrada.key] ?? 0,
        ),
  ]..sort((a, b) => (b.actual - b.anterior).compareTo(a.actual - a.anterior));

  return resultado.take(maximo).toList();
}
