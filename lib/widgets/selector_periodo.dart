import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/periodo.dart';
import '../providers/finanzas_provider.dart';
import '../providers/preferencias_provider.dart';

/// Barra `‹ Octubre 2026 ›` de Inicio y Estadísticas. Las flechas mueven el
/// periodo y al tocar el nombre se elige otro tipo (año, rangos, todo).
class SelectorPeriodo extends StatelessWidget {
  const SelectorPeriodo({super.key});

  @override
  Widget build(BuildContext context) {
    final preferencias = context.watch<PreferenciasProvider>();
    final periodo = preferencias.periodo;
    final navegable = periodo.tipo != TipoPeriodo.total;
    // No se avanza más allá del periodo que incluye hoy.
    final haySiguiente =
        navegable && periodo.siguiente.inicio!.isBefore(DateTime.now());

    void cambiar(Periodo nuevo) {
      HapticFeedback.selectionClick();
      preferencias.periodo = nuevo;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Periodo anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: navegable ? () => cambiar(periodo.anterior) : null,
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final nuevo = await elegirPeriodo(context, periodo);
                if (nuevo != null) cambiar(nuevo);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        periodo.etiqueta,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Periodo siguiente',
            icon: const Icon(Icons.chevron_right),
            onPressed: haySiguiente ? () => cambiar(periodo.siguiente) : null,
          ),
        ],
      ),
    );
  }
}

/// Panel para elegir el tipo de periodo. Devuelve null si se cierra.
Future<Periodo?> elegirPeriodo(BuildContext context, Periodo actual) async {
  final ahora = DateTime.now();
  final movimientos = context.read<FinanzasProvider>().movimientos;
  final primerAnio = movimientos.isEmpty
      ? ahora.year
      : movimientos
            .map((m) => m.fecha.year)
            .reduce((a, b) => a < b ? a : b)
            .clamp(2000, ahora.year);

  final opcion = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      Widget opcion(String valor, IconData icono, String titulo, String? sub) =>
          ListTile(
            leading: Icon(icono),
            title: Text(titulo),
            subtitle: sub == null ? null : Text(sub),
            selected: _tipoDeOpcion(valor) == actual.tipo,
            onTap: () => Navigator.pop(context, valor),
          );

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ver periodo',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              opcion('mes', Icons.calendar_view_month, 'Un mes', null),
              opcion('anio', Icons.calendar_today_outlined, 'Un año', null),
              opcion(
                'rangoMeses',
                Icons.date_range_outlined,
                'Rango de meses',
                'Ej. de enero a junio',
              ),
              opcion(
                'rangoFechas',
                Icons.event_note_outlined,
                'Rango de fechas',
                'De una fecha a otra',
              ),
              opcion('total', Icons.all_inclusive, 'Todo el historial', null),
            ],
          ),
        ),
      );
    },
  );
  if (opcion == null || !context.mounted) return null;

  final mesInicial = actual.inicio ?? DateTime(ahora.year, ahora.month);

  switch (opcion) {
    case 'mes':
      final mes = await _elegirMes(
        context,
        titulo: 'Elige el mes',
        inicial: mesInicial,
        primerAnio: primerAnio,
      );
      return mes == null ? null : Periodo.mes(mes.year, mes.month);
    case 'anio':
      final anio = await _elegirAnio(
        context,
        inicial: mesInicial.year,
        primerAnio: primerAnio,
      );
      return anio == null ? null : Periodo.anio(anio);
    case 'rangoMeses':
      final desde = await _elegirMes(
        context,
        titulo: 'Desde el mes',
        inicial: mesInicial,
        primerAnio: primerAnio,
      );
      if (desde == null || !context.mounted) return null;
      final hasta = await _elegirMes(
        context,
        titulo: 'Hasta el mes',
        inicial: actual.ultimoDia ?? DateTime(ahora.year, ahora.month),
        primerAnio: primerAnio,
        minimo: desde,
      );
      return hasta == null ? null : Periodo.rangoMeses(desde, hasta);
    case 'rangoFechas':
      final rango = await showDateRangePicker(
        context: context,
        firstDate: DateTime(primerAnio),
        lastDate: DateTime(ahora.year + 1, 12, 31),
        initialDateRange: actual.inicio == null
            ? null
            : DateTimeRange(start: actual.inicio!, end: actual.ultimoDia!),
        helpText: 'Elige las fechas',
      );
      return rango == null ? null : Periodo.rangoFechas(rango.start, rango.end);
    case 'total':
      return Periodo.total;
  }
  return null;
}

TipoPeriodo _tipoDeOpcion(String opcion) =>
    TipoPeriodo.values.asNameMap()[opcion]!;

Future<int?> _elegirAnio(
  BuildContext context, {
  required int inicial,
  required int primerAnio,
}) {
  final ultimo = DateTime.now().year;
  final anios = [for (var a = ultimo; a >= primerAnio; a--) a];

  return showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Elige el año'),
      children: [
        for (final anio in anios)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, anio),
            child: Text(
              '$anio',
              style: TextStyle(
                fontSize: 16,
                fontWeight: anio == inicial ? FontWeight.bold : null,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Diálogo con los 12 meses de un año y flechas para cambiar de año.
/// Devuelve el primer día del mes elegido.
Future<DateTime?> _elegirMes(
  BuildContext context, {
  required String titulo,
  required DateTime inicial,
  required int primerAnio,
  DateTime? minimo,
}) {
  final ahora = DateTime.now();
  var anio = inicial.year.clamp(primerAnio, ahora.year);

  return showDialog<DateTime>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final colorScheme = Theme.of(context).colorScheme;

        bool habilitado(int mes) {
          final fecha = DateTime(anio, mes);
          if (fecha.isAfter(ahora)) return false;
          if (minimo != null && fecha.isBefore(minimo)) return false;
          return true;
        }

        return AlertDialog(
          title: Text(titulo),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: anio > primerAnio
                          ? () => setState(() => anio--)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        '$anio',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: anio < ahora.year
                          ? () => setState(() => anio++)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  childAspectRatio: 2,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (var mes = 1; mes <= 12; mes++)
                      Builder(
                        builder: (context) {
                          final elegido =
                              anio == inicial.year && mes == inicial.month;
                          final texto = Text(
                            nombresMeses[mes - 1].substring(0, 3),
                          );
                          final accion = habilitado(mes)
                              ? () =>
                                    Navigator.pop(context, DateTime(anio, mes))
                              : null;
                          return elegido
                              ? FilledButton(onPressed: accion, child: texto)
                              : TextButton(
                                  onPressed: accion,
                                  style: TextButton.styleFrom(
                                    foregroundColor: colorScheme.onSurface,
                                  ),
                                  child: texto,
                                );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    ),
  );
}
