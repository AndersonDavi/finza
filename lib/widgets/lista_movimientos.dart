import 'package:flutter/material.dart';

import '../models/movimiento.dart';
import '../models/periodo.dart';
import '../theme/app_theme.dart';
import '../utils/fechas.dart';
import 'acciones.dart';
import 'monto.dart';
import 'tarjeta_movimiento.dart';

const _diasSemana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// `Hoy`, `Ayer`, `Lun 20 oct` (con el año si no es el actual).
String nombreDelDia(DateTime fecha, {DateTime? hoy}) {
  final dia = soloFecha(fecha);
  final referencia = soloFecha(hoy ?? DateTime.now());
  if (dia == referencia) return 'Hoy';
  if (dia == DateTime(referencia.year, referencia.month, referencia.day - 1)) {
    return 'Ayer';
  }
  final mes = nombresMeses[dia.month - 1].substring(0, 3).toLowerCase();
  final anio = dia.year == referencia.year ? '' : ' ${dia.year}';
  return '${_diasSemana[dia.weekday - 1]} ${dia.day} $mes$anio';
}

/// Movimientos que se pueden deslizar para enviarlos a la papelera.
///
/// Con [agrupar], se separan por día con un encabezado y el balance del día
/// (solo tiene sentido si vienen ordenados por fecha).
///
/// Con [comoColumna] devuelve una columna para meter dentro de otra lista
/// (Inicio); si no, una lista con scroll propio (Movimientos).
class ListaMovimientos extends StatefulWidget {
  const ListaMovimientos({
    super.key,
    required this.movimientos,
    this.agrupar = false,
    this.comoColumna = false,
    this.padding,
  });

  final List<Movimiento> movimientos;
  final bool agrupar;
  final bool comoColumna;
  final EdgeInsets? padding;

  @override
  State<ListaMovimientos> createState() => _ListaMovimientosState();
}

class _ListaMovimientosState extends State<ListaMovimientos> {
  /// Los que se acaban de deslizar: se ocultan ya, sin esperar a que la base
  /// de datos termine (un Dismissible no puede seguir en el árbol).
  final _deslizados = <String>{};

  @override
  void didUpdateWidget(ListaMovimientos anterior) {
    super.didUpdateWidget(anterior);
    // Si se restauró con "Deshacer" (no estaba y volvió), se muestra otra vez.
    bool esta(List<Movimiento> lista, String uuid) =>
        lista.any((m) => m.uuid == uuid);
    _deslizados.removeWhere(
      (uuid) =>
          !esta(anterior.movimientos, uuid) && esta(widget.movimientos, uuid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibles = widget.movimientos
        .where((m) => !_deslizados.contains(m.uuid))
        .toList();

    final elementos = <Object>[];
    if (widget.agrupar) {
      final balancePorDia = <DateTime, double>{};
      for (final m in visibles) {
        final dia = soloFecha(m.fecha);
        balancePorDia[dia] =
            (balancePorDia[dia] ?? 0) + (m.esIngreso ? m.monto : -m.monto);
      }

      DateTime? diaActual;
      for (final m in visibles) {
        final dia = soloFecha(m.fecha);
        if (dia != diaActual) {
          diaActual = dia;
          elementos.add((dia: dia, balance: balancePorDia[dia]!));
        }
        elementos.add(m);
      }
    } else {
      elementos.addAll(visibles);
    }

    Widget construir(Object elemento) {
      if (elemento is Movimiento) return _deslizable(elemento);
      final encabezado = elemento as ({DateTime dia, double balance});
      return _Encabezado(dia: encabezado.dia, balance: encabezado.balance);
    }

    if (widget.comoColumna) {
      return Column(children: [for (final e in elementos) construir(e)]);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: widget.padding,
      itemCount: elementos.length,
      itemBuilder: (context, i) => construir(elementos[i]),
    );
  }

  Widget _deslizable(Movimiento movimiento) {
    final colores = ColoresFinza.de(context);

    return Dismissible(
      key: ValueKey('mov-${movimiento.uuid}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: colores.gasto.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Eliminar',
              style: TextStyle(
                color: colores.gasto,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.delete_outline, color: colores.gasto),
          ],
        ),
      ),
      onDismissed: (_) {
        setState(() => _deslizados.add(movimiento.uuid));
        eliminarMovimientoConDeshacer(context, movimiento);
      },
      child: TarjetaMovimiento(
        movimiento: movimiento,
        mostrarFecha: !widget.agrupar,
        onTap: () => mostrarOpcionesMovimiento(context, movimiento),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.dia, required this.balance});

  final DateTime dia;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(nombreDelDia(dia), style: estilo)),
          Text(context.dinero(balance, conSigno: balance != 0), style: estilo),
        ],
      ),
    );
  }
}
