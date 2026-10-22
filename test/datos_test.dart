import 'dart:convert';
import 'dart:io';

import 'package:finza/database/database_helper.dart';
import 'package:finza/models/factura.dart';
import 'package:finza/models/movimiento.dart';
import 'package:finza/providers/finanzas_provider.dart';
import 'package:finza/services/drive_api.dart';
import 'package:finza/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Directory carpeta;

Future<void> usarBaseNueva(String nombre) async {
  await DatabaseHelper.instance.cerrarBaseDeDatos();
  DatabaseHelper.rutaPersonalizada = '${carpeta.path}/$nombre.db';
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    carpeta = await Directory.systemTemp.createTemp('finza_test');
  });

  tearDownAll(() => carpeta.delete(recursive: true));

  test('migra una base v2 sin perder datos y les asigna uuid', () async {
    final ruta = '${carpeta.path}/v2.db';
    final v2 = await databaseFactoryFfi.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE movimientos (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'tipo TEXT NOT NULL, categoria TEXT NOT NULL, descripcion TEXT NOT NULL, '
            'monto REAL NOT NULL, fecha TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE facturas (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'nombre TEXT NOT NULL, categoria TEXT NOT NULL, monto REAL NOT NULL, '
            'fechaVencimiento TEXT NOT NULL, recurrente INTEGER NOT NULL DEFAULT 0, '
            "frecuencia TEXT, estado TEXT NOT NULL DEFAULT 'Pendiente')",
          );
        },
      ),
    );
    for (final descripcion in ['Almuerzo', 'Bus']) {
      await v2.insert('movimientos', {
        'tipo': 'Gasto',
        'categoria': 'Alimentación',
        'descripcion': descripcion,
        'monto': 15000.0,
        'fecha': DateTime(2026, 9, 1).toIso8601String(),
      });
    }
    await v2.insert('facturas', {
      'nombre': 'Internet',
      'categoria': 'Internet',
      'monto': 80000.0,
      'fechaVencimiento': DateTime(2026, 9, 1).toIso8601String(),
      'recurrente': 1,
      'frecuencia': 'Mensual',
      'estado': 'Pendiente',
    });
    await v2.close();

    await DatabaseHelper.instance.cerrarBaseDeDatos();
    DatabaseHelper.rutaPersonalizada = ruta;

    final movimientos = await DatabaseHelper.instance.obtenerMovimientos();
    final facturas = await DatabaseHelper.instance.obtenerFacturas();

    expect(
      movimientos.map((m) => m.descripcion),
      unorderedEquals(['Almuerzo', 'Bus']),
    );
    expect(movimientos.map((m) => m.uuid).toSet(), hasLength(2));
    expect(facturas.single.recurrente, isTrue);
    expect(facturas.single.eliminadoEn, isNull);
  });

  group('FinanzasProvider', () {
    late FinanzasProvider finanzas;

    setUp(() async {
      await usarBaseNueva('provider_${DateTime.now().microsecondsSinceEpoch}');
      finanzas = FinanzasProvider();
      await finanzas.cargar();
    });

    test('guardar, editar, eliminar a la papelera y restaurar', () async {
      var modificaciones = 0;
      finanzas.alModificarLocalmente = () => modificaciones++;

      await finanzas.guardarMovimiento(
        Movimiento(
          tipo: 'Ingreso',
          categoria: 'Salario',
          descripcion: 'Pago',
          monto: 100,
          fecha: DateTime(2026, 10, 1),
        ),
      );
      final guardado = finanzas.movimientos.single;
      await finanzas.guardarMovimiento(guardado.copyWith(monto: 250));
      expect(finanzas.saldo, 250);

      await finanzas.eliminarMovimiento(finanzas.movimientos.single);
      expect(finanzas.movimientos, isEmpty);
      expect(finanzas.movimientosEnPapelera, hasLength(1));
      expect(finanzas.saldo, 0);

      await finanzas.restaurarMovimiento(finanzas.movimientosEnPapelera.single);
      expect(finanzas.movimientos.single.monto, 250);

      await finanzas.eliminarMovimiento(finanzas.movimientos.single);
      await finanzas.vaciarPapelera();
      expect(finanzas.movimientosEnPapelera, isEmpty);

      expect(modificaciones, 6);
    });

    test('pagar una recurrente crea la siguiente una sola vez', () async {
      await finanzas.guardarFactura(
        Factura(
          nombre: 'Arriendo',
          categoria: 'Vivienda',
          monto: 900000,
          fechaVencimiento: DateTime(2026, 1, 31),
          recurrente: true,
          frecuencia: 'Mensual',
          estado: 'Pendiente',
        ),
      );
      final enero = finanzas.facturas.single;

      final febrero = await finanzas.cambiarEstadoFactura(enero, pagada: true);
      expect(febrero?.fechaVencimiento, DateTime(2026, 2, 28));
      expect(finanzas.facturas, hasLength(2));

      // Desmarcar y volver a pagar no duplica la de febrero.
      final eneroPagada = finanzas.facturas.firstWhere(
        (f) => f.uuid == enero.uuid,
      );
      await finanzas.cambiarEstadoFactura(eneroPagada, pagada: false);
      final eneroPendiente = finanzas.facturas.firstWhere(
        (f) => f.uuid == enero.uuid,
      );
      final otra = await finanzas.cambiarEstadoFactura(
        eneroPendiente,
        pagada: true,
      );
      expect(otra, isNull);
      expect(finanzas.facturas, hasLength(2));
    });
  });

  group('SyncService con un Drive simulado', () {
    late _DriveFalso drive;
    late FinanzasProvider finanzas;
    late SyncService sync;

    setUp(() async {
      await usarBaseNueva('sync_${DateTime.now().microsecondsSinceEpoch}');
      SharedPreferences.setMockInitialValues({});
      drive = _DriveFalso();
      finanzas = FinanzasProvider();
      await finanzas.cargar();
      sync = SyncService(finanzas, await SharedPreferences.getInstance());
    });

    Movimiento gasto(String descripcion) => Movimiento(
      tipo: 'Gasto',
      categoria: 'Transporte',
      descripcion: descripcion,
      monto: 3000,
      fecha: DateTime(2026, 10, 1),
    );

    test('la primera vez crea el archivo con los datos locales', () async {
      await finanzas.guardarMovimiento(gasto('Bus'));
      await sync.sincronizarCon(drive.api);

      final archivo = drive.unicoArchivo;
      expect(archivo['app'], 'finza');
      expect((archivo['movimientos'] as List).single['descripcion'], 'Bus');
    });

    test('combina con lo que subió otro celular y propaga borrados', () async {
      await finanzas.guardarMovimiento(gasto('Bus'));
      await sync.sincronizarCon(drive.api);

      // Otro celular agrega un movimiento y borra "Bus" después.
      final archivo = drive.unicoArchivo;
      final bus =
          (archivo['movimientos'] as List).single as Map<String, dynamic>;
      final despues = DateTime.now()
          .add(const Duration(minutes: 1))
          .toIso8601String();
      archivo['movimientos'] = [
        {...bus, 'eliminadoEn': despues, 'actualizadoEn': despues},
        gasto('Taxi').toJson(),
      ];
      drive.reemplazarUnico(archivo);

      // Y este celular agrega otro sin haber sincronizado.
      await finanzas.guardarMovimiento(gasto('Metro'));
      await sync.sincronizarCon(drive.api);

      expect(
        finanzas.movimientos.map((m) => m.descripcion),
        unorderedEquals(['Taxi', 'Metro']),
      );
      expect(finanzas.movimientosEnPapelera.single.descripcion, 'Bus');

      final subidos = (drive.unicoArchivo['movimientos'] as List).map(
        (m) => m['descripcion'],
      );
      expect(subidos, unorderedEquals(['Bus', 'Taxi', 'Metro']));
    });

    test('si se borró el archivo en Drive, lo vuelve a crear', () async {
      await finanzas.guardarMovimiento(gasto('Bus'));
      await sync.sincronizarCon(drive.api);
      drive.archivos.clear();

      await sync.sincronizarCon(drive.api);
      expect(drive.archivos, hasLength(1));
    });

    test('no pisa un archivo de una versión más nueva de Finza', () async {
      drive.archivos['x'] = jsonEncode({
        'formato': 99,
        'movimientos': [],
        'facturas': [],
      });
      await expectLater(sync.sincronizarCon(drive.api), throwsException);
      expect(jsonDecode(drive.archivos['x']!)['formato'], 99);
    });
  });
}

/// Simula la API de Drive en memoria.
class _DriveFalso {
  final archivos = <String, String>{};
  var _siguienteId = 1;

  DriveApi get api => DriveApi('token', cliente: MockClient(_responder));

  Map<String, dynamic> get unicoArchivo =>
      jsonDecode(archivos.values.single) as Map<String, dynamic>;

  void reemplazarUnico(Map<String, dynamic> contenido) {
    archivos[archivos.keys.single] = jsonEncode(contenido);
  }

  Future<http.Response> _responder(http.Request solicitud) async {
    final ruta = solicitud.url.path;

    if (solicitud.method == 'GET' && ruta == '/drive/v3/files') {
      return http.Response(
        jsonEncode({
          'files': [
            for (final id in archivos.keys) {'id': id},
          ],
        }),
        200,
      );
    }
    if (solicitud.method == 'GET' && ruta.startsWith('/drive/v3/files/')) {
      final contenido = archivos[ruta.split('/').last];
      return contenido == null
          ? http.Response('', 404)
          : http.Response.bytes(utf8.encode(contenido), 200);
    }
    if (solicitud.method == 'POST' && ruta == '/upload/drive/v3/files') {
      final partes = solicitud.body.split('--finza_limite_multipart');
      final contenido = partes[2].split('\r\n\r\n')[1].trim();
      final id = 'archivo${_siguienteId++}';
      archivos[id] = contenido;
      return http.Response(jsonEncode({'id': id}), 200);
    }
    if (solicitud.method == 'PATCH' &&
        ruta.startsWith('/upload/drive/v3/files/')) {
      final id = ruta.split('/').last;
      if (!archivos.containsKey(id)) return http.Response('', 404);
      archivos[id] = solicitud.body;
      return http.Response('{}', 200);
    }
    return http.Response('ruta no simulada: ${solicitud.method} $ruta', 500);
  }
}
