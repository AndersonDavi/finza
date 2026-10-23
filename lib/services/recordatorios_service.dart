import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/config_recordatorios.dart';
import '../models/factura.dart';
import '../utils/fechas.dart';
import '../utils/formato.dart';

/// Recordatorios locales de facturas, a la hora y con los días de
/// anticipación que el usuario elige en Ajustes. No usan servidor (a diferencia de las push de
/// top-list): Android los dispara aunque la app esté cerrada.
class RecordatoriosService {
  RecordatoriosService(this._prefs);

  static const _canal = AndroidNotificationDetails(
    'facturas',
    'Facturas por vencer',
    channelDescription: 'Recordatorios de facturas pendientes',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Android limita las alarmas por app; con esto sobra.
  static const _maximoAvisos = 60;
  static const _clavePermisoPedido = 'notificaciones_permiso_pedido';

  final SharedPreferences _prefs;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _listo = false;
  String? _ultimaFirma;
  Timer? _temporizador;

  /// Solo en Android y si el plugin se pudo iniciar.
  bool get disponible => _listo;

  /// Se llama al tocar una notificación (abre la pestaña de Facturas).
  VoidCallback? alTocarNotificacion;

  Future<void> inicializar() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    tz.initializeTimeZones();
    try {
      final zona = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zona.identifier));
    } catch (e) {
      // Algunos teléfonos reportan zonas que no están en la base de datos
      // (ej. "GMT-05:00"). Se queda en UTC: igual funciona, porque cada aviso
      // se programa con el instante exacto (TZDateTime.from).
      debugPrint('Recordatorios: zona horaria desconocida, se usa UTC: $e');
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // Ícono monocromo: con el de la app, Android muestra un cuadro blanco.
          android: AndroidInitializationSettings('ic_stat_finza'),
        ),
        onDidReceiveNotificationResponse: (_) => alTocarNotificacion?.call(),
      );

      final lanzamiento = await _plugin.getNotificationAppLaunchDetails();
      if (lanzamiento?.didNotificationLaunchApp ?? false) {
        alTocarNotificacion?.call();
      }

      _listo = true;
    } catch (e) {
      debugPrint('Recordatorios: no se pudieron iniciar: $e');
    }
  }

  /// Reprograma todos los avisos. Se puede llamar seguido: espera un momento
  /// y no hace nada si las facturas pendientes no cambiaron.
  void programar(
    List<Factura> facturas, {
    required bool activos,
    required ConfigRecordatorios config,
  }) {
    _temporizador?.cancel();
    _temporizador = Timer(
      const Duration(milliseconds: 500),
      () => _programar(facturas, activos: activos, config: config),
    );
  }

  Future<void> _programar(
    List<Factura> facturas, {
    required bool activos,
    required ConfigRecordatorios config,
  }) async {
    if (!_listo) return;

    final avisos = activos
        ? calcularAvisos(facturas, config).take(_maximoAvisos).toList()
        : <AvisoFactura>[];
    final firma = avisos
        .map((a) => '${a.cuando}|${a.titulo}|${a.cuerpo}')
        .join(';');
    if (firma == _ultimaFirma) return;
    _ultimaFirma = firma;

    await _plugin.cancelAll();
    if (avisos.isEmpty) return;

    await _pedirPermisoUnaVez();

    for (var i = 0; i < avisos.length; i++) {
      final aviso = avisos[i];
      await _plugin.zonedSchedule(
        id: i,
        title: aviso.titulo,
        body: aviso.cuerpo,
        scheduledDate: tz.TZDateTime.from(aviso.cuando, tz.local),
        notificationDetails: const NotificationDetails(android: _canal),
        // Inexacto: no necesita el permiso de alarmas exactas y un aviso
        // de factura no tiene que llegar al segundo.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'facturas',
      );
    }
  }

  /// Muestra ya mismo un aviso de ejemplo, para ver cómo se ve. Usa la
  /// próxima factura pendiente si hay alguna. Devuelve false si no se pudo
  /// (sin permiso o fuera de Android).
  Future<bool> probar(List<Factura> facturas) async {
    if (!_listo) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final activas = await android?.areNotificationsEnabled() ?? false;
    if (!activas && !await pedirPermiso()) return false;

    final pendientes = facturas.where((f) => !f.pagada).toList()
      ..sort((a, b) => a.fechaVencimiento.compareTo(b.fechaVencimiento));
    final ejemplo = pendientes.isEmpty
        ? (titulo: 'Internet vence mañana', cuerpo: 'Pago de \$80.000.')
        : textoAviso(
            pendientes.first,
            soloFecha(pendientes.first.fechaVencimiento)
                .difference(soloFecha(DateTime.now()))
                .inDays
                .clamp(0, 365),
          );

    await _plugin.show(
      id: _idPrueba,
      title: ejemplo.titulo,
      body: ejemplo.cuerpo,
      notificationDetails: const NotificationDetails(android: _canal),
      payload: 'facturas',
    );
    return true;
  }

  static const _idPrueba = 100000;

  /// Android 13+ exige pedir permiso para notificaciones. Se pide la primera
  /// vez que hay algo para avisar, no al abrir la app.
  Future<void> _pedirPermisoUnaVez() async {
    if (_prefs.getBool(_clavePermisoPedido) ?? false) return;
    await _prefs.setBool(_clavePermisoPedido, true);
    await pedirPermiso();
  }

  Future<bool> pedirPermiso() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }
}

class AvisoFactura {
  AvisoFactura(this.cuando, this.titulo, this.cuerpo);

  final DateTime cuando;
  final String titulo;
  final String cuerpo;
}

/// Título y texto del aviso de [factura] a [dias] del vencimiento (negativo
/// si ya se venció).
({String titulo, String cuerpo}) textoAviso(Factura factura, int dias) {
  final monto = formatearDinero(factura.monto);
  final nombre = factura.nombre;

  if (dias < 0) {
    final vencida = -dias;
    return (
      titulo: '$nombre lleva $vencida día${vencida == 1 ? '' : 's'} vencida',
      cuerpo: 'Pago de $monto. Márcala como pagada en Finza.',
    );
  }
  return switch (dias) {
    0 => (
      titulo: '$nombre vence hoy',
      cuerpo: 'Pago de $monto. Márcala como pagada en Finza.',
    ),
    1 => (titulo: '$nombre vence mañana', cuerpo: 'Pago de $monto.'),
    _ => (titulo: '$nombre vence en $dias días', cuerpo: 'Pago de $monto.'),
  };
}

/// Todos los avisos futuros de las facturas pendientes según [config],
/// ordenados del más próximo al más lejano.
List<AvisoFactura> calcularAvisos(
  List<Factura> facturas,
  ConfigRecordatorios config, {
  DateTime? ahora,
}) {
  final momento = ahora ?? DateTime.now();
  final avisos = <AvisoFactura>[];

  final dias = [
    ...config.diasAntes,
    if (config.insistirVencidas)
      for (var i = 1; i <= ConfigRecordatorios.diasInsistiendo; i++) -i,
  ];

  for (final factura in facturas.where((f) => !f.pagada)) {
    final vence = soloFecha(factura.fechaVencimiento);
    for (final antes in dias) {
      final texto = textoAviso(factura, antes);
      avisos.add(
        AvisoFactura(
          DateTime(
            vence.year,
            vence.month,
            vence.day - antes,
            config.hora,
            config.minuto,
          ),
          texto.titulo,
          texto.cuerpo,
        ),
      );
    }
  }

  return avisos.where((a) => a.cuando.isAfter(momento)).toList()
    ..sort((a, b) => a.cuando.compareTo(b.cuando));
}
