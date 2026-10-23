import 'package:flutter/material.dart';

/// Catálogos de la app, en un solo lugar para formularios y filtros.
class Categorias {
  Categorias._();

  static const ingresos = ['Salario', 'Freelance', 'Negocio', 'Otros'];

  static const gastos = [
    'Alimentación',
    'Transporte',
    'Vivienda',
    'Servicios',
    'Entretenimiento',
    'Otros',
  ];

  static const facturas = [
    'Servicios',
    'Vivienda',
    'Internet',
    'Telefonía',
    'Suscripciones',
    'Transporte',
    'Otros',
  ];

  static const frecuencias = ['Semanal', 'Mensual', 'Trimestral', 'Anual'];

  static List<String> deMovimiento(String tipo) =>
      tipo == 'Ingreso' ? ingresos : gastos;

  /// Todas las categorías de movimientos, sin repetir (para filtros).
  static List<String> get todasDeMovimientos =>
      {...ingresos, ...gastos}.toList();

  static const _iconos = {
    'Salario': Icons.work_outline,
    'Freelance': Icons.laptop_mac,
    'Negocio': Icons.storefront_outlined,
    'Alimentación': Icons.restaurant,
    'Transporte': Icons.directions_bus_outlined,
    'Vivienda': Icons.home_outlined,
    'Servicios': Icons.lightbulb_outline,
    'Entretenimiento': Icons.movie_outlined,
    'Internet': Icons.wifi,
    'Telefonía': Icons.phone_android,
    'Suscripciones': Icons.subscriptions_outlined,
  };

  /// Ícono de una categoría (de movimiento o de factura). Las que no están
  /// en el catálogo (ej. renombradas) usan uno genérico.
  static IconData icono(String categoria) =>
      _iconos[categoria] ?? Icons.category_outlined;
}
