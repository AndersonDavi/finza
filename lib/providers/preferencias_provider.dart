import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/config_recordatorios.dart';
import '../models/filtro_movimientos.dart';
import '../models/periodo.dart';

/// Preferencias que se guardan en el teléfono (no se sincronizan con Drive).
class PreferenciasProvider extends ChangeNotifier {
  PreferenciasProvider(this._prefs) {
    _modoTema =
        ThemeMode.values.asNameMap()[_prefs.getString(_claveTema)] ??
        ThemeMode.system;
    _recordatoriosActivos = _prefs.getBool(_claveRecordatorios) ?? true;
    _ocultarMontos = _prefs.getBool(_claveOcultarMontos) ?? false;
    _bienvenidaVista = _prefs.getBool(_claveBienvenida) ?? false;

    // Si el formato cambió entre versiones, se usan los valores por defecto.
    final filtro = _leerJson(_claveFiltro);
    if (filtro != null) _filtroMovimientos = FiltroMovimientos.fromJson(filtro);
    final config = _leerJson(_claveConfigRecordatorios);
    if (config != null) {
      _configRecordatorios = ConfigRecordatorios.fromJson(config);
    }
    final periodo = _leerJson(_clavePeriodo);
    if (periodo != null) _periodo = Periodo.fromJson(periodo);
  }

  Map<String, dynamic>? _leerJson(String clave) {
    final guardado = _prefs.getString(clave);
    if (guardado == null) return null;
    try {
      return jsonDecode(guardado) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static const _claveTema = 'tema';
  static const _claveRecordatorios = 'recordatorios_activos';
  static const _claveFiltro = 'filtro_movimientos';
  static const _claveConfigRecordatorios = 'config_recordatorios';
  static const _claveOcultarMontos = 'ocultar_montos';
  static const _claveBienvenida = 'bienvenida_vista';
  static const _clavePeriodo = 'periodo_resumen';

  final SharedPreferences _prefs;

  SharedPreferences get prefs => _prefs;

  late ThemeMode _modoTema;
  late bool _recordatoriosActivos;
  late bool _ocultarMontos;
  late bool _bienvenidaVista;
  FiltroMovimientos _filtroMovimientos = const FiltroMovimientos();
  ConfigRecordatorios _configRecordatorios = const ConfigRecordatorios();
  Periodo _periodo = Periodo.mesActual();

  ThemeMode get modoTema => _modoTema;
  bool get recordatoriosActivos => _recordatoriosActivos;
  FiltroMovimientos get filtroMovimientos => _filtroMovimientos;
  ConfigRecordatorios get configRecordatorios => _configRecordatorios;

  /// Muestra `$ ••••` en vez de los montos (para usar la app en público).
  bool get ocultarMontos => _ocultarMontos;

  /// La bienvenida se muestra solo la primera vez que se abre la app.
  bool get bienvenidaVista => _bienvenidaVista;

  /// Periodo que muestran Inicio y Estadísticas (el mismo en las dos).
  Periodo get periodo => _periodo;

  set modoTema(ThemeMode modo) {
    _modoTema = modo;
    _prefs.setString(_claveTema, modo.name);
    notifyListeners();
  }

  set recordatoriosActivos(bool activos) {
    _recordatoriosActivos = activos;
    _prefs.setBool(_claveRecordatorios, activos);
    notifyListeners();
  }

  set configRecordatorios(ConfigRecordatorios config) {
    _configRecordatorios = config;
    _prefs.setString(_claveConfigRecordatorios, jsonEncode(config.toJson()));
    notifyListeners();
  }

  set ocultarMontos(bool ocultar) {
    _ocultarMontos = ocultar;
    _prefs.setBool(_claveOcultarMontos, ocultar);
    notifyListeners();
  }

  set bienvenidaVista(bool vista) {
    _bienvenidaVista = vista;
    _prefs.setBool(_claveBienvenida, vista);
    notifyListeners();
  }

  set periodo(Periodo periodo) {
    _periodo = periodo;
    _prefs.setString(_clavePeriodo, jsonEncode(periodo.toJson()));
    notifyListeners();
  }

  set filtroMovimientos(FiltroMovimientos filtro) {
    _filtroMovimientos = filtro;
    _prefs.setString(_claveFiltro, jsonEncode(filtro.toJson()));
    notifyListeners();
  }
}
