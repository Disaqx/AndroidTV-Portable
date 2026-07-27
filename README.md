# Android TV portatil

**Un "televisor" Android a pantalla completa, hecho con el emulador de Android.**

Convierte cualquier PC con Windows en un Android TV: emulador a pantalla
completa sin bordes, puente para manejar el mando de gamepad, arranque
automatico de la app de TV y un acceso directo `Android TV` en el escritorio.

Pensado para desplegarse en varios equipos (PC de sobremesa y Lenovo Legion Go)
con el mismo paquete.

## Instalacion en un PC nuevo

1. Ve a **[Releases](../../releases/latest)** y descarga
   **`AndroidTV-Portable-cloudsdk.zip`** (8 MB).
2. Descomprimelo donde quieras.
3. Doble clic en **`INSTALAR.bat`**.

Y ya. No hace falta clonar el repositorio, ni Android Studio, ni Java.

### Las dos variantes

| Adjunto | Tamano | El SDK... | Internet al instalar |
|---|---:|---|---|
| **`AndroidTV-Portable-cloudsdk.zip`** | 8 MB | se baja de Google al instalar | si (~1,3 GB, una vez) |
| `AndroidTV-Portable.zip` | 1,05 GB | ya viene dentro | **no** |

**Si dudas, coge `cloudsdk`.** El resultado es identico. El grande solo tiene
sentido para instalar en un equipo **sin conexion**, llevandolo en un USB.

> **Pulsa `INSTALAR.bat`, no `INSTALL.ps1`.** Windows **ejecuta** los `.bat`,
> pero al hacer doble clic en un `.ps1` lo abre el editor en vez de correrlo.
> El `.bat` es justamente el que lanza el `.ps1` como toca.

Mejor aun: clic derecho en `INSTALAR.bat` → *Ejecutar como administrador*, y
asi ademas te activa el hipervisor de Windows sin que tengas que ir a buscarlo.

### Si prefieres clonar el repositorio

Funciona igual, solo que el `.zip` de la Release trae el SDK ya dentro y el
repositorio no (no cabe, ver mas abajo). Clonando, el instalador se baja el SDK
de Google la primera vez.

| | Repo clonado | ZIP de la Release |
|---|---|---|
| Descarga | ~15 MB | 1,05 GB |
| Necesita internet al instalar | si (~1,3 GB) | **no** |
| Clics | los mismos | los mismos |

### Las apps no vienen incluidas

No se distribuye ninguna `.apk`: no son nuestras. Descarga las que quieras y
**dejalas en la carpeta `apps\` antes de instalar** — el instalador instala
todos los `.apk` que encuentre ahi, sin tocar nada mas.

| App | Donde |
|---|---|
| **Downloader** (el del logo naranja) | https://www.aftvnews.com/downloader/ |
| Tu app de IPTV | de donde la tengas |

Si ya instalaste y quieres anadir una despues, dejala en `apps\` y ejecuta
`ACTUALIZAR.bat`.

## El SDK se instala solo

**No tienes que hacer nada.** Si el SDK no esta, `INSTALAR.bat` lo baja de los
repositorios publicos de Google y lo deja listo. No hace falta Android Studio,
ni Java, ni `sdkmanager`, ni ningun token.

El instalador resuelve el SDK en cascada, de mas rapido a mas lento:

| Situacion | Que hace | Cuanto tarda |
|---|---|---|
| El SDK ya esta instalado | Nada, lo omite | instantaneo |
| El paquete trae `sdk.7z` | Lo extrae. **Sin internet** | 1-2 min |
| No hay `sdk.7z` (repo clonado) | Lo baja de Google | 5-30 min segun conexion |

En el tercer caso baja ~1,3 GB repartidos asi:

| Componente | Tamano |
|---|---:|
| `platform-tools` | 8 MB |
| `emulator` | 399 MB |
| Imagen de sistema Android TV x86 (API 36) | 918 MB |

Cada descarga se **verifica por SHA1** contra el manifiesto de Google y se
cachea en `%TEMP%\AndroidTV-sdk-cache`, asi que si se corta a mitad no vuelve a
empezar de cero. Usa BITS (reanudable) y cae a descarga directa si no esta.

Solo se instalan versiones del **canal estable**. Google publica en el mismo
manifiesto builds de los canales beta, dev y canary con numero de revision mas
alto — coger "la mas nueva" a secas te instalaria una canary.

### Por que sdk.7z no esta en el repositorio

Pesa 996 MB y **GitHub rechaza cualquier fichero de mas de 100 MB**, asi que
esta excluido en `.gitignore`.

Va en la [Release](../../releases/latest), que publica dos ficheros:

| Adjunto | Que es | Cuando lo quieres |
|---|---|---|
| **`AndroidTV-Portable.zip`** | El paquete entero con el SDK dentro | **Casi siempre.** Descargar, descomprimir, instalar |
| `sdk.7z` | Solo el SDK suelto | Si ya tienes el repo clonado y quieres evitar la descarga |

Al ser un repositorio privado, bajar de la Release exige estar autenticado en
GitHub. Por eso el instalador **no** depende de ella: cuando no encuentra el
SDK tira de los repositorios de Google, que son publicos y no piden nada.

## Las apps

El instalador instala **todos los `.apk` que encuentre en `apps\`**, asi que
para anadir una basta con dejarla ahi.

Este repositorio incluye solo **`Downloader.apk`** (el del logo naranja, de
AFTVnews). La app de IPTV no se versiona: no es redistribuible.

## Los .bat del paquete

| Fichero | Para que |
|---|---|
| `INSTALAR.bat` | Instalacion completa, la primera vez |
| `ACTUALIZAR.bat` | Reaplica scripts y redetecta resolucion, sin tocar SDK ni apps |
| `DIAGNOSTICO.bat` | Resolucion detectada, config del AVD, estado del puente, y **en vivo** lo que reporta el mando al pulsar cada boton |
| `INFORME.bat` | Vuelca todo el estado a un `.txt` en el escritorio. Ejecutar **con el TV abierto** |
| `ARRANQUE-RAPIDO.bat` | Arranque con instantanea (~20 s) |
| `ARRANQUE-SEGURO.bat` | Arranque en frio (~30 s) |
| `TACTIL-SI.bat` / `TACTIL-NO.bat` | Activa/desactiva la pantalla tactil |
| `ESCALADOR-SI.bat` / `ESCALADOR-NO.bat` | Activa/desactiva el escalador |
| `PUENTE-MANUAL.bat` | Arranca el puente del mando a la vista, para ver errores |
| `MEDIR-CALIDAD.bat` | Resolucion y **bitrate real** del canal, y si ese bitrate da para esa resolucion |

## Por que la ventana nativa y no scrcpy

Se usa la ventana propia del emulador puesta a pantalla completa. Con scrcpy
las apps que marcan su pantalla como protegida (`FLAG_SECURE` — IPTV, VPN) se
ven **en negro**.

## Estructura

```
AndroidTV-Portable/
├── INSTALL.ps1          instalador de verdad (los .bat solo lo lanzan)
├── scripts/             los .ps1 que se copian a ~/.android
├── config/config.ini    plantilla del AVD
├── apps/                los .apk que se instalan
├── tools/               7-Zip portatil para extraer el SDK
└── sdk.7z               NO versionado (996 MB) - opcional, ver arriba
```

La instalacion resultante vive en `C:\Users\<tu-usuario>\.android\`.

## Documentacion completa

**[LEEME.txt](LEEME.txt)** — manual en espanol con el detalle de cada script.

## Licencias

El codigo de este proyecto —los `.ps1`, los `.bat`, el generador del icono y la
documentacion— esta bajo **[MIT](LICENSE)**.

El software de terceros va por su cuenta:

| Componente | Licencia |
|---|---|
| 7-Zip (`tools/`) | GNU LGPL — ver [`tools/LICENSE-7zip.txt`](tools/LICENSE-7zip.txt) |
| SDK de Android | [Android SDK License Agreement](https://developer.android.com/studio/terms). **No se redistribuye**: el instalador lo baja de Google, donde cada usuario acepta sus terminos |
| `apps/*.apk` | Cada una con la licencia de su autor |

### Que NO hay aqui, y por que

Este repositorio contiene **solo codigo propio**. Deliberadamente no incluye:

- **El SDK de Android.** Su licencia
  [prohibe la redistribucion de forma explicita](https://developer.android.com/studio/terms):
  *"you may not copy (except for backup purposes), modify, adapt, redistribute
  [...] the SDK or any part of the SDK"*. El instalador lo baja de los
  servidores de Google, donde cada usuario acepta sus terminos directamente.
- **Ninguna `.apk`.** No son nuestras para redistribuirlas. Descargalas de su
  fuente oficial y dejalas en `apps\`.

Lo unico de terceros que si se redistribuye es 7-Zip, porque su licencia LGPL
lo permite expresamente, y va acompanado de
[su texto de licencia](tools/LICENSE-7zip.txt).
