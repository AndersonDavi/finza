import 'package:flutter/services.dart';

/// Formato colombiano: punto para miles y coma para decimales. Los centavos
/// solo se muestran si los hay. Ejemplos: 15000 -> `$15.000`,
/// 1500000.5 -> `$1.500.000,50`.
String formatearDinero(double valor) {
  final negativo = valor < 0;
  final centavos = (valor.abs() * 100).round();
  final entero = _separarMiles('${centavos ~/ 100}');
  final decimales = centavos % 100;

  return '${negativo ? '-' : ''}\$$entero'
      '${decimales == 0 ? '' : ',${decimales.toString().padLeft(2, '0')}'}';
}

/// Versión corta para ejes de gráficas: `$850 mil`, `$1,2 M`.
String formatearDineroCorto(double valor) {
  final absoluto = valor.abs();
  final signo = valor < 0 ? '-' : '';
  if (absoluto >= 1000000) {
    final millones = absoluto / 1000000;
    final texto = millones >= 10
        ? millones.round().toString()
        : millones.toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',');
    return '$signo\$$texto M';
  }
  if (absoluto >= 1000) return '$signo\$${(absoluto / 1000).round()} mil';
  return '$signo\$${absoluto.round()}';
}

String _separarMiles(String digitos) =>
    digitos.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => '.');

/// `dd/mm/aaaa`.
String formatearFecha(DateTime fecha) {
  return '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/'
      '${fecha.year}';
}

/// `hh:mm` en formato de 24 horas.
String formatearHora(DateTime fecha) {
  return '${fecha.hour.toString().padLeft(2, '0')}:'
      '${fecha.minute.toString().padLeft(2, '0')}';
}

/// Convierte lo que escribe el usuario en un monto. Acepta `80000`,
/// `80.000`, `80.000,50` y `80000.50`.
double? leerMonto(String texto) {
  var limpio = texto.trim().replaceAll(' ', '').replaceAll('\$', '');
  if (limpio.isEmpty) return null;

  if (limpio.contains(',')) {
    // Formato colombiano: los puntos son miles y la coma es el decimal.
    limpio = limpio.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(limpio)) {
    // `80.000` o `1.500.000`: puntos de miles sin decimales.
    limpio = limpio.replaceAll('.', '');
  }

  return double.tryParse(limpio);
}

/// Texto para un monto en un campo editable, en el mismo formato que deja
/// [FormateadorMonto] (`80.000` o `80.000,5`).
String montoParaEditar(double monto) {
  final partes = monto.toStringAsFixed(2).split('.');
  final entero = _separarMiles(partes[0]);
  final decimales = partes[1].replaceFirst(RegExp(r'0+$'), '');
  return decimales.isEmpty ? entero : '$entero,$decimales';
}

/// Separa los miles mientras se escribe el monto (`15000` -> `15.000`).
///
/// Como el punto es el separador de miles, la coma es el decimal. Algunos
/// teclados numéricos de Android solo tienen punto: si el usuario lo escribe
/// al final, se toma como la coma decimal.
class FormateadorMonto extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var texto = newValue.text;
    if (texto.endsWith('.') &&
        texto.length > oldValue.text.length &&
        !texto.contains(',')) {
      texto = '${texto.substring(0, texto.length - 1)},';
    }

    final coma = texto.indexOf(',');
    var entero = (coma == -1 ? texto : texto.substring(0, coma)).replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final decimales = coma == -1
        ? null
        : texto.substring(coma + 1).replaceAll(RegExp(r'[^0-9]'), '');

    entero = entero.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (entero.isEmpty && decimales != null) entero = '0';
    if (entero.length > 13) return oldValue;

    final resultado =
        _separarMiles(entero) +
        (decimales == null
            ? ''
            : ',${decimales.length > 2 ? decimales.substring(0, 2) : decimales}');

    return TextEditingValue(
      text: resultado,
      selection: TextSelection.collapsed(offset: resultado.length),
    );
  }
}
