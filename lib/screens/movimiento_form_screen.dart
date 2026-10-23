import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/categorias.dart';
import '../models/movimiento.dart';
import '../providers/finanzas_provider.dart';
import '../theme/app_theme.dart';
import '../utils/fechas.dart';
import '../utils/formato.dart';
import '../widgets/acciones.dart';

/// Crear (sin [movimiento]) o editar (con [movimiento]) un movimiento.
///
/// Pensado para registrar un gasto en segundos: arranca en Gasto, con el
/// teclado abierto en el monto, y la categoría se elige con un toque.
class MovimientoFormScreen extends StatefulWidget {
  const MovimientoFormScreen({super.key, this.movimiento});

  final Movimiento? movimiento;

  @override
  State<MovimientoFormScreen> createState() => _MovimientoFormScreenState();
}

class _MovimientoFormScreenState extends State<MovimientoFormScreen> {
  late final _descripcionController = TextEditingController(
    text: widget.movimiento?.descripcion,
  );
  late final _montoController = TextEditingController(
    text: widget.movimiento == null
        ? null
        : montoParaEditar(widget.movimiento!.monto),
  );

  late String _tipo = widget.movimiento?.tipo ?? 'Gasto';
  late String _categoria =
      widget.movimiento?.categoria ?? Categorias.deMovimiento(_tipo).first;
  late DateTime _fecha = widget.movimiento?.fecha ?? DateTime.now();

  bool _guardando = false;

  bool get _editando => widget.movimiento != null;

  List<String> get _categorias {
    final categorias = Categorias.deMovimiento(_tipo);
    // Si se renombró una categoría, la del movimiento sigue disponible.
    if (!categorias.contains(_categoria)) return [...categorias, _categoria];
    return categorias;
  }

  @override
  void dispose() {
    _descripcionController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final hoy = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime(hoy.year + 1, 12, 31),
    );

    if (fecha != null && mounted) {
      setState(() {
        // Se conserva la hora original para no desordenar los del mismo día.
        _fecha = DateTime(
          fecha.year,
          fecha.month,
          fecha.day,
          _fecha.hour,
          _fecha.minute,
          _fecha.second,
        );
      });
    }
  }

  Future<void> _guardar() async {
    final monto = leerMonto(_montoController.text);

    if (monto == null || monto <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Escribe un monto válido.')));
      return;
    }

    // Sin descripción, se usa la categoría (ej. "Transporte").
    final escrita = _descripcionController.text.trim();
    final descripcion = escrita.isEmpty ? _categoria : escrita;

    setState(() => _guardando = true);

    final base =
        widget.movimiento ??
        Movimiento(
          tipo: _tipo,
          categoria: _categoria,
          descripcion: descripcion,
          monto: monto,
          fecha: _fecha,
        );

    await context.read<FinanzasProvider>().guardarMovimiento(
      base.copyWith(
        tipo: _tipo,
        categoria: _categoria,
        descripcion: descripcion,
        monto: monto,
        fecha: _fecha,
      ),
    );

    HapticFeedback.lightImpact();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _eliminar() async {
    // Se cierra el formulario primero; el "Deshacer" se muestra en la
    // pantalla de atrás.
    final navigator = Navigator.of(context);
    final contextoAnterior = navigator.context;
    navigator.pop(false);
    await eliminarMovimientoConDeshacer(contextoAnterior, widget.movimiento!);
  }

  @override
  Widget build(BuildContext context) {
    final colores = ColoresFinza.de(context);
    final colorTipo = _tipo == 'Ingreso' ? colores.ingreso : colores.gasto;
    final esHoy = soloFecha(_fecha) == soloFecha(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar movimiento' : 'Nuevo movimiento'),
        actions: [
          if (_editando)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: _eliminar,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'Gasto',
                          label: Text('Gasto'),
                          icon: Icon(Icons.north_east),
                        ),
                        ButtonSegment(
                          value: 'Ingreso',
                          label: Text('Ingreso'),
                          icon: Icon(Icons.south_west),
                        ),
                      ],
                      selected: {_tipo},
                      onSelectionChanged: (seleccion) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _tipo = seleccion.first;
                          _categoria = Categorias.deMovimiento(_tipo).first;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _montoController,
                      autofocus: !_editando,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [FormateadorMonto()],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _guardar(),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: colorTipo,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Monto',
                        hintText: '0',
                        prefixText: '\$ ',
                        prefixStyle: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: colorTipo,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Categoría',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final categoria in _categorias)
                          ChoiceChip(
                            avatar: Icon(Categorias.icono(categoria), size: 18),
                            label: Text(categoria),
                            selected: _categoria == categoria,
                            showCheckmark: false,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              setState(() => _categoria = categoria);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _descripcionController,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _guardar(),
                      decoration: InputDecoration(
                        labelText: 'Descripción (opcional)',
                        hintText: 'Si la dejas vacía: $_categoria',
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _seleccionarFecha,
                      borderRadius: BorderRadius.circular(4),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha',
                          prefixIcon: Icon(Icons.calendar_month),
                        ),
                        child: Text(
                          esHoy
                              ? 'Hoy, ${formatearFecha(_fecha)}'
                              : formatearFecha(_fecha),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // El botón queda fijo abajo, encima del teclado.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.check),
                  label: Text(
                    _editando ? 'Guardar cambios' : 'Guardar movimiento',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
