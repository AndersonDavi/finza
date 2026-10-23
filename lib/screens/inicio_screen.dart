import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/finanzas_provider.dart';
import '../providers/preferencias_provider.dart';
import '../services/sync_service.dart';
import '../utils/estadisticas.dart';
import '../utils/estado_factura.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/lista_movimientos.dart';
import '../widgets/monto.dart';
import '../widgets/selector_periodo.dart';
import '../widgets/tarjeta_resumen.dart';
import 'home_shell.dart';

class InicioScreen extends StatelessWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final finanzas = context.watch<FinanzasProvider>();
    final periodo = context.watch<PreferenciasProvider>().periodo;

    if (finanzas.cargando) return const Esqueleto();

    final resumen = ResumenPeriodo.de(finanzas.movimientos, periodo);
    final recientes = finanzas.movimientos.take(5).toList();
    final porVencer = finanzas.facturas.where((f) {
      final estado = estadoDeFactura(f);
      return estado == EstadoFactura.vencida ||
          estado == EstadoFactura.venceHoy ||
          estado == EstadoFactura.proxima;
    }).length;

    return RefreshIndicator(
      onRefresh: () => context.read<SyncService>().sincronizar(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const SelectorPeriodo(),
          const SizedBox(height: 12),
          TarjetaBalance(
            titulo: 'Balance ${periodo.nombreCorto}',
            ingresos: resumen.ingresos,
            gastos: resumen.gastos,
            saldoTotal: finanzas.saldo,
          ),
          if (porVencer > 0) ...[
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text(
                  porVencer == 1
                      ? '1 factura vencida o por vencer'
                      : '$porVencer facturas vencidas o por vencer',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => HomeShell.tabIndex.value = HomeShell.tabFacturas,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Movimientos recientes',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (recientes.isNotEmpty)
                TextButton(
                  onPressed: () =>
                      HomeShell.tabIndex.value = HomeShell.tabMovimientos,
                  child: const Text('Ver todos'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (recientes.isEmpty)
            const Card(
              child: EstadoVacio(
                icono: Icons.account_balance_wallet_outlined,
                titulo: 'Todavía no tienes movimientos.',
                mensaje: 'Agrega tu primer ingreso o gasto.',
              ),
            )
          else
            ListaMovimientos(movimientos: recientes, comoColumna: true),
        ],
      ),
    );
  }
}
