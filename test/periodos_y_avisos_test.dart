import 'package:finza/models/config_recordatorios.dart';
import 'package:finza/models/factura.dart';
import 'package:finza/models/movimiento.dart';
import 'package:finza/models/periodo.dart';
import 'package:finza/services/recordatorios_service.dart';
import 'package:finza/utils/estadisticas.dart';
import 'package:finza/utils/formato.dart';
import 'package:finza/widgets/lista_movimientos.dart';
import 'package:flutter_test/flutter_test.dart';

Movimiento _mov(String tipo, String categoria, double monto, DateTime fecha) =>
    Movimiento(
      tipo: tipo,
      categoria: categoria,
      descripcion: categoria,
      monto: monto,
      fecha: fecha,
    );

Factura _factura(DateTime vence, {String estado = 'Pendiente'}) => Factura(
  nombre: 'Internet',
  categoria: 'Internet',
  monto: 80000,
  fechaVencimiento: vence,
  recurrente: false,
  estado: estado,
);

void main() {
  group('Periodo', () {
    test('mes: contiene, etiqueta y flechas cruzando el año', () {
      final enero = Periodo.mes(2027, 1);
      expect(enero.etiqueta, 'Enero 2027');
      expect(enero.contiene(DateTime(2027, 1, 31, 23, 59)), isTrue);
      expect(enero.contiene(DateTime(2027, 2, 1)), isFalse);
      expect(enero.anterior, Periodo.mes(2026, 12));
      expect(enero.anterior.etiqueta, 'Diciembre 2026');
    });

    test('año', () {
      final anio = Periodo.anio(2026);
      expect(anio.etiqueta, '2026');
      expect(anio.contiene(DateTime(2026, 12, 31, 23)), isTrue);
      expect(anio.siguiente, Periodo.anio(2027));
    });

    test('rango de meses incluye los dos meses y se desplaza en bloque', () {
      final rango = Periodo.rangoMeses(DateTime(2026, 8), DateTime(2026, 10));
      expect(rango.etiqueta, 'Ago – Oct 2026');
      expect(rango.contiene(DateTime(2026, 10, 31, 22)), isTrue);
      expect(rango.contiene(DateTime(2026, 11, 1)), isFalse);
      expect(
        rango.anterior,
        Periodo.rangoMeses(DateTime(2026, 5), DateTime(2026, 7)),
      );
      expect(
        Periodo.rangoMeses(DateTime(2026, 11), DateTime(2027, 2)).etiqueta,
        'Nov 2026 – Feb 2027',
      );
    });

    test('rango de fechas incluye el último día y acepta el orden inverso', () {
      final rango = Periodo.rangoFechas(
        DateTime(2026, 10, 15),
        DateTime(2026, 10, 1),
      );
      expect(rango.etiqueta, '01/10/2026 – 15/10/2026');
      expect(rango.contiene(DateTime(2026, 10, 15, 23, 59)), isTrue);
      expect(rango.contiene(DateTime(2026, 10, 16)), isFalse);
      expect(rango.ultimoDia, DateTime(2026, 10, 15));
      // 15 días antes: del 16 al 30 de septiembre.
      expect(
        rango.anterior,
        Periodo.rangoFechas(DateTime(2026, 9, 16), DateTime(2026, 9, 30)),
      );
    });

    test('todo el historial', () {
      expect(Periodo.total.contiene(DateTime(1990)), isTrue);
      expect(Periodo.total.anterior, Periodo.total);
      expect(Periodo.total.etiqueta, 'Todo el historial');
    });

    test('al guardarse, mes y año vuelven al actual; los rangos se quedan', () {
      final hoy = DateTime(2027, 3, 5);
      expect(
        Periodo.fromJson(Periodo.mes(2026, 1).toJson(), hoy: hoy),
        Periodo.mes(2027, 3),
      );
      expect(
        Periodo.fromJson(Periodo.anio(2020).toJson(), hoy: hoy),
        Periodo.anio(2027),
      );
      final rango = Periodo.rangoFechas(
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 3),
      );
      expect(Periodo.fromJson(rango.toJson(), hoy: hoy), rango);
      expect(
        Periodo.fromJson({'tipo': 'raro'}, hoy: hoy),
        Periodo.mes(2027, 3),
      );
    });
  });

  group('estadísticas', () {
    final movimientos = [
      _mov('Ingreso', 'Salario', 2000000, DateTime(2026, 10, 1)),
      _mov('Gasto', 'Alimentación', 300000, DateTime(2026, 10, 5)),
      _mov('Gasto', 'Transporte', 100000, DateTime(2026, 10, 6)),
      _mov('Gasto', 'Transporte', 50000, DateTime(2026, 10, 7)),
      _mov('Ingreso', 'Salario', 2000000, DateTime(2026, 9, 1)),
      _mov('Gasto', 'Alimentación', 400000, DateTime(2026, 9, 5)),
      _mov('Gasto', 'Transporte', 20000, DateTime(2026, 9, 6)),
    ];

    test('resumen de un periodo, con categorías de mayor a menor', () {
      final octubre = ResumenPeriodo.de(movimientos, Periodo.mes(2026, 10));
      expect(octubre.ingresos, 2000000);
      expect(octubre.gastos, 450000);
      expect(octubre.balance, 1550000);
      expect(octubre.proporcionGastada, closeTo(0.225, 1e-9));
      expect(octubre.gastosPorCategoria.keys, ['Alimentación', 'Transporte']);

      final vacio = ResumenPeriodo.de(movimientos, Periodo.mes(2026, 1));
      expect(vacio.proporcionGastada, isNull);
    });

    test('categorías que crecieron respecto al periodo anterior', () {
      final crecieron = categoriasQueCrecieron(
        ResumenPeriodo.de(movimientos, Periodo.mes(2026, 10)),
        ResumenPeriodo.de(movimientos, Periodo.mes(2026, 9)),
      );
      // Alimentación bajó; Transporte subió de 20.000 a 150.000.
      expect(crecieron.single.categoria, 'Transporte');
      expect(crecieron.single.anterior, 20000);
    });

    test('variación', () {
      expect(variacion(120, 100), closeTo(0.2, 1e-9));
      expect(variacion(50, 0), isNull);
    });

    test('totales de los últimos meses, del más antiguo al más reciente', () {
      final meses = totalesPorMes(
        movimientos,
        hasta: DateTime(2026, 10, 20),
        cantidad: 3,
      );
      expect(meses.map((m) => m.mes), [
        DateTime(2026, 8),
        DateTime(2026, 9),
        DateTime(2026, 10),
      ]);
      expect(meses[1].gastos, 420000);
      expect(meses[2].ingresos, 2000000);
      expect(meses[0].ingresos, 0);
    });
  });

  group('avisos de facturas', () {
    final ahora = DateTime(2026, 10, 22, 12);

    test('a la hora y con los días elegidos, solo los futuros', () {
      final avisos = calcularAvisos(
        [_factura(DateTime(2026, 10, 30))],
        const ConfigRecordatorios(
          hora: 7,
          minuto: 30,
          diasAntes: {0, 3, 7, 15},
        ),
        ahora: ahora,
      );
      // 15 días antes ya pasó (15 de octubre).
      expect(avisos.map((a) => a.cuando), [
        DateTime(2026, 10, 23, 7, 30),
        DateTime(2026, 10, 27, 7, 30),
        DateTime(2026, 10, 30, 7, 30),
      ]);
      expect(avisos.map((a) => a.titulo), [
        'Internet vence en 7 días',
        'Internet vence en 3 días',
        'Internet vence hoy',
      ]);
    });

    test('las pagadas no avisan', () {
      expect(
        calcularAvisos(
          [_factura(DateTime(2026, 10, 30), estado: 'Pagada')],
          const ConfigRecordatorios(),
          ahora: ahora,
        ),
        isEmpty,
      );
    });

    test('si está vencida, sigue avisando cada día', () {
      final avisos = calcularAvisos(
        [_factura(DateTime(2026, 10, 20))],
        const ConfigRecordatorios(diasAntes: {}, insistirVencidas: true),
        ahora: ahora,
      );
      // Del 23 al 27 (7 días después del 20), a las 9:00.
      expect(avisos.first.cuando, DateTime(2026, 10, 23, 9));
      expect(avisos.first.titulo, 'Internet lleva 3 días vencida');
      expect(avisos.last.cuando, DateTime(2026, 10, 27, 9));
      expect(avisos, hasLength(5));
    });

    test('textos', () {
      final f = _factura(DateTime(2026, 10, 30));
      expect(textoAviso(f, 1).titulo, 'Internet vence mañana');
      expect(textoAviso(f, 1).cuerpo, 'Pago de \$80.000.');
      expect(textoAviso(f, -1).titulo, 'Internet lleva 1 día vencida');
    });

    test('descripción y guardado de la configuración', () {
      expect(
        const ConfigRecordatorios().descripcionDias,
        'El mismo día, el día antes',
      );
      expect(
        const ConfigRecordatorios(
          diasAntes: {3, 1},
          insistirVencidas: true,
        ).descripcionDias,
        '1 y 3 días antes, a diario si se vence',
      );
      expect(
        const ConfigRecordatorios(diasAntes: {}).descripcionDias,
        'Sin avisos',
      );

      const config = ConfigRecordatorios(
        hora: 20,
        minuto: 15,
        diasAntes: {0, 5},
        insistirVencidas: true,
      );
      final leida = ConfigRecordatorios.fromJson(config.toJson());
      expect(leida.hora, 20);
      expect(leida.minuto, 15);
      expect(leida.diasAntes, {0, 5});
      expect(leida.insistirVencidas, isTrue);
    });
  });

  group('FormateadorMonto', () {
    String escribir(String antes, String despues) => FormateadorMonto()
        .formatEditUpdate(
          TextEditingValue(text: antes),
          TextEditingValue(text: despues),
        )
        .text;

    test('separa los miles mientras se escribe', () {
      expect(escribir('1.500', '1.5000'), '15.000');
      expect(escribir('', '1500000'), '1.500.000');
      expect(escribir('15.000', '15.00'), '1.500');
      expect(escribir('', '007'), '7');
    });

    test('coma decimal, y el punto al final también cuenta como coma', () {
      expect(escribir('15.000', '15.000,'), '15.000,');
      expect(escribir('15.000,5', '15.000,555'), '15.000,55');
      expect(escribir('15.000', '15.000.'), '15.000,');
      expect(escribir('', ','), '0,');
    });

    test('lo que deja se lee bien', () {
      for (final texto in ['15.000', '1.500.000,5', '0,25']) {
        expect(leerMonto(texto), isNotNull);
      }
      expect(montoParaEditar(1500000), '1.500.000');
      expect(montoParaEditar(80000.5), '80.000,5');
    });
  });

  test('nombre del día en las listas agrupadas', () {
    final hoy = DateTime(2026, 10, 22, 18);
    expect(nombreDelDia(DateTime(2026, 10, 22, 1), hoy: hoy), 'Hoy');
    expect(nombreDelDia(DateTime(2026, 10, 21), hoy: hoy), 'Ayer');
    expect(nombreDelDia(DateTime(2026, 10, 19), hoy: hoy), 'Lun 19 oct');
    expect(nombreDelDia(DateTime(2025, 12, 31), hoy: hoy), 'Mié 31 dic 2025');
  });

  test('montos cortos para las gráficas', () {
    expect(formatearDineroCorto(850000), '\$850 mil');
    expect(formatearDineroCorto(1200000), '\$1,2 M');
    expect(formatearDineroCorto(2000000), '\$2 M');
    expect(formatearDineroCorto(15000000), '\$15 M');
    expect(formatearDineroCorto(500), '\$500');
  });
}
