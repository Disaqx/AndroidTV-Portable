# Software de terceros

La [licencia MIT](LICENSE) de este proyecto cubre **unicamente el codigo
propio**: los `.ps1`, los `.bat`, el generador del icono y la documentacion.

## Lo que se redistribuye

| Componente | Licencia |
|---|---|
| 7-Zip (`tools/7z.exe`, `tools/7z.dll`) | GNU LGPL, con componentes BSD y la restriccion de unRAR — ver [`tools/LICENSE-7zip.txt`](tools/LICENSE-7zip.txt) |

Es lo unico. Su licencia permite la redistribucion expresamente, y va
acompanado de su texto de licencia como esta exige.

## Lo que NO se redistribuye, y por que

**El SDK de Android.** Su licencia lo prohibe de forma explicita:

> *"you may not copy (except for backup purposes), modify, adapt, redistribute,
> decompile, reverse engineer, disassemble, or create derivative works of the
> SDK or any part of the SDK"*
>
> — [Android Software Development Kit License Agreement](https://developer.android.com/studio/terms)

El instalador lo descarga de los repositorios publicos de Google, de modo que
cada usuario acepta los terminos de Google directamente. Se bajan
`platform-tools`, `emulator` y la imagen de sistema `android-tv;x86` de la API
36, filtrando por canal estable y verificando cada componente por SHA1.

**Las aplicaciones Android (`.apk`).** No son nuestras para redistribuirlas.
Descargalas de su fuente oficial y dejalas en `apps\`; el instalador instala
todas las que encuentre ahi.

- Downloader (el del logo naranja): https://www.aftvnews.com/downloader/
