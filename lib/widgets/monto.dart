import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/preferencias_provider.dart';
import '../utils/formato.dart';

const montoOculto = '\$ ••••';

extension MontosOcultables on BuildContext {
  /// Monto formateado, o `$ ••••` si el usuario ocultó los montos. Se usa en
  /// `build` (escucha el ajuste); en callbacks usar [formatearDinero].
  String dinero(double valor, {bool conSigno = false}) {
    if (select<PreferenciasProvider, bool>((p) => p.ocultarMontos)) {
      return montoOculto;
    }
    final signo = conSigno ? (valor < 0 ? '-' : '+') : '';
    return conSigno
        ? '$signo${formatearDinero(valor.abs())}'
        : formatearDinero(valor);
  }
}

/// Monto que cambia con una animación corta (cuenta hasta el valor nuevo).
class MontoAnimado extends StatelessWidget {
  const MontoAnimado(
    this.valor, {
    super.key,
    this.style,
    this.conSigno = false,
  });

  final double valor;
  final TextStyle? style;
  final bool conSigno;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: valor),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, actual, _) => Text(
        context.dinero(
          // Al final de la animación se muestra el valor exacto.
          actual == valor ? valor : actual.roundToDouble(),
          conSigno: conSigno,
        ),
        style: style,
      ),
    );
  }
}

/// Bloques grises que ocupan el lugar del contenido mientras carga.
class Esqueleto extends StatefulWidget {
  const Esqueleto({super.key});

  @override
  State<Esqueleto> createState() => _EsqueletoState();
}

class _EsqueletoState extends State<Esqueleto>
    with SingleTickerProviderStateMixin {
  late final _controlador = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sin animación si el sistema pide reducir el movimiento.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controlador.value = 0.5;
    } else if (!_controlador.isAnimating) {
      _controlador.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget bloque(double alto, {double? ancho}) => Container(
      height: alto,
      width: ancho,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
    );

    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_controlador),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          bloque(48),
          bloque(130),
          Row(
            children: [
              Expanded(child: bloque(90)),
              const SizedBox(width: 12),
              Expanded(child: bloque(90)),
            ],
          ),
          bloque(22, ancho: 180),
          for (var i = 0; i < 4; i++) bloque(64),
        ],
      ),
    );
  }
}
