# UltraNotch

*A macOS app that turns your MacBook's notch into a dynamic island: music with live lyrics, calendar, file shelf, clipboard slots, Claude Code sessions and approvals, voice commands and a little mascot named Dottie. (Docs in Spanish.)*

**UltraNotch convierte el notch de tu Mac en una isla dinámica:** pasa el mouse por el notch y se abre un panel con tu música y su letra, tu agenda, un estante de archivos, un portapapeles con ranuras, tus sesiones de Claude Code en vivo y a Dottie, un personajito que vive junto al notch.

![UltraNotch: música con letra en vivo y la próxima junta](docs/capturas/hoy-musica-letra.png)

- Ligera y nativa (SwiftUI + AppKit), sin cuentas ni suscripciones.
- Casi todo pasa en tu Mac; lo poco que sale a internet está en [Privacidad](#privacidad).
- Código, comentarios e interfaz en español.

---

## Qué hace

### Hoy: música, letra y agenda

- Lo que suena en **Spotify** o **Música**, con carátula, avance y controles. Cuando cambia la canción sale un aviso cortito junto al notch.
- **Letra en vivo**: la línea que se canta en grande, con la anterior y la siguiente. En *Letra completa* toca una línea para brincar a esa parte. La letra viene de [LRCLIB](https://lrclib.net) (gratis y abierto; no todas las canciones la tienen).
- **Agenda** de hoy y mañana con botón **Unirme** para Teams, Google Meet, Zoom y Webex. Sale del **Calendario de la Mac** (incluye cuentas de Google o Microsoft que agregues en *Cuentas de internet*) o de un **link .ics**. Te avisa unos minutos antes de cada junta.

![Pestaña Hoy con la agenda](docs/capturas/hoy-agenda.png)

![Notch cerrado con un aviso de junta](docs/capturas/notch-cerrado-aviso-junta.png)

### Estante

- Tus **capturas de pantalla** y **descargas nuevas** llegan solas (con un aviso a los lados del notch).
- **Arrastra cualquier archivo al notch** para guardarlo, y arrástralo después a donde quieras (correo, Slack, Finder…).
- **AirDrop**: suelta un archivo en el lado derecho del panel o usa el botón azul de cada archivo.
- Los archivos no se mueven ni se copian: el estante solo los enlaza.

![Estante](docs/capturas/estante.png)

### Portapapeles

- **⌘C + número (1–9)** guarda lo copiado en esa ranura; **⌘V + número** la pega sin perder lo que tenías copiado.
- Las 9 ranuras se guardan en disco; el historial (30 elementos) vive solo en memoria y omite lo que los gestores de contraseñas marcan como privado.

![Portapapeles](docs/capturas/portapapeles.png)

### Claude Code: en vivo, permisos, preguntas y límites

Conecta UltraNotch con [Claude Code](https://claude.com/claude-code) y ves tus sesiones desde el notch, sin API ni costo extra.

- **Actividad en vivo**: con el panel cerrado, un personajito por sesión se asoma junto al notch (trabaja, piensa, te espera o festeja) y a un lado ves qué hace (*Edita · invoice.ts*).
- **Permisos desde el notch**: cuando Claude Code pide permiso baja una tarjeta con **Permitir / Siempre / Negar / Terminal**. Si no eliges a tiempo, Claude Code pregunta en la terminal como siempre.
- **Preguntas con opciones**: eliges en la tarjeta, marcas varias o escribes tu respuesta.
- **Vista previa del cambio** (opcional): renglones que se quitan y se agregan antes de aprobar una edición.
- **Límites de uso**: dos anillos con tu sesión de 5 h y tu semana, con avisos al acercarte al límite.
- **Pestaña Claude** con cada sesión, sus pasos recientes y el resumen al terminar; sonidos distintos por evento; las sesiones automáticas (Agent SDK, plugins) no hacen ruido.
- **Respóndele por voz** cuando una sesión termina: di "responde…" y tu mensaje le llega a esa misma sesión.

| En vivo | Permiso |
|---|---|
| ![Actividad en vivo](docs/capturas/claude-en-vivo.png) | ![Permiso](docs/capturas/claude-permiso.png) |
| **Pregunta con opciones** | **Vista previa del cambio** |
| ![Pregunta](docs/capturas/claude-pregunta.png) | ![Vista previa](docs/capturas/claude-vista-previa-cambios.png) |

![Pestaña Claude con sesiones y límites de uso](docs/capturas/claude-sesiones.png)

> [!IMPORTANT]
> **Para esto UltraNotch modifica `~/.claude/settings.json`.** Al tocar *Conectar con Claude Code* agrega unos *hooks* (SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, Notification, Stop, SessionEnd) que ejecutan `UltraNotch.app/Contents/MacOS/UltraNotch --claude-hook`, y, si tienes activados los límites de uso, se pone como `statusLine` (sigue mostrando la línea de estado que ya tenías y te la regresa al quitarlo).
>
> - Antes de escribir guarda un respaldo junto al archivo: `settings.json.ultranotch-respaldo-<fecha>`. No toca tus otros ajustes ni tus hooks.
> - Los hooks hablan con la app por un socket local (`~/Library/Application Support/UltraNotch/claude.sock`). Si UltraNotch está cerrado, terminan al instante y Claude Code sigue normal.
> - Aplica a **sesiones nuevas** de Claude Code.
> - **Para quitarlos:** Configuración › Claude › **Desconectar**, el menú de la barra › **Desconectar Claude Code**, o `./desinstalar.sh` (también los quita).

### Mac

CPU, memoria, disco, temperatura y batería en vivo; las apps que más RAM usan (con botón para cerrarlas); **Liberar RAM** (`purge`) y **Liberar espacio** (Papelera, cachés, descargas y capturas viejas, cachés de desarrollo), siempre con confirmación. Avisa si el disco se llena, la RAM se agota o la Mac se calienta. Cerrado, casi no consume.

![Pestaña Mac](docs/capturas/mac.png)

### Dottie

Dottie vive junto al notch todo el tiempo y tiene más de 30 animaciones: camina, se cuelga de un hilo, anda en patineta, despega en cohete, viaja en ovni, pasa en avioneta con letrero y recibe a su amigo (el cuadradito con antena). Te sigue con la mirada, saca su caja de herramientas cuando Claude trabaja, festeja cuando termina, se duerme si no usas la Mac, suda si la Mac va a tope y se pone audífonos cuando suena tu música. De vez en cuando sale de paseo, aterriza arriba del Dock y regresa en globo. Te avisa cosas en globitos. Su color y su comportamiento se ajustan en Configuración › Dottie.

![Dottie y sus poses](docs/capturas/dottie-poses.png)

| Notch cerrado | Aviso de captura |
|---|---|
| ![Notch cerrado](docs/capturas/notch-cerrado.png) | ![Aviso de captura](docs/capturas/aviso-captura.png) |

### Modo programación

Botón ☕ del panel (o "Oye Claudio, modo programación"): la Mac no se duerme, no apaga la pantalla ni se bloquea mientras está activo. Si cierras la tapa, sí se duerme (salvo con corriente y monitor externo).

### Voz: "Oye Claudio"

Reconocimiento de voz **en tu Mac** (el audio no sale de tu computadora). La frase se cambia en Configuración › Voz. Después de la frase puedes decir:

| Orden | Qué hace |
|---|---|
| **nuevo chat** + mensaje | Chat nuevo en Claude (app de Mac o navegador) con tu plan |
| **a *proyecto*** + mensaje | Lo manda a uno de tus proyectos de Claude |
| **cowork** / **Claude Code** + mensaje | Tarea nueva de Cowork o sesión de Claude Code en Claude para Mac |
| **ChatGPT** + mensaje | Chat nuevo en ChatGPT (app o chatgpt.com) |
| **responde** + mensaje | Contesta a la sesión de Claude Code que acaba de terminar |
| **permitir** / **siempre** / **negar** | Responde el permiso pendiente |
| **terminal** + mensaje | Trae la terminal, escribe lo dictado y le da Enter |
| **estante**, **portapapeles**, **Mac**, **agenda** | Abre esa pestaña |
| **pausa**, **siguiente canción**, **canción anterior** | Controla la música |

- **Tecla para hablar:** mantén **⌥ derecha**, habla sin "Oye Claudio" y suelta. Si apagas *Escuchar siempre*, el micrófono solo se enciende con esa tecla.
- **Tu diccionario:** palabras que debe conocer y correcciones ("cloud code → Claude Code").
- **Limpieza del dictado:** quita muletillas y pone puntuación; con **Apple Intelligence** (macOS 26) queda mejor, también en tu Mac.

---

## Requisitos

- **macOS 13 Ventura o superior.** Se ve mejor en una Mac **con notch**; sin notch (o en un monitor externo) aparece una "isla" virtual arriba al centro.
- **Command Line Tools de Apple** (gratis) para compilar: `xcode-select --install`.
- Algunas funciones piden algo más nuevo:
  - **Liquid Glass** (estilo *Cristal líquido*) y **limpieza del dictado con Apple Intelligence**: macOS 26 Tahoe con Apple Intelligence activada. Antes se usa el vidrio esmerilado del sistema y la limpieza normal.
  - **"Oye Claudio"** necesita reconocimiento de voz en el dispositivo para tu idioma (Ajustes › Teclado › Dictado).
  - **Letra en vivo y controles:** Spotify o Música de Apple.
  - **Claude Code** instalado (para la pestaña Claude) y un plan Pro o Max para ver los límites de uso. Las órdenes de chat/Cowork usan la app **Claude para Mac** (o el navegador).

## Instalación

```bash
git clone https://github.com/terder95/UltraNotch.git
cd UltraNotch
./instalar.sh
```

El script compila, arma `UltraNotch.app`, la firma (con tu certificado de desarrollador si tienes uno, si no con firma local), la copia a **Aplicaciones** y la abre. Para actualizar, `git pull` y vuelve a correr `./instalar.sh`.

¿Prefieres un instalador? `./crear-dmg.sh` crea `UltraNotch-<versión>.dmg`. Al compartirlo, como no está notarizado, la otra Mac pedirá *Ajustes › Privacidad y seguridad › Abrir de todos modos*.

> Con firma local, macOS olvida algunos permisos en cada reinstalación (Accesibilidad, micrófono, calendario). El instalador los reinicia para que los vuelva a pedir limpio.

> **¿Venías de "Isla"?** UltraNotch es el nuevo nombre. `instalar.sh` quita `Isla.app` y cierra su proceso; la primera vez que abre, UltraNotch copia tus ajustes y datos, y reemplaza los hooks viejos de Claude Code por los nuevos sin duplicarlos.

## Permisos que pide

| Permiso | Para qué |
|---|---|
| **Accesibilidad** | Atajos ⌘C / ⌘V + número, tecla para hablar y escribir en la terminal |
| **Micrófono** y **Reconocimiento de voz** | "Oye Claudio" y el dictado (procesado en tu Mac) |
| **Calendarios** | Tus juntas en la pestaña Hoy |
| **Escritorio**, **Descargas** (y Documentos) | Detectar capturas y descargas nuevas |
| **Automatización** (Terminal, iTerm2, Spotify, Música, Finder) | Ir a la pestaña de Claude Code, controlar la música, vaciar la Papelera; solo cuando tú lo pides |
| Contraseña de administrador | Solo al usar *Liberar RAM* (`purge`) |

## Privacidad

**Se queda en tu Mac:** tu voz y el dictado, tu agenda del Calendario, el portapapeles, el estante, los datos de tus sesiones de Claude Code y los registros. Los datos de la app viven en `~/Library/Application Support/UltraNotch/` y los ajustes en el dominio `io.github.terder95.ultranotch`.

**Sale a internet** (solo esto, sin cuentas ni rastreo):

| Servicio | Qué se manda | Cuándo |
|---|---|---|
| [LRCLIB](https://lrclib.net) | Título, artista, álbum y duración de la canción | Al buscar la letra |
| Spotify oEmbed / búsqueda de iTunes (Apple) | El enlace de la canción o título y artista | Al buscar la carátula si la app de música no la da |
| El link **.ics** que tú pongas | Una descarga del calendario | Solo si agregas un link |

Las órdenes de voz a Claude o ChatGPT abren esas apps (o su web) con tu mensaje; ahí aplican sus propias políticas. UltraNotch no usa ninguna API de pago.

## Desinstalar

```bash
./desinstalar.sh
```

Quita los hooks y la línea de estado de Claude Code (con respaldo de `settings.json`), la app, sus datos, sus ajustes y sus permisos. También limpia lo que haya quedado de la versión anterior (Isla).

## Regenerar las capturas

Las imágenes de este README se dibujan con la propia app y datos de ejemplo (no toca tus ajustes ni tus datos):

```bash
swift build -c release
.build/release/UltraNotch --capturas docs/capturas
```

## Estructura del proyecto

```
UltraNotch/
├── Package.swift             Swift Package (se compila con `swift build`)
├── instalar.sh               Compila e instala en Aplicaciones
├── desinstalar.sh            Quita app, datos, permisos y hooks
├── crear-dmg.sh              Crea UltraNotch-<versión>.dmg
├── scripts/compilar.sh       Parte compartida: compila, arma UltraNotch.app y la firma
├── Resources/                Info.plist (nombre, permisos) e ícono
├── docs/capturas/            Imágenes del README (generadas con --capturas)
├── Sources/UltraNotchObjC/   Ayudante en Objective-C que atrapa NSException
└── Sources/UltraNotch/
    ├── UltraNotchApp.swift     Punto de entrada y modos sin interfaz (--claude-hook, --capturas…)
    ├── AppDelegate.swift       Arranque, menú de la barra
    ├── Migracion.swift         Copia ajustes y datos de la versión anterior (Isla)
    ├── Notch*.swift            Ventana sobre el notch, abrir/cerrar, avisos
    ├── IslandView.swift        El panel y sus pestañas
    ├── TodayView, NowPlaying, Lyrics, CalendarStore   Música, letra y agenda
    ├── Shelf*, FolderWatcher, AirDrop                 Estante
    ├── Clipboard*, KeyInterceptor                     Portapapeles y atajos
    ├── Claude*.swift           Hooks, sesiones, permisos, preguntas, límites, chats
    ├── Companion*, BuddyFigure, StageExtras           Dottie
    ├── VoiceWake, HoldToTalk, PersonalDictionary      Voz y dictado
    ├── System*, MacView, KeepAwake                    Pestaña Mac y modo programación
    ├── Capturas.swift          Modo capturas (imágenes del README)
    └── SettingsView.swift      Configuración
```

## Licencia

[MIT](LICENSE) © 2026 Abraham Trujillo
