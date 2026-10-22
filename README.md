# Finza

**Controla tu dinero, alcanza tus metas.**

App Android para manejar finanzas personales: registrar ingresos y gastos,
llevar el control de facturas y sus vencimientos, y ver estadísticas.
Proyecto universitario: *"Finza: Aplicación móvil para la gestión y control de
las finanzas personales mediante el seguimiento de ingresos, gastos, facturas y
metas de ahorro"*.

No usa backend ni cuenta: todo se guarda en el teléfono (SQLite). No se
distribuye por Play Store: se instala el APK desde este repo y la app avisa
sola cuando hay una versión nueva.

Más contexto del proyecto (decisiones, incidencias resueltas, próximos pasos)
en [`Contexto_Finza.md`](Contexto_Finza.md).

## Funcionalidades
- **Inicio:** saldo, total de ingresos y gastos, y los movimientos recientes.
- **Movimientos:** registrar ingresos y gastos por categoría, buscar por descripción o categoría, filtrar por tipo y eliminar.
- **Estadísticas:** totales, saldo, comparación ingresos vs. gastos y gastos por categoría.
- **Facturas:**
  - con categoría, vencimiento y recurrencia (semanal, mensual, trimestral, anual);
  - pendientes y pagadas, con el monto total pendiente;
  - estados según la fecha: *Vencida*, *Vence hoy*, *Próxima* (3 días) y *Pendiente*;
  - marcar como pagada.
- **Moneda** en formato colombiano (`$1.500.000,50`).
- **Actualizaciones:** al abrir, la app revisa si hay una versión nueva publicada en este repo y ofrece descargarla. También se puede revisar a mano con el botón de la barra superior.

## Instalar en el celular

1. Desde el celular, abre **https://github.com/Isaito05/finza/raw/master/releases/finza.apk**. Ese link siempre apunta a la última versión.
2. Abre el APK descargado. La primera vez, Android pide permiso para *instalar apps desconocidas* desde el navegador.
3. Toca **Instalar**.

> Si ya tenías Finza instalada con `flutter run`, desinstálala antes. Esa versión
> está firmada con otra llave y Android no deja instalar encima. Al desinstalar se
> borran los datos guardados.

## Cómo funcionan las actualizaciones

No hay servidor: el repo hace de servidor.

- `releases/latest.json` (se crea con la primera publicación) dice cuál es la última versión publicada:
  ```json
  {
    "version": "1.1.0",
    "versionCode": 2,
    "apkUrl": "https://raw.githubusercontent.com/Isaito05/finza/master/releases/Finza-v1.1.0-2.apk",
    "changelog": "Qué cambió"
  }
  ```
- Al abrir la app, [`lib/services/actualizacion_service.dart`](lib/services/actualizacion_service.dart) descarga ese JSON y compara su `versionCode` con el build instalado (el `+N` de `version:` en `pubspec.yaml`). Si el publicado es mayor, muestra un diálogo con los cambios y un botón **Descargar** que abre el APK en el navegador.
- Si no hay internet o todavía no hay nada publicado, no muestra nada.
- GitHub cachea los archivos unos minutos, así que una versión recién publicada puede tardar un poco en aparecer.

La instalación sigue siendo manual: Android no deja que una app se actualice sola sin Play Store.

Archivos relevantes:
- [`lib/main.dart`](lib/main.dart): `_verificarActualizacion()` y `_mostrarDialogoActualizacion()` en `InicioScreen`.
- [`lib/services/actualizacion_service.dart`](lib/services/actualizacion_service.dart): consulta `latest.json` y abre la descarga.
- [`lib/models/actualizacion.dart`](lib/models/actualizacion.dart): modelo del JSON.
- [`lib/app_info.dart`](lib/app_info.dart): versión y build instalados.

## Correr en local

```powershell
flutter pub get
flutter run
```

Requiere Flutter con Dart `^3.13.4` (ver `pubspec.yaml`) y un Android conectado o un emulador.

## Publicar una versión nueva

Desde Windows, en la raíz del repo y en la rama `master` (la app lee `latest.json` de `master`).

### Una sola vez: llave de firma

Android solo instala una actualización encima si viene firmada con la **misma llave**.
Por eso los APK publicados se firman con un keystore propio, no con la llave de debug
(que es distinta en cada PC).

1. Sigue los pasos de [`android/key.properties.example`](android/key.properties.example): genera el `.jks` con `keytool` y crea `android/key.properties`.
2. Guarda el `.jks` y sus contraseñas con respaldo y **fuera del repo**. Si se pierden, la próxima versión no se podrá instalar encima de la anterior.

`key.properties`, `*.jks` y `*.keystore` están en `.gitignore`.

### Cada versión

```powershell
powershell -ExecutionPolicy Bypass -File .\release.ps1 -Cambios "Arregla el listado de facturas"
powershell -ExecutionPolicy Bypass -File .\release.ps1 -Version 1.1.0 -Cambios "Metas de ahorro"
```

- `-Cambios` (obligatorio): el texto que ve el usuario en el diálogo de actualización.
- `-Version X.Y.Z` (opcional): si se omite, se mantiene y solo sube el build (`+N`).
- `-SinPush`: compila y hace commit sin publicar.

Qué hace [`release.ps1`](release.ps1):
1. Verifica que estés en `master`, sin cambios pendientes y con `android/key.properties`.
2. Sube `version:` en `pubspec.yaml`: el `+N` siempre y el `X.Y.Z` solo si lo pasaste.
3. Corre `flutter pub get` y `flutter build apk --release` (solo ARM, que cubre prácticamente todos los celulares). Si falla, revierte el cambio de versión.
4. Deja el APK en `releases/` como `Finza-vX.Y.Z-N.apk` y `finza.apk` (el link fijo del README), y escribe `releases/latest.json`.
5. Hace commit `Release vX.Y.Z+N` y `git push origin master`. Desde ahí, las versiones viejas ven el aviso al abrirse.

> Cada APK pesa unos 15–20 MB y queda en el historial de git. Para un proyecto
> de este tamaño está bien. Si el repo crece demasiado, la alternativa es subir
> los APK a GitHub Releases en vez de al repo.

## Estructura

```
lib/
  main.dart                  app, pantallas (Inicio, Movimientos, Estadísticas, Facturas) y formularios
  app_info.dart              versión instalada (package_info_plus)
  models/                    Movimiento, Factura, Actualizacion
  database/                  DatabaseHelper (SQLite, versión 2: tablas movimientos y facturas)
  services/                  ActualizacionService
releases/                    APK publicado + latest.json (los genera release.ps1)
release.ps1                  script para compilar y publicar una versión
android/key.properties.example  cómo configurar la llave de firma
```
