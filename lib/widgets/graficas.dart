import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/periodo.dart';
import '../theme/app_theme.dart';
import '../utils/formato.dart';

/// Colores de las categorías en la dona. Tonos medios que se leen en claro
/// y en oscuro; se repiten si hay más categorías que colores.
const coloresCategorias = [
  Color(0xFF1B8A5A),
  Color(0xFF3F7DD8),
  Color(0xFFE08A1E),
  Color(0xFF9B59B6),
  Color(0xFFD64545),
  Color(0xFF2BA3A3),
  Color(0xFFC2A01F),
  Color(0xFF7F8C8D),
];

Color colorCategoria(int indice) =>
    coloresCategorias[indice % coloresCategorias.length];

/// Dona de gastos por categoría. [valores] en el mismo orden que los colores
/// de [colorCategoria]. En el centro va [centro] (ej. el total).
class GraficaDona extends StatelessWidget {
  const GraficaDona({
    super.key,
    required this.valores,
    required this.centro,
    this.descripcion,
  });

  final List<double> valores;
  final Widget centro;
  final String? descripcion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: descripcion,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, progreso, child) => CustomPaint(
          painter: _PintorDona(
            valores,
            progreso,
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: child,
        ),
        child: SizedBox.square(
          dimension: 180,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: FittedBox(fit: BoxFit.scaleDown, child: centro),
            ),
          ),
        ),
      ),
    );
  }
}

class _PintorDona extends CustomPainter {
  _PintorDona(this.valores, this.progreso, this.fondo);

  final List<double> valores;
  final double progreso;
  final Color fondo;

  @override
  void paint(Canvas canvas, Size size) {
    const grosor = 26.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - grosor / 2,
    );
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor;

    canvas.drawArc(rect, 0, math.pi * 2, false, pincel..color = fondo);

    final total = valores.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;

    // Un pequeño espacio entre segmentos si hay más de uno.
    final espacio = valores.where((v) => v > 0).length > 1 ? 0.025 : 0.0;
    var inicio = -math.pi / 2;
    for (var i = 0; i < valores.length; i++) {
      final barrido = valores[i] / total * math.pi * 2 * progreso;
      if (barrido > espacio) {
        canvas.drawArc(
          rect,
          inicio + espacio / 2,
          barrido - espacio,
          false,
          pincel..color = colorCategoria(i),
        );
      }
      inicio += barrido;
    }
  }

  @override
  bool shouldRepaint(_PintorDona anterior) =>
      anterior.progreso != progreso ||
      anterior.fondo != fondo ||
      !_mismosValores(anterior.valores, valores);
}

bool _mismosValores(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Barras de ingresos y gastos por mes.
class GraficaMeses extends StatelessWidget {
  const GraficaMeses({
    super.key,
    required this.meses,
    this.ocultarMontos = false,
  });

  final List<({DateTime mes, double ingresos, double gastos})> meses;
  final bool ocultarMontos;

  @override
  Widget build(BuildContext context) {
    final colores = ColoresFinza.de(context);
    final tema = Theme.of(context);
    final maximo = meses.fold<double>(
      0,
      (m, x) => math.max(m, math.max(x.ingresos, x.gastos)),
    );

    final descripcion = meses
        .map(
          (m) =>
              '${nombresMeses[m.mes.month - 1]}: ingresos '
              '${formatearDinero(m.ingresos)}, gastos ${formatearDinero(m.gastos)}',
        )
        .join('. ');

    return Semantics(
      label: ocultarMontos ? 'Gráfica de los últimos meses' : descripcion,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!ocultarMontos && maximo > 0)
            Text(
              'Máximo: ${formatearDineroCorto(maximo)}',
              style: tema.textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, progreso, _) => CustomPaint(
                size: Size.infinite,
                painter: _PintorBarras(
                  meses: meses,
                  maximo: maximo,
                  progreso: progreso,
                  colorIngreso: colores.ingreso,
                  colorGasto: colores.gasto,
                  colorLinea: tema.colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final m in meses)
                Expanded(
                  child: Text(
                    nombresMeses[m.mes.month - 1].substring(0, 3),
                    textAlign: TextAlign.center,
                    style: tema.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Leyenda(color: colores.ingreso, texto: 'Ingresos'),
              const SizedBox(width: 16),
              _Leyenda(color: colores.gasto, texto: 'Gastos'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(texto),
      ],
    );
  }
}

class _PintorBarras extends CustomPainter {
  _PintorBarras({
    required this.meses,
    required this.maximo,
    required this.progreso,
    required this.colorIngreso,
    required this.colorGasto,
    required this.colorLinea,
  });

  final List<({DateTime mes, double ingresos, double gastos})> meses;
  final double maximo;
  final double progreso;
  final Color colorIngreso;
  final Color colorGasto;
  final Color colorLinea;

  @override
  void paint(Canvas canvas, Size size) {
    final linea = Paint()
      ..color = colorLinea
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      linea,
    );
    if (maximo <= 0 || meses.isEmpty) return;

    final anchoMes = size.width / meses.length;
    final anchoBarra = math.min(14.0, anchoMes / 3);

    void barra(double x, double valor, Color color) {
      final alto = valor / maximo * size.height * progreso;
      if (alto <= 0) return;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, size.height - alto, anchoBarra, alto),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()..color = color,
      );
    }

    for (var i = 0; i < meses.length; i++) {
      final centro = anchoMes * i + anchoMes / 2;
      barra(centro - anchoBarra - 1, meses[i].ingresos, colorIngreso);
      barra(centro + 1, meses[i].gastos, colorGasto);
    }
  }

  @override
  bool shouldRepaint(_PintorBarras anterior) =>
      anterior.progreso != progreso ||
      anterior.maximo != maximo ||
      anterior.colorIngreso != colorIngreso ||
      anterior.meses != meses;
}
