import 'package:finza/database/database_helper.dart';
import 'package:finza/main.dart';
import 'package:finza/models/factura.dart';
import 'package:finza/models/movimiento.dart';
import 'package:finza/models/periodo.dart';
import 'package:finza/providers/finanzas_provider.dart';
import 'package:finza/providers/preferencias_provider.dart';
import 'package:finza/screens/home_shell.dart';
import 'package:finza/widgets/monto.dart';
import 'package:finza/services/actualizacion_service.dart';
import 'package:finza/services/recordatorios_service.dart';
import 'package:finza/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base de datos en memoria, para que los tests de interfaz no dependan de
/// SQLite.
class _BaseEnMemoria implements DatabaseHelper {
  final movimientos = <Movimiento>[];
  final facturas = <Factura>[];
  var _id = 1;

  @override
  Future<int> insertarMovimiento(Movimiento m) async {
    movimientos.add(m.copyWith(id: _id));
    return _id++;
  }

  @override
  Future<int> actualizarMovimiento(Movimiento m) async {
    movimientos[movimientos.indexWhere((x) => x.id == m.id)] = m;
    return 1;
  }

  @override
  Future<List<Movimiento>> obtenerMovimientos() async =>
      movimientos.where((m) => !m.purgado).toList()
        ..sort((a, b) => b.fecha.compareTo(a.fecha));

  @override
  Future<int> insertarFactura(Factura f) async {
    facturas.add(f.copyWith(id: _id));
    return _id++;
  }

  @override
  Future<int> actualizarFactura(Factura f) async {
    facturas[facturas.indexWhere((x) => x.id == f.id)] = f;
    return 1;
  }

  @override
  Future<List<Factura>> obtenerFacturas() async =>
      facturas.where((f) => !f.purgado).toList()
        ..sort((a, b) => a.fechaVencimiento.compareTo(b.fechaVencimiento));

  @override
  Future<bool> existeFactura(String uuid) async =>
      facturas.any((f) => f.uuid == uuid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<FinanzasProvider> _abrirApp(
  WidgetTester tester, {
  ThemeMode tema = ThemeMode.light,
  bool bienvenidaVista = true,
  void Function(_BaseEnMemoria db)? datos,
}) async {
  SharedPreferences.setMockInitialValues({
    'tema': tema.name,
    'bienvenida_vista': bienvenidaVista,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = _BaseEnMemoria();
  datos?.call(db);

  final finanzas = FinanzasProvider(db: db);
  await finanzas.cargar();
  HomeShell.tabIndex.value = HomeShell.tabInicio;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: finanzas),
        ChangeNotifierProvider(create: (_) => PreferenciasProvider(prefs)),
        ChangeNotifierProvider(
          create: (_) => SyncService(finanzas, prefs, db: db),
        ),
        Provider(create: (_) => RecordatoriosService(prefs)),
        Provider(create: (_) => ActualizacionService(prefs)),
      ],
      child: const FinzaApp(),
    ),
  );
  await tester.pumpAndSettle();
  return finanzas;
}

void main() {
  testWidgets('agregar un gasto lo muestra en Inicio y en el saldo', (
    tester,
  ) async {
    final finanzas = await _abrirApp(tester);

    expect(find.text('Todavía no tienes movimientos.'), findsOneWidget);

    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Descripción (opcional)'),
      'Almuerzo',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '15.000');
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();

    expect(finanzas.movimientos.single.monto, 15000);
    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text('-\$15.000'), findsWidgets);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('recorre todas las pestañas en modo oscuro', (tester) async {
    await _abrirApp(
      tester,
      tema: ThemeMode.dark,
      datos: (db) {
        db.movimientos.add(
          Movimiento(
            id: 1,
            tipo: 'Ingreso',
            categoria: 'Salario',
            descripcion: 'Pago',
            monto: 2000000,
            fecha: DateTime.now(),
          ),
        );
        db.facturas.add(
          Factura(
            id: 2,
            nombre: 'Internet',
            categoria: 'Internet',
            monto: 80000,
            fechaVencimiento: DateTime.now().subtract(const Duration(days: 2)),
            recurrente: true,
            frecuencia: 'Mensual',
            estado: 'Pendiente',
          ),
        );
      },
    );

    // Banner de facturas vencidas al abrir.
    expect(find.text('Facturas por pagar'), findsOneWidget);

    for (final pestana in ['Movimientos', 'Estadísticas', 'Facturas']) {
      await tester.tap(find.widgetWithText(NavigationDestination, pestana));
      await tester.pumpAndSettle();
    }
    expect(find.text('Vencida'), findsOneWidget);

    await tester.tap(find.text('Marcar pagada'));
    await tester.pumpAndSettle();
    expect(find.textContaining('La próxima vence el'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('eliminar manda a la papelera y se puede restaurar', (
    tester,
  ) async {
    final finanzas = await _abrirApp(
      tester,
      datos: (db) => db.movimientos.add(
        Movimiento(
          id: 1,
          tipo: 'Gasto',
          categoria: 'Transporte',
          descripcion: 'Bus',
          monto: 3000,
          fecha: DateTime.now(),
        ),
      ),
    );

    await tester.tap(find.text('Bus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar movimiento'));
    await tester.pumpAndSettle();
    expect(finanzas.movimientos, isEmpty);

    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('No disponible en esta versión'), findsOneWidget);

    await tester.tap(find.text('Papelera'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurar'));
    await tester.pumpAndSettle();

    expect(finanzas.movimientos.single.descripcion, 'Bus');
    expect(find.text('La papelera está vacía'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('la primera vez muestra la bienvenida y luego la app', (
    tester,
  ) async {
    await _abrirApp(tester, bienvenidaVista: false);

    expect(find.text('Bienvenido a Finza'), findsOneWidget);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Respaldo en tu Drive'), findsOneWidget);
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Activar avisos'), findsOneWidget);
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();

    expect(find.text('Movimientos recientes'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('bienvenida_vista'), isTrue);
  });

  testWidgets('guardar sin descripción usa la categoría', (tester) async {
    final finanzas = await _abrirApp(tester);

    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '2500');
    expect(find.text('2.500'), findsOneWidget);
    await tester.tap(find.text('Transporte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();

    final guardado = finanzas.movimientos.single;
    expect(guardado.tipo, 'Gasto');
    expect(guardado.categoria, 'Transporte');
    expect(guardado.descripcion, 'Transporte');
    expect(guardado.monto, 2500);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('el ojo oculta y vuelve a mostrar los montos', (tester) async {
    await _abrirApp(
      tester,
      datos: (db) => db.movimientos.add(
        Movimiento(
          id: 1,
          tipo: 'Ingreso',
          categoria: 'Salario',
          descripcion: 'Pago',
          monto: 2000000,
          fecha: DateTime.now(),
        ),
      ),
    );

    expect(find.text('+\$2.000.000'), findsWidgets);
    await tester.tap(find.byTooltip('Ocultar montos'));
    await tester.pumpAndSettle();
    expect(find.text('+\$2.000.000'), findsNothing);
    expect(find.text(montoOculto), findsWidgets);

    await tester.tap(find.byTooltip('Mostrar montos'));
    await tester.pumpAndSettle();
    expect(find.text('+\$2.000.000'), findsWidgets);
  });

  testWidgets('deslizar un movimiento lo elimina y se puede deshacer', (
    tester,
  ) async {
    final finanzas = await _abrirApp(
      tester,
      datos: (db) => db.movimientos.add(
        Movimiento(
          id: 1,
          tipo: 'Gasto',
          categoria: 'Transporte',
          descripcion: 'Bus',
          monto: 3000,
          fecha: DateTime.now(),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(NavigationDestination, 'Movimientos'));
    await tester.pumpAndSettle();
    expect(find.text('Hoy'), findsOneWidget);

    await tester.drag(find.text('Bus'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(finanzas.movimientos, isEmpty);
    expect(find.text('Bus'), findsNothing);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(finanzas.movimientos.single.descripcion, 'Bus');
    expect(find.text('Bus'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('Inicio muestra el periodo elegido', (tester) async {
    final ahora = DateTime.now();
    await _abrirApp(
      tester,
      datos: (db) => db.movimientos.addAll([
        Movimiento(
          id: 1,
          tipo: 'Gasto',
          categoria: 'Alimentación',
          descripcion: 'Mercado',
          monto: 100000,
          fecha: ahora,
        ),
        Movimiento(
          id: 2,
          tipo: 'Ingreso',
          categoria: 'Salario',
          descripcion: 'Prima',
          monto: 500000,
          fecha: DateTime(ahora.year - 1, 6, 15),
        ),
      ]),
    );

    expect(find.text(Periodo.mesActual().etiqueta), findsOneWidget);
    expect(find.text('-\$100.000'), findsWidgets);
    expect(find.text('+\$400.000'), findsNothing);

    await tester.tap(find.text(Periodo.mesActual().etiqueta));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todo el historial'));
    await tester.pumpAndSettle();

    expect(find.text('Balance total'), findsOneWidget);
    expect(find.text('+\$400.000'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(NavigationDestination, 'Estadísticas'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gastaste el 20 % de lo que ganaste'), findsOneWidget);
  });

  testWidgets('tocar una categoría en Estadísticas filtra Movimientos', (
    tester,
  ) async {
    await _abrirApp(
      tester,
      datos: (db) => db.movimientos.addAll([
        Movimiento(
          id: 1,
          tipo: 'Gasto',
          categoria: 'Transporte',
          descripcion: 'Bus',
          monto: 3000,
          fecha: DateTime.now(),
        ),
        Movimiento(
          id: 2,
          tipo: 'Gasto',
          categoria: 'Alimentación',
          descripcion: 'Almuerzo',
          monto: 15000,
          fecha: DateTime.now(),
        ),
      ]),
    );

    await tester.tap(
      find.widgetWithText(NavigationDestination, 'Estadísticas'),
    );
    await tester.pumpAndSettle();
    // La de la lista de la dona (la otra es de "Categorías que más crecieron").
    final categoria = find.text('Transporte').last;
    await tester.scrollUntilVisible(find.text('Últimos 6 meses'), 200);
    await tester.tap(categoria);
    await tester.pumpAndSettle();

    expect(HomeShell.tabIndex.value, HomeShell.tabMovimientos);
    expect(find.text('Bus'), findsOneWidget);
    expect(find.text('Almuerzo'), findsNothing);
  });

  testWidgets('configurar los avisos y probar la notificación', (tester) async {
    await _abrirApp(tester);

    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(
      find.text('El mismo día, el día antes, a las 09:00'),
      findsOneWidget,
    );
    await tester.tap(find.text('Avisos de facturas'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3 días antes'));
    await tester.tap(find.text('El mismo día'));
    await tester.tap(find.text('Seguir avisando si se vence'));
    await tester.pumpAndSettle();

    final preferencias = tester
        .element(find.byType(Scaffold).last)
        .read<PreferenciasProvider>();
    expect(preferencias.configRecordatorios.diasAntes, {1, 3});
    expect(preferencias.configRecordatorios.insistirVencidas, isTrue);

    await tester.scrollUntilVisible(find.text('Probar notificación'), 200);
    await tester.tap(find.text('Probar notificación'));
    await tester.pumpAndSettle();
    // En los tests no hay Android: avisa en vez de fallar.
    expect(find.textContaining('solo funcionan'), findsOneWidget);
  });

  testWidgets('con letra grande no se desborda ninguna pestaña', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _abrirApp(
      tester,
      datos: (db) {
        db.movimientos.add(
          Movimiento(
            id: 1,
            tipo: 'Gasto',
            categoria: 'Entretenimiento',
            descripcion: 'Cine con amigos del trabajo',
            monto: 1234567890,
            fecha: DateTime.now(),
          ),
        );
        db.facturas.add(
          Factura(
            id: 2,
            nombre: 'Internet',
            categoria: 'Internet',
            monto: 80000,
            // Lejana: sin el banner de vencidas tapando la barra superior.
            fechaVencimiento: DateTime.now().add(const Duration(days: 20)),
            recurrente: false,
            estado: 'Pendiente',
          ),
        );
      },
    );

    for (final pestana in ['Movimientos', 'Estadísticas', 'Facturas']) {
      await tester.tap(find.widgetWithText(NavigationDestination, pestana));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Avisos de facturas'), 200);
    await tester.tap(find.text('Avisos de facturas'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
