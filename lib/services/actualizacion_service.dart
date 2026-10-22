import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../models/actualizacion.dart';

/// Revisa si hay una versión nueva del APK publicada en el repo de GitHub.
///
/// `release.ps1` deja en `releases/latest.json` la versión, el versionCode,
/// la URL del APK y los cambios. Si el versionCode publicado es mayor que el
/// de la app instalada, hay actualización.
class ActualizacionService {
  ActualizacionService._();

  static const String urlUltimaVersion =
      'https://raw.githubusercontent.com/Isaito05/finza/master/releases/latest.json';

  static Future<Actualizacion?> buscarActualizacion() async {
    final respuesta = await http
        .get(Uri.parse(urlUltimaVersion))
        .timeout(const Duration(seconds: 10));

    // 404 = todavía no se ha publicado ninguna versión.
    if (respuesta.statusCode != 200) return null;

    final datos = jsonDecode(utf8.decode(respuesta.bodyBytes));
    final actualizacion = Actualizacion.fromMap(datos as Map<String, dynamic>);

    final buildActual = int.tryParse(AppInfo.buildNumber) ?? 0;
    if (actualizacion.versionCode <= buildActual) return null;

    return actualizacion;
  }

  static Future<void> abrirDescarga(String apkUrl) {
    return launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
  }
}
