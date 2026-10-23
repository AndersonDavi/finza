import 'package:finza/models/config_recordatorios.dart';
import 'package:finza/models/factura.dart';
import 'package:finza/services/recordatorios_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simula el lado Android del plugin de notificaciones: guarda cómo se
/// programó cada aviso y deja controlar el permiso de alarmas exactas.
class _AndroidSimulado {
  bool exactasPermitidas = false;
  bool fallarExactas = false;
  final modos = <String>[];

  Future<Object?> responder(MethodCall llamada) async {
    switch (llamada.method) {
      case 'canScheduleExactNotifications':
        return exactasPermitidas;
      case 'requestExactAlarmsPermission':
        // El usuario activa el permiso en la pantalla de Android.
        exactasPermitidas = true;
        return true;
      case 'zonedSchedule':
        final argumentos = llamada.arguments as Map;
        final modo =
            (argumentos['platformSpecifics'] as Map)['scheduleMode'] as String;
        if (modo.startsWith('exact') && fallarExactas) {
          throw PlatformException(code: 'exactAlarmsNotPermitted');
        }
        modos.add(modo);
        return null;
      case 'cancelAll':
        modos.clear();
        return null;
      case 'requestNotificationsPermission':
      case 'areNotificationsEnabled':
      case 'initialize':
        return true;
      default:
        return null;
    }
  }
}

Future<void> _esperarProgramacion() =>
    Future<void>.delayed(const Duration(milliseconds: 700));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AndroidSimulado android;
  late RecordatoriosService servicio;

  final facturas = [
    Factura(
      nombre: 'Internet',
      categoria: 'Internet',
      monto: 80000,
      fechaVencimiento: DateTime.now().add(const Duration(days: 10)),
      recurrente: false,
      estado: 'Pendiente',
    ),
  ];
  const config = ConfigRecordatorios(diasAntes: {0, 1, 3});

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    android = _AndroidSimulado();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          android.responder,
        );

    SharedPreferences.setMockInitialValues({});
    servicio = RecordatoriosService(await SharedPreferences.getInstance());
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('sin el permiso de alarmas exactas, programa inexactos', () async {
    await servicio.inicializar();
    expect(servicio.exactos.value, isFalse);

    servicio.programar(facturas, activos: true, config: config);
    await _esperarProgramacion();

    expect(android.modos, hasLength(3));
    expect(android.modos.toSet(), {'inexactAllowWhileIdle'});
  });

  test('con el permiso, programa a la hora exacta', () async {
    android.exactasPermitidas = true;
    await servicio.inicializar();
    expect(servicio.exactos.value, isTrue);

    servicio.programar(facturas, activos: true, config: config);
    await _esperarProgramacion();

    expect(android.modos.toSet(), {'exactAllowWhileIdle'});
  });

  test('al conceder el permiso, reprograma todo como exacto', () async {
    await servicio.inicializar();
    servicio.programar(facturas, activos: true, config: config);
    await _esperarProgramacion();
    expect(android.modos.toSet(), {'inexactAllowWhileIdle'});

    expect(await servicio.pedirAvisosExactos(), isTrue);
    await _esperarProgramacion();

    expect(android.modos, hasLength(3));
    expect(android.modos.toSet(), {'exactAllowWhileIdle'});
  });

  test('si quitan el permiso fuera de la app, al volver reprograma', () async {
    android.exactasPermitidas = true;
    await servicio.inicializar();
    servicio.programar(facturas, activos: true, config: config);
    await _esperarProgramacion();
    expect(android.modos.toSet(), {'exactAllowWhileIdle'});

    // Android borra las alarmas exactas al quitar el permiso.
    android.exactasPermitidas = false;
    servicio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _esperarProgramacion();

    expect(servicio.exactos.value, isFalse);
    expect(android.modos, hasLength(3));
    expect(android.modos.toSet(), {'inexactAllowWhileIdle'});
  });

  test('si Android rechaza la alarma exacta, el aviso no se pierde', () async {
    android
      ..exactasPermitidas = true
      ..fallarExactas = true;
    await servicio.inicializar();

    servicio.programar(facturas, activos: true, config: config);
    await _esperarProgramacion();

    expect(android.modos, hasLength(3));
    expect(android.modos.toSet(), {'inexactAllowWhileIdle'});
    expect(servicio.exactos.value, isFalse);
  });
}
