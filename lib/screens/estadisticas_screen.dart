import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/filtro_movimientos.dart';
import '../models/periodo.dart';
import '../providers/finanzas_provider.dart';
import '../providers/preferencias_provider.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/estadisticas.dart';
import '../widgets/graficas.dart';
import '../widgets/monto.dart';
import '../widgets/selector_periodo.dart';
import '../widgets/tarjeta_resumen.dart';
import 'home_shell.dart';

class EstadisticasScreen extends StatelessWidget {
  const EstadisticasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final finanzas = context.watch<FinanzasProvider>();
    final preferencias = context.watch<PreferenciasProvider>();
    final periodo = preferencias.periodo;

    if (finanzas.cargando) return const Esqueleto();

    final movimientos = finanzas.movimientos;
    final resumen = ResumenPeriodo.de(movimientos, periodo);
    final anterior = periodo.tipo == TipoPeriodo.total
        ? null
        : ResumenPeriodo.de(movimientos, periodo.anterior);

    // Las barras terminan en el último mes del periodo (sin pasar de hoy).
    final hoy = DateTime.now();
    final ultimoDia = periodo.ultimoDia;
    final finBarras = ultimoDia == null || ultimoDia.isAfter(hoy)
        ? hoy
        : ultimoDia;

    return RefreshIndicator(
      onRefresh: () => context.read<SyncService>().sincronizar(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const SelectorPeriodo(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TarjetaResumen(esIngreso: true, valor: resumen.ingresos),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TarjetaResumen(esIngreso: false, valor: resumen.gastos),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TarjetaProporcion(resumen: resumen),
          if (anterior != null) ...[
            const SizedBox(height: 12),
            _TarjetaComparacion(
              actual: resumen,
              anterior: anterior,
              nombreAnterior: periodo.anterior.etiqueta,
            ),
          ],
          const SizedBox(height: 12),
          _TarjetaCategorias(resumen: resumen, periodo: periodo),
          const SizedBox(height: 12),
          _Tarjeta(
            titulo: 'Últimos 6 meses',
            child: GraficaMeses(
              meses: totalesPorMes(movimientos, hasta: finBarras),
              ocultarMontos: preferencias.ocultarMontos,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// "Gastaste el 72 % de lo que ganaste".
class _TarjetaProporcion extends StatelessWidget {
  const _TarjetaProporcion({required this.resumen});

  final ResumenPeriodo resumen;

  @override
  Widget build(BuildContext context) {
    final colores = ColoresFinza.de(context);
    final proporcion = resumen.proporcionGastada;

    final String titulo;
    final String? detalle;
    if (proporcion != null) {
      final porcentaje = (proporcion * 100).round();
      titulo = 'Gastaste el $porcentaje % de lo que ganaste';
      detalle = resumen.balance >= 0
          ? 'Te quedaron ${context.dinero(resumen.balance)}.'
          : 'Gastaste ${context.dinero(-resumen.balance)} más de lo que '
                'entró.';
    } else if (resumen.gastos > 0) {
      titulo = 'No hubo ingresos en este periodo';
      detalle = 'Gastaste ${context.dinero(resumen.gastos)}.';
    } else {
      titulo = 'Sin movimientos en este periodo';
      detalle = null;
    }

    final color = proporcion == null
        ? colores.gasto
        : proporcion > 1
        ? colores.gasto
        : proporcion > 0.8
        ? colores.alerta
        : colores.ingreso;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            if (proporcion != null) ...[
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(end: proporcion.clamp(0, 1).toDouble()),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, valor, _) => LinearProgressIndicator(
                  value: valor,
                  minHeight: 10,
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ],
            if (detalle != null) ...[const SizedBox(height: 10), Text(detalle)],
          ],
        ),
      ),
    );
  }
}

/// Ingresos y gastos contra el periodo anterior, y las categorías que más
/// subieron.
class _TarjetaComparacion extends StatelessWidget {
  const _TarjetaComparacion({
    required this.actual,
    required this.anterior,
    required this.nombreAnterior,
  });

  final ResumenPeriodo actual;
  final ResumenPeriodo anterior;
  final String nombreAnterior;

  @override
  Widget build(BuildContext context) {
    final colores = ColoresFinza.de(context);
    final crecieron = categoriasQueCrecieron(actual, anterior);

    Widget fila(
      String nombre,
      double hoy,
      double antes, {
      required bool esGasto,
    }) {
      final cambio = variacion(hoy, antes);
      final subio = hoy > antes;
      // Gastar más es malo; ganar más es bueno.
      final color = hoy == antes
          ? null
          : (subio == esGasto ? colores.gasto : colores.ingreso);

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(child: Text(nombre)),
            if (hoy != antes)
              Icon(
                subio ? Icons.trending_up : Icons.trending_down,
                size: 20,
                color: color,
              ),
            const SizedBox(width: 6),
            Text(
              cambio == null
                  ? (hoy == 0 ? 'Sin cambios' : 'Nuevo')
                  : '${cambio >= 0 ? '+' : ''}${(cambio * 100).round()} %',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      );
    }

    return _Tarjeta(
      titulo: 'Comparado con $nombreAnterior',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fila('Ingresos', actual.ingresos, anterior.ingresos, esGasto: false),
          fila('Gastos', actual.gastos, anterior.gastos, esGasto: true),
          if (crecieron.isNotEmpty) ...[
            const Divider(height: 20),
            const Text(
              'Categorías que más crecieron',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final c in crecieron)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(c.categoria)),
                    Text(
                      '+${context.dinero(c.actual - c.anterior)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colores.gasto,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Dona de gastos por categoría. Tocar una categoría abre Movimientos con
/// esa categoría y el mismo periodo.
class _TarjetaCategorias extends StatelessWidget {
  const _TarjetaCategorias({required this.resumen, required this.periodo});

  final ResumenPeriodo resumen;
  final Periodo periodo;

  void _verMovimientos(BuildContext context, String categoria) {
    context.read<PreferenciasProvider>().filtroMovimientos = FiltroMovimientos(
      tipo: 'Gasto',
      categorias: {categoria},
      periodo: periodo.tipo == TipoPeriodo.total
          ? PeriodoFiltro.todo
          : PeriodoFiltro.personalizado,
      desde: periodo.inicio,
      hasta: periodo.ultimoDia,
    );
    HomeShell.tabIndex.value = HomeShell.tabMovimientos;
  }

  @override
  Widget build(BuildContext context) {
    final categorias = resumen.gastosPorCategoria.entries.toList();

    if (categorias.isEmpty) {
      return const _Tarjeta(
        titulo: 'Gastos por categoría',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: Text('No hay gastos en este periodo.')),
        ),
      );
    }

    return _Tarjeta(
      titulo: 'Gastos por categoría',
      child: Column(
        children: [
          Center(
            child: GraficaDona(
              valores: [for (final c in categorias) c.value],
              descripcion: categorias
                  .map((c) => '${c.key}: ${context.dinero(c.value)}')
                  .join(', '),
              centro: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Total'),
                  Text(
                    context.dinero(resumen.gastos),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < categorias.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _verMovimientos(context, categorias[i].key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colorCategoria(i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        categorias[i].key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${(categorias[i].value / resumen.gastos * 100).round()} %',
                    ),
                    const SizedBox(width: 12),
                    Text(
                      context.dinero(categorias[i].value),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
