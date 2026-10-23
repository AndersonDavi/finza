import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/config_recordatorios.dart';
import '../providers/finanzas_provider.dart';
import '../providers/preferencias_provider.dart';
import '../services/recordatorios_service.dart';
import '../utils/formato.dart';
import '../widgets/acciones.dart';
import '../widgets/lista_movimientos.dart';

/// Ajustes de los avisos de facturas: hora, con cuántos días de
/// anticipación y una prueba para ver cómo se ve la notificación.
class RecordatoriosScreen extends StatelessWidget {
  const RecordatoriosScreen({super.key});

  static String nombreOpcion(int dias) => switch (dias) {
    0 => 'El mismo día',
    1 => '1 día antes',
    _ => '$dias días antes',
  };

  Future<void> _elegirHora(
    BuildContext context,
    PreferenciasProvider preferencias,
  ) async {
    final config = preferencias.configRecordatorios;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: config.hora, minute: config.minuto),
      helpText: 'Hora del aviso',
    );
    if (hora != null) {
      preferencias.configRecordatorios = config.copyWith(
        hora: hora.hour,
        minuto: hora.minute,
      );
    }
  }

  Future<void> _probar(BuildContext context) async {
    final servicio = context.read<RecordatoriosService>();
    if (!servicio.disponible) {
      mostrarMensaje(
        context,
        'Las notificaciones solo funcionan en la app instalada en Android.',
      );
      return;
    }

    final mostrada = await servicio.probar(
      context.read<FinanzasProvider>().facturas,
    );
    if (!context.mounted) return;
    mostrarMensaje(
      context,
      mostrada
          ? 'Listo: revisa la barra de notificaciones.'
          : 'Finza no tiene permiso para notificar. Actívalo en los ajustes '
                'del celular (Aplicaciones > Finza > Notificaciones).',
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferencias = context.watch<PreferenciasProvider>();
    final config = preferencias.configRecordatorios;
    final activos = preferencias.recordatoriosActivos;
    final proximos = activos
        ? calcularAvisos(
            context.watch<FinanzasProvider>().facturas,
            config,
          ).take(3).toList()
        : <AvisoFactura>[];

    // Se parte siempre de la configuración guardada, no de la que había al
    // construir la pantalla (dos toques seguidos no se pisan).
    void cambiar(ConfigRecordatorios Function(ConfigRecordatorios) cambio) =>
        preferencias.configRecordatorios = cambio(
          preferencias.configRecordatorios,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Avisos de facturas')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Avisar de las facturas pendientes'),
            subtitle: const Text('Llegan aunque la app esté cerrada'),
            value: activos,
            onChanged: (valor) async {
              preferencias.recordatoriosActivos = valor;
              if (valor) {
                await context.read<RecordatoriosService>().pedirPermiso();
              }
            },
          ),
          const Divider(),
          ListTile(
            enabled: activos,
            leading: const Icon(Icons.schedule),
            title: const Text('Hora del aviso'),
            trailing: Text(
              formatearHora(config.comoFecha),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            onTap: () => _elegirHora(context, preferencias),
          ),
          const _Titulo('¿Cuándo avisar?'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final dias in ConfigRecordatorios.opcionesDias)
                  FilterChip(
                    label: Text(nombreOpcion(dias)),
                    selected: config.diasAntes.contains(dias),
                    onSelected: activos
                        ? (_) => cambiar((actual) {
                            final nuevos = {...actual.diasAntes};
                            if (!nuevos.remove(dias)) nuevos.add(dias);
                            return actual.copyWith(diasAntes: nuevos);
                          })
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            secondary: const Icon(Icons.repeat),
            title: const Text('Seguir avisando si se vence'),
            subtitle: const Text(
              'Un aviso diario durante '
              '${ConfigRecordatorios.diasInsistiendo} días, '
              'hasta que la marques como pagada',
            ),
            value: config.insistirVencidas,
            onChanged: activos
                ? (valor) => cambiar(
                    (actual) => actual.copyWith(insistirVencidas: valor),
                  )
                : null,
          ),
          if (activos && config.diasAntes.isEmpty && !config.insistirVencidas)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Elige al menos un día: así como está no llegará ningún aviso.',
              ),
            ),
          const _Titulo('Próximos avisos'),
          if (!activos)
            const _Nota('Los avisos están desactivados.')
          else if (proximos.isEmpty)
            const _Nota(
              'No hay avisos programados: no tienes facturas '
              'pendientes con fechas próximas.',
            )
          else
            for (final aviso in proximos)
              ListTile(
                dense: true,
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(aviso.titulo),
                subtitle: Text(
                  '${nombreDelDia(aviso.cuando)}, ${formatearHora(aviso.cuando)}',
                ),
              ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.tonalIcon(
              onPressed: () => _probar(context),
              icon: const Icon(Icons.notification_add_outlined),
              label: const Text('Probar notificación'),
            ),
          ),
          const _Nota(
            'Muestra ya mismo un aviso de ejemplo, igual a los '
            'que vas a recibir.',
          ),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(
        texto,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        texto,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
