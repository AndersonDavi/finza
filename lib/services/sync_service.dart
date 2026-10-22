import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../database/database_helper.dart';
import '../models/factura.dart';
import '../models/movimiento.dart';
import '../providers/finanzas_provider.dart';
import 'drive_api.dart';
import 'sincronizacion.dart';

enum EstadoSync {
  /// Falta el Client ID de Google al compilar (ver AppConfig).
  noConfigurado,

  /// No hay cuenta de Google conectada.
  desconectado,

  /// Hay cuenta, pero falta (o se revocó) el permiso de Drive.
  sinPermiso,
  listo,
  sincronizando,
  error,
}

/// Sincroniza los datos con un archivo en el Drive del usuario, sin backend.
///
/// Usa el permiso `drive.file`: la app solo puede ver y modificar los
/// archivos que ella misma creó (acá, `finza_datos.json`), nada más del
/// Drive del usuario.
class SyncService extends ChangeNotifier {
  SyncService(this._finanzas, this._prefs, {DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance {
    final ultima = _prefs.getString(_claveUltima);
    ultimaSincronizacion = ultima == null ? null : DateTime.parse(ultima);
  }

  static const nombreArchivo = 'finza_datos.json';
  static const _scopes = ['https://www.googleapis.com/auth/drive.file'];
  static const _claveArchivoId = 'drive_archivo_id';
  static const _claveUltima = 'drive_ultima_sincronizacion';

  final FinanzasProvider _finanzas;
  final SharedPreferences _prefs;
  final DatabaseHelper _db;
  final _googleSignIn = GoogleSignIn.instance;

  EstadoSync estado = AppConfig.syncConfigurado
      ? EstadoSync.desconectado
      : EstadoSync.noConfigurado;
  GoogleSignInAccount? cuenta;
  DateTime? ultimaSincronizacion;
  String? error;

  bool _inicializado = false;
  bool _pendiente = false;
  Timer? _temporizador;
  Future<void>? _enCurso;

  bool get conectado => cuenta != null;

  Future<void> inicializar() async {
    if (!AppConfig.syncConfigurado || _inicializado) return;
    _inicializado = true;

    try {
      await _googleSignIn.initialize(
        serverClientId: AppConfig.googleServerClientId,
      );
      // Recupera la sesión anterior sin mostrar nada.
      final account = await _googleSignIn.attemptLightweightAuthentication();
      if (account != null) {
        cuenta = account;
        await sincronizar();
      }
    } catch (e) {
      _fallo('No se pudo iniciar Google: $e');
    }
  }

  /// Conecta una cuenta de Google y pide el permiso de Drive. Debe llamarse
  /// desde un botón (muestra la interfaz de Google).
  Future<void> conectar() async {
    if (!AppConfig.syncConfigurado) return;
    await inicializar();

    try {
      cuenta = await _googleSignIn.authenticate(scopeHint: _scopes);
      await cuenta!.authorizationClient.authorizeScopes(_scopes);
      error = null;
      await sincronizar();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        estado = cuenta == null
            ? EstadoSync.desconectado
            : EstadoSync.sinPermiso;
        notifyListeners();
        return;
      }
      _fallo('No se pudo conectar con Google: ${e.description ?? e.code.name}');
    } catch (e) {
      _fallo('No se pudo conectar con Google: $e');
    }
  }

  /// Cierra la sesión. Los datos del teléfono y el archivo de Drive quedan
  /// como están.
  Future<void> desconectar() async {
    _temporizador?.cancel();
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      // Si falla la revocación, igual se olvida la cuenta localmente.
    }
    cuenta = null;
    error = null;
    estado = EstadoSync.desconectado;
    await _prefs.remove(_claveArchivoId);
    notifyListeners();
  }

  /// Agenda una sincronización unos segundos después del último cambio, para
  /// no subir el archivo en cada tecla.
  void programarSincronizacion() {
    if (!conectado) return;
    _temporizador?.cancel();
    _temporizador = Timer(const Duration(seconds: 3), sincronizar);
  }

  /// Baja el archivo de Drive, lo combina con los datos locales y sube el
  /// resultado si hay algo nuevo acá. Si ya hay una en curso, se repite al
  /// terminar.
  Future<void> sincronizar() async {
    if (!conectado) return;

    if (_enCurso != null) {
      _pendiente = true;
      return _enCurso;
    }

    _enCurso = _sincronizarConReintento();
    try {
      await _enCurso;
    } finally {
      _enCurso = null;
    }

    if (_pendiente) {
      _pendiente = false;
      await sincronizar();
    }
  }

  Future<void> _sincronizarConReintento() async {
    estado = EstadoSync.sincronizando;
    error = null;
    notifyListeners();

    try {
      final token = await _tokenDeAcceso();
      if (token == null) {
        estado = EstadoSync.sinPermiso;
        notifyListeners();
        return;
      }

      try {
        await sincronizarCon(DriveApi(token));
      } on DriveException catch (e) {
        if (!e.noAutorizado) rethrow;
        // Token vencido: se descarta y se intenta una vez con uno nuevo.
        await cuenta!.authorizationClient.clearAuthorizationToken(
          accessToken: token,
        );
        final nuevo = await _tokenDeAcceso();
        if (nuevo == null) {
          estado = EstadoSync.sinPermiso;
          notifyListeners();
          return;
        }
        await sincronizarCon(DriveApi(nuevo));
      }

      ultimaSincronizacion = DateTime.now();
      await _prefs.setString(
        _claveUltima,
        ultimaSincronizacion!.toIso8601String(),
      );
      estado = EstadoSync.listo;
      notifyListeners();
    } catch (e) {
      _fallo(e is DriveException ? e.mensaje : '$e');
    }
  }

  /// Token de Drive sin mostrar interfaz, o null si hace falta pedir permiso.
  Future<String?> _tokenDeAcceso() async {
    final autorizacion = await cuenta!.authorizationClient
        .authorizationForScopes(_scopes);
    return autorizacion?.accessToken;
  }

  /// Un ciclo de sincronización con [drive]. Público solo para los tests.
  @visibleForTesting
  Future<void> sincronizarCon(DriveApi drive) async {
    var archivoId = _prefs.getString(_claveArchivoId);
    String? contenido;

    if (archivoId != null) {
      contenido = await drive.descargar(archivoId);
      if (contenido == null) archivoId = null; // Se borró en Drive.
    }
    if (archivoId == null) {
      archivoId = await drive.buscarArchivo(nombreArchivo);
      if (archivoId != null) contenido = await drive.descargar(archivoId);
    }

    final remoto = contenido == null
        ? ArchivoSincronizacion(movimientos: [], facturas: [])
        : ArchivoSincronizacion.fromJson(
            jsonDecode(contenido) as Map<String, dynamic>,
          );

    if (remoto.esDeUnaVersionMasNueva) {
      throw Exception(
        'Los datos de Drive son de una versión más nueva de Finza. '
        'Actualiza la app para sincronizar.',
      );
    }

    final local = await _db.exportarParaSincronizar();
    final movimientos = combinarRegistros(
      local['movimientos']!,
      remoto.movimientos,
    );
    final facturas = combinarRegistros(local['facturas']!, remoto.facturas);

    if (movimientos.paraAplicarLocal.isNotEmpty ||
        facturas.paraAplicarLocal.isNotEmpty) {
      await _db.aplicarCambiosRemotos(
        movimientos: movimientos.paraAplicarLocal
            .map(Movimiento.fromJson)
            .toList(),
        facturas: facturas.paraAplicarLocal.map(Factura.fromJson).toList(),
      );
      await _finanzas.cargar();
    }

    if (archivoId == null || movimientos.hayQueSubir || facturas.hayQueSubir) {
      final nuevoContenido = jsonEncode(
        ArchivoSincronizacion(
          movimientos: movimientos.combinados,
          facturas: facturas.combinados,
        ).toJson(),
      );

      if (archivoId == null ||
          !await drive.actualizar(archivoId, nuevoContenido)) {
        archivoId = await drive.crear(nombreArchivo, nuevoContenido);
      }
    }

    await _prefs.setString(_claveArchivoId, archivoId);
  }

  void _fallo(String mensaje) {
    debugPrint('Sincronización: $mensaje');
    error = mensaje;
    estado = EstadoSync.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }
}
