class Actualizacion {
  final String version;
  final int versionCode;
  final String apkUrl;
  final String? cambios;

  Actualizacion({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    this.cambios,
  });

  factory Actualizacion.fromMap(Map<String, dynamic> map) {
    return Actualizacion(
      version: map['version'] as String,
      versionCode: map['versionCode'] as int,
      apkUrl: map['apkUrl'] as String,
      cambios: map['changelog'] as String?,
    );
  }
}
