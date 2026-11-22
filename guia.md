# Guia de continuacion - Xuper Pad (iPad mini 1, iOS 9.3.6)

Documento de traspaso para seguir el trabajo en otro agente como si fuera
la misma sesion. Ultima actualizacion: 2026-11-22.

Repo: `C:\Users\Usuario\Documents\Ixuperipa\XuperPad`
Bundle: `com.xuper.pad`
Dispositivo de pruebas: iPad mini "Wil", UDID
`a53356f6b0e7d371a576e56e8101598cd30ca3de`, iOS 9.3.6 (armv7).

## 1. Objetivo

Aplicacion nativa para iPad mini 1 con iOS 9.3.6 que reproduce el catalogo
del portal Xuper. Todo lo visible se dibuja a mano con UIKit/Core Graphics;
del port WebOS solo se toma el protocolo y las URLs, nunca su interfaz.
La decodificacion usa libavcodec/libavformat/libswscale/libswresample de
FFmpeg (no se embebe VLC; se reimplementa el pipeline al estilo VLC).

El reproductor usa `view.bounds` de 768x432 en horizontal.

## 2. Estado del repositorio

- Rama `main`, sincronizada con `origin/main`.
- Ultimo commit publicado: `cb49435` "Evita los saltos del video y las
  pausas del audio".
- Commits previos relevantes: `5206605` (scroll del panel de opciones),
  `611ad6b` (compilacion con FFmpeg 4.4.4), `d8b94a9` (idioma, subtitulos y
  velocidad), `1032d25` (AudioQueueStart en iOS 9).
- Ultimo build publicado: `build-20261122-122111`, instalado y verificado.
- Esta ronda deja cambios SIN commitear (ver apartado 3). Tras revisarlos
  hay que publicarlos segun el apartado 6.

## 3. Cambios implementados en esta ronda (sin commitear)

`git status --short` debe mostrar exactamente estos siete archivos:

```
 M app/Classes/XPConstants.h
 M app/Classes/XPConstants.m
 M app/Classes/XPDecoder.m
 M app/Classes/XPPlayerViewController.m
 M app/Classes/XPSession.h
 M app/Classes/XPSession.m
 M app/Classes/XPStatusView.m
```

### 3.1 XPConstants.h / XPConstants.m - errores precisos

- Nuevas constantes: `XPVersionRejectedErrorCode` (`portal200001`),
  `XPCredentialBusyErrorCode` (`aaa100083`),
  `XPSessionNotLoggedInErrorCode` (`aaa100028`).
- `XPPortalErrorMessage` distingue version retirada, credencial ocupada en
  otro dispositivo, sesion no iniciada, sesion caducada, bloqueo regional y
  mensaje crudo del portal.
- `XPSessionDeadErrorCodes` ya NO incluye `portal200001`: reintentar no
  arregla una version retirada. Si incluye `aaa100083`, para poder invalidar
  la credencial compartida y renovar.

### 3.2 XPSession.h / XPSession.m - sesion persistente con latido

- `XPSessionState` gana `snToken` y `heartbeatInterval`.
- Persistencia en `NSUserDefaults` bajo `XuperPad.activeSession` (semilla,
  userId, userToken, snToken, expiracion, intervalo de latido y origen).
- `restoreStoredSession` en `init`; `persistCurrentState`,
  `clearStoredSession` y `discardCurrentState`.
- Latido: `startHeartbeat`/`stopHeartbeat` con `NSTimer` en el run loop
  principal. El intervalo es `heartBeatTime/2` limitado a 30-120 s (60 s por
  defecto). `heartbeatFired:` llama a `v8/active` en cola de fondo; si el
  portal devuelve un codigo de sesion muerta se descarta el estado y se
  re-Activa; si es un fallo de red se reintenta en el siguiente tick.
- La expiracion se toma del servidor: `availableTime` (28800 s = 8 h) y
  `heartBeatTime` (120 s), con tope de seguridad de 24 h y respaldo de 6 h.
- `resumeStoredSessionWithCompletion` revalida la sesion guardada al arrancar
  con `v8/active`; si el portal la rechaza se crea sesion fresca, si falla la
  red se usa la guardada.
- La activacion real es el camino principal; las semillas publicadas quedan
  como ultimo recurso.
- `activationParametersWithSeed:snToken:` factoriza los parametros de
  `v8/active` (activacion fresca, semillas y latido).
- `invalidate`/`invalidateSharedSeed` limpian estado, timer y persistencia.

Observacion: el portal espera un latido cada 120 s y el port WebOS no lo
enviaba; la app tampoco. Esa era la causa de que la sesion caducara. Repetir
`v8/active` con el mismo `snToken` es seguro y devuelve el mismo `userId`.

### 3.3 XPDecoder.m - gris/pixeleado y sincronia

Diagnostico previo (log del iPad, 300 s): 536+ errores
`ffmpeg: Could not find ref with POC N`, unos 23 paquetes de video por
segundo pero solo 7 fotogramas por segundo, cola de video que nunca llegaba
a 64 (sin descartes por desbordamiento) y audio perfecto. La causa era
comparar el PTS del video con el reloj maestro del audio (lineas de tiempo
distintas): se hacia flush y salto a clave a mitad de GOP, se perdian
referencias y se descartaban fotogramas.

Cambios:

- Eliminados `videoNeedsFlush` y `takeKeyframePacket` (y la constante
  `XPVideoLateSeconds`). Ya no se salta a clave por "paquete tardio".
- `videoDecodeLoop` reescrito: si hace falta una clave se espera hasta 8 s
  (`XPVideoKeyframeWaitLimit`) y al llegar se hace `avcodec_flush_buffers`;
  el flag de espera ya no se consume antes de tiempo. Se detectan saltos de
  tiempo con DTS monotono (`packetDecodeTime:`) y se reinicia el GOP.
- Si el log de FFmpeg reporta "Could not find ref" (callback
  `XPFFmpegLogCallback`), se cuenta, se hace flush y se espera la siguiente
  clave.
- `decodeVideoPacket` maneja `AVERROR(EAGAIN)` drenando fotogramas y
  reintentando el envio; ante error real ya no descarta en silencio: cuenta,
  hace flush y marca `videoNeedsKeyframe`. El bucle de recepcion vive en
  `drainVideoFrames:`.
- Al desbordar la cola de video se marca `videoNeedsKeyframe` (descarte
  alineado a GOP).
- Relojes: nuevo `videoClock` propio y `videoMasterOffset` para alinear la
  linea de tiempo del video con el reloj maestro. `masterClock` aplica la
  velocidad a la rama de video, `waitForVideoPace` usa `videoClock`,
  `nextFrameToShow` compara `pts + videoMasterOffset`, `currentTime` usa
  `videoStartPTS + videoMasterOffset`, `realignAudioClock` compara
  `videoClock + videoMasterOffset` y el arranque del audio ancla
  `audioOffset` al reloj de video para que el reloj maestro no salte.
- Codec: sin `AV_CODEC_FLAG2_FAST`; `FF_THREAD_FRAME` solo para HEVC,
  `FRAME|SLICE` para el resto; `thread_count = 2`.
- El log de progreso agrega `refs`, `envios` y `esperas` para validar en
  dispositivo.

### 3.4 XPStatusView.m - el overlay ya no bloquea

Nuevo `hitTest:withEvent:` que devuelve `nil` cuando el toque cae en el
propio statusView. El boton "Reintentar" sigue siendo interactivo porque el
hit devuelve el boton. Antes, al terminar el contenido el statusView a
pantalla completa se comia los toques y no se podian ni mostrar los
controles: por eso habia que cerrar la app.

### 3.5 XPPlayerViewController.m - fin de contenido

- Constante `XPPlayerNextChapterDelay = 4.0`; propiedades `endTimer` y
  `playbackFinished`.
- `decoder:didFinishWithMessage:` para, muestra el mensaje no bloqueante y
  llama a `handlePlaybackFinished:`.
- `handlePlaybackFinished:` marca fin, pausa, muestra controles y, si hay
  capitulo siguiente, avisa "Siguiente capitulo en 4 s: <titulo>" y programa
  `advanceToNextChapter` (que llama a `openChapterAtIndex:`). Si no hay
  siguiente, avisa con toast y deja los controles.
- `cancelAutomaticChapter` invalida el timer y se llama en
  `previousChapterTapped`, `nextChapterTapped`, `chapterSelectedAtIndex:` y
  `openChapterAtIndex:`.
- `togglePlayPause`: si la reproduccion termino (sin decoder ni player y
  `playbackFinished`) reinicia el capitulo actual (`currentIndex = 0` +
  `startPlayback`, que reconstruye la cola de direcciones del capitulo).
- `startPlayback` resetea `playbackFinished`; `stopPlayback` y `dealloc`
  invalidan `endTimer`.

## 4. Protocolo del portal (resumen operativo)

Cadena que funciona (returnCode 0):

```
v3/snToken -> v8/active -> getNextColumns -> v4/getItemData
-> v10/startPlayVOD -> v14/getSlbInfo
```

- Cabecera `apkVer: 43404` funciona. `49902`/`99999` devuelven
  `portal200001` ("version descontinuada").
- `v8/active` devuelve `activeTime`, `nowTime`, `availableTime` (28800),
  `heartBeatTime` (120), `renewFlag` (2), `jwtToken`, `userId` y `userToken`.
- `v8/active` repetido con el mismo `snToken` es latido y renovacion.
- `heartbeat`/`v4/heartbeat` existe pero siempre responde `aaa100028`; no
  usarlo.
- Codigos: `aaa100028` sesion no iniciada, `aaa100083` cuenta abierta en otro
  dispositivo, `portal200001` version retirada, `portal100024` bloqueo
  regional.
- Las semillas publicadas (repo cristianco7/XUPER-HYDRA-PORT-WEBOS) estaban
  caducadas (0/70 vigentes); no sirven como respaldo real hoy.

Fuente de verdad del protocolo:
`...\webos\services\com.webosflux.xuptertv.fidelity.service\magis.js`
(lineas 23-25 `APK_VERSION`/`APK_VER_HEADER`, 272, 336, 620-730 semillas,
944-987 `v3/snToken` + `v8/active`, 1723 `v10/startPlayVOD`,
2179-2185 `v4/startPlayLive`, 2256 `App-Version: 49902`).

## 5. Entorno y trampas conocidas

- Bash del harness es PowerShell 5.1: no admite `&&`/`||` ni escapes `u{}`;
  `$host` es constante. Usar `;` y `if ($?)`.
- Git Bash explicito:
  `& "C:\Program Files\Git\bin\bash.exe" -lc "..."`.
- Git: la identidad NO esta en la config. Pasar siempre
  `-c user.name=lofturb -c user.email=217372106+lofturb@users.noreply.github.com`
  antes del subcomando. No modificar `git config`.
- `gh`:
  `"C:\Program Files\GitHub CLI\gh.exe"`.
- Redirecciones de `gh api` desde PowerShell escriben UTF-16 y rompen
  base64: usar `cmd /c` o `--json`. Para logs de CI usar
  `--log | Out-File -Encoding utf8`.
- El harness aborta comandos con procesos desacoplados: capturar syslog con
  `Start-Process ... -RedirectStandardOutput` + `Start-Sleep` +
  `Stop-Process`.
- `idevicedebug run` no funciona en iOS 9.3 (sin DeveloperDiskImage). Hay
  que abrir la app a mano en el iPad y capturar con `idevicesyslog`.
- Linter: `python tools/lint.py` busca identificadores prohibidos en `.m` y
  `.h`. No introducir palabras como `pattern`, `place`, `junk`, `fini`,
  `plat`, `bucket`. Debe terminar en `LINT OK`.
- No anadir comentarios nuevos al codigo ni documentacion .md salvo que el
  usuario lo pida (este `guia.md` fue pedido).
- No tocar `C:\Users\Usuario\Documents\Ixuperipa\Guia-Compilar-Instalar-IPAs-iOS9.md`.
- El LSP local no tiene SDK de iOS: los errores `Foundation/UIKit.h file not
  found` son de entorno, no del codigo. La compilacion real ocurre en CI.

## 6. Publicar y validar (pasos exactos)

### 6.1 Linter y revision

```
cd C:\Users\Usuario\Documents\Ixuperipa\XuperPad
python tools/lint.py
git status --short
git diff --stat
```

Debe dar `LINT OK` y los siete archivos modificados.

### 6.2 Commit y push

Ejecutar `git add`, `git commit` y `git push` en comandos separados:

```
git add app/Classes/XPConstants.h app/Classes/XPConstants.m app/Classes/XPDecoder.m app/Classes/XPPlayerViewController.m app/Classes/XPSession.h app/Classes/XPSession.m app/Classes/XPStatusView.m guia.md
git -c user.name=lofturb -c user.email=217372106+lofturb@users.noreply.github.com commit -m "Renueva la sesion del portal y reanuda el video sin perder referencias"
git push origin main
```

### 6.3 CI y release

```
"C:\Program Files\GitHub CLI\gh.exe" run list --limit 3
"C:\Program Files\GitHub CLI\gh.exe" run watch <id> --exit-status
"C:\Program Files\GitHub CLI\gh.exe" release list --limit 5
```

El workflow `.github/workflows/build-ipa.yml` compila FFmpeg con cache
`...-v7` (incluye `--enable-parser=hevc,aac` y
`--enable-demuxer=mpegts`) y publica una release `build-<fecha>` con
`com.xuper.pad_1.0.0.ipa`.

### 6.4 Descargar e instalar

```
"C:\Program Files\GitHub CLI\gh.exe" release download build-<nuevo> --dir "$env:TEMP\xuper_release" --clobber
Get-FileHash "$env:TEMP\xuper_release\com.xuper.pad_1.0.0.ipa" -Algorithm SHA256
$tools = "C:\Users\Usuario\Downloads\Compressed\XUPER-HYDRA-PORT-WEBOS-3.1.13\XUPER-HYDRA-PORT-WEBOS-3.1.13\tools\libimobiledevice"
& "$tools\ideviceinstaller.exe" -u a53356f6b0e7d371a576e56e8101598cd30ca3de -U com.xuper.pad
& "$tools\ideviceinstaller.exe" -u a53356f6b0e7d371a576e56e8101598cd30ca3de -i "$env:TEMP\xuper_release\com.xuper.pad_1.0.0.ipa"
```

`gh release download` debe ejecutarse dentro del repo o con `--dir`.

### 6.5 Captura de syslog acotada

Pedir al usuario que abra la app a mano y ejecutar:

```
$tools = "C:\Users\Usuario\Downloads\Compressed\XUPER-HYDRA-PORT-WEBOS-3.1.13\XUPER-HYDRA-PORT-WEBOS-3.1.13\tools\libimobiledevice"
$log = "$env:TEMP\xuper_validacion.log"
$p = Start-Process -FilePath "$tools\idevicesyslog.exe" -ArgumentList "-u","a53356f6b0e7d371a576e56e8101598cd30ca3de" -RedirectStandardOutput $log -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 120
Stop-Process -Id $p.Id -Force
Select-String -Path $log -Pattern "decodificador:|sesion:|ffmpeg:" | Select-Object -Last 120
```

## 7. Que debe validar el usuario en el iPad

1. Serie en HEVC: sin areas grises ni pixeleado, `imagenes` cerca de 25/s,
   pocos o cero errores `Could not find ref` y `refs 0`.
2. Directo: audio sin cortes, `en cola` alrededor de 0.7 s, sin pausas.
3. Fin de contenido: aparece el mensaje, se ven los controles, avanza solo
   al capitulo siguiente a los 4 s; los botones de capitulo anterior y
   siguiente responden sin cerrar la app.
4. Sesion: el log muestra `sesion: latido correcto, vigente N min` cada
   ~60 s y no aparece `la sesion del portal caduco`.
5. Panel de opciones: idioma de audio, subtitulos y velocidad funcionan sin
   cortar la reproduccion y el panel se puede desplazar.

## 8. Pendientes conocidos

- Validar en dispositivo los cambios de esta ronda (apartado 7).
- Parser de pista del portal: `alto`, `bitrate` y `fps` llegan a 0; habria
  que leer la pista real del manifiesto/segmento.
- `XPTransport` todavia no usa el DoH que emplea `magis.js`.
- `signO3` solo deberia enviarse en LIVE, no en VOD.
- `README.md` solo si el usuario lo pide expresamente.
- Si el usuario quiere, unificar el mensaje de fin de contenido con el
  titulo del siguiente capitulo en el propio statusView.

## 9. Resumen en una frase

La app ya evita los saltos de video y las pausas de audio; esta ronda
anade sesion persistente con latido, reanudacion del video sin perder
referencias y fin de contenido con avance o retroceso de capitulo sin
cerrar la app. Falta publicarlo y validarlo en el iPad.