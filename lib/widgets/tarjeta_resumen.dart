import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'monto.dart';

/// Tarjeta de total de ingresos o de gastos (Estadísticas).
class TarjetaResumen extends StatelessWidget {
  const TarjetaResumen({
    super.key,
    required this.esIngreso,
    required this.valor,
  });

  final bool esIngreso;
  final double valor;

  @override
  Widget build(BuildContext context) {
    final colores = ColoresFinza.de(context);
    final color = esIngreso ? colores.ingreso : colores.gasto;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              esIngreso ? Icons.south_west : Icons.north_east,
              color: color,
              size: 26,
            ),
            const SizedBox(height: 8),
            Text(
              esIngreso ? 'Ingresos' : 'Gastos',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: MontoAnimado(
                valor,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta principal de Inicio: balance del periodo, sus ingresos y gastos,
/// y el saldo acumulado como dato secundario.
class TarjetaBalance extends StatelessWidget {
  const TarjetaBalance({
    super.key,
    required this.titulo,
    required this.ingresos,
    required this.gastos,
    required this.saldoTotal,
  });

  final String titulo;
  final double ingresos;
  final double gastos;
  final double saldoTotal;

  @override
  Widget build(BuildContext context) {
    final colores = ColoresFinza.de(context);
    final balance = ingresos - gastos;

    Widget total(bool esIngreso, double valor) {
      final color = esIngreso ? colores.ingreso : colores.gasto;
      return Expanded(
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: 0.15),
              foregroundColor: color,
              child: Icon(
                esIngreso ? Icons.south_west : Icons.north_east,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(esIngreso ? 'Ingresos' : 'Gastos'),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: MontoAnimado(
                      valor,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MontoAnimado(
                balance,
                conSigno: balance != 0,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: balance < 0 ? colores.gasto : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                total(true, ingresos),
                const SizedBox(width: 12),
                total(false, gastos),
              ],
            ),
            const Divider(height: 28),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Saldo total')),
                MontoAnimado(
                  saldoTotal,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: saldoTotal < 0 ? colores.gasto : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
