import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/preferencias_provider.dart';
import '../services/recordatorios_service.dart';
import '../services/sync_service.dart';
import '../utils/formato.dart';
import 'recordatorios_screen.dart';

/// Pantallas de la primera vez: qué hace Finza, conectar Drive (opcional) y
/// activar los avisos de facturas. Todo se puede cambiar luego en Ajustes.
class BienvenidaScreen extends StatefulWidget {
  const BienvenidaScreen({super.key});

  @override
  State<BienvenidaScreen> createState() => _BienvenidaScreenState();
}

class _BienvenidaScreenState extends State<BienvenidaScreen> {
  final _paginas = PageController();
  int _pagina = 0;

  static const _total = 3;

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  void _terminar() =>
      context.read<PreferenciasProvider>().bienvenidaVista = true;

  void _siguiente() {
    if (_pagina == _total - 1) {
      _terminar();
      return;
    }
    _paginas.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: _terminar,
                  child: const Text('Saltar'),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _paginas,
                onPageChanged: (pagina) => setState(() => _pagina = pagina),
                children: const [
                  _PaginaInicio(),
                  _PaginaDrive(),
                  _PaginaAvisos(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  for (var i = 0; i < _total; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _pagina ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _pagina
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _siguiente,
                    child: Text(
                      _pagina == _total - 1 ? 'Empezar' : 'Siguiente',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estructura común: ícono grande, título, texto y contenido opcional.
class _Pagina extends StatelessWidget {
  const _Pagina({
    required this.icono,
    required this.titulo,
    required this.texto,
    this.contenido,
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final Widget? contenido;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            child: Icon(icono, size: 40),
          ),
          const SizedBox(height: 28),
          Text(
            titulo,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(texto, style: const TextStyle(fontSize: 16, height: 1.4)),
          if (contenido != null) ...[const SizedBox(height: 28), contenido!],
        ],
      ),
    );
  }
}

class _PaginaInicio extends StatelessWidget {
  const _PaginaInicio();

  @override
  Widget build(BuildContext context) {
    Widget punto(IconData icono, String texto) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icono, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );

    return _Pagina(
      icono: Icons.account_balance_wallet_outlined,
      titulo: 'Bienvenido a Finza',
      texto: 'Tus finanzas personales, simples y en tu celular.',
      contenido: Column(
        children: [
          punto(Icons.bolt, 'Registra un gasto en segundos.'),
          punto(
            Icons.pie_chart_outline,
            'Mira en qué se va tu plata, mes a mes.',
          ),
          punto(
            Icons.receipt_long_outlined,
            'No vuelvas a olvidar una factura.',
          ),
          punto(
            Icons.visibility_off_outlined,
            'Oculta los montos con el ojo de arriba.',
          ),
        ],
      ),
    );
  }
}

class _PaginaDrive extends StatelessWidget {
  const _PaginaDrive();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();

    final Widget contenido;
    if (sync.estado == EstadoSync.noConfigurado) {
      contenido = const Text(
        'Esta versión de la app no trae la sincronización activada. '
        'Tus datos se guardan en este celular.',
      );
    } else if (sync.vinculado) {
      contenido = Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(child: Text('Conectado como ${sync.email ?? 'tu cuenta'}.')),
        ],
      );
    } else {
      contenido = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: sync.conectar,
            icon: const Icon(Icons.login),
            label: const Text('Conectar con Google'),
          ),
          if (sync.error != null) ...[
            const SizedBox(height: 8),
            Text(sync.error!),
          ],
          const SizedBox(height: 12),
          const Text('Es opcional: puedes hacerlo luego en Ajustes.'),
        ],
      );
    }

    return _Pagina(
      icono: Icons.cloud_outlined,
      titulo: 'Respaldo en tu Drive',
      texto:
          'Guarda una copia en tu Google Drive y ten los mismos datos en '
          'todos tus celulares. Finza solo ve el archivo que ella misma crea.',
      contenido: contenido,
    );
  }
}

class _PaginaAvisos extends StatelessWidget {
  const _PaginaAvisos();

  @override
  Widget build(BuildContext context) {
    final preferencias = context.watch<PreferenciasProvider>();
    final config = preferencias.configRecordatorios;

    return _Pagina(
      icono: Icons.notifications_active_outlined,
      titulo: 'Avisos de facturas',
      texto:
          'Finza te avisa antes de que se venza una factura, aunque la app '
          'esté cerrada.',
      contenido: Column(
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Activar avisos'),
                  subtitle: Text(config.descripcionDias),
                  value: preferencias.recordatoriosActivos,
                  onChanged: (activos) async {
                    preferencias.recordatoriosActivos = activos;
                    if (activos) {
                      await context.read<RecordatoriosService>().pedirPermiso();
                    }
                  },
                ),
                ListTile(
                  enabled: preferencias.recordatoriosActivos,
                  title: const Text('Hora del aviso'),
                  trailing: Text(
                    formatearHora(config.comoFecha),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () async {
                    final hora = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: config.hora,
                        minute: config.minuto,
                      ),
                    );
                    if (hora != null) {
                      preferencias.configRecordatorios = config.copyWith(
                        hora: hora.hour,
                        minuto: hora.minute,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          if (preferencias.recordatoriosActivos) ...[
            const SizedBox(height: 8),
            const AvisoAlarmasExactas(),
          ],
        ],
      ),
    );
  }
}
