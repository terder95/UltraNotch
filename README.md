# Isla — tu notch convertido en isla dinámica

App ligera para macOS que vive en el notch de tu Mac. Pasa el mouse por el notch (arriba, al centro) y se abre una isla de cristal con cinco pestañas:

**Hoy** (tu música y tu agenda)
- **Música:** lo que suena en **Spotify** o **Música** (Apple Music) con su **carátula**, la barra de avance y botones de anterior, pausa y siguiente. Cuando cambia la canción, sale un aviso cortito junto al notch (se apaga en Configuración › Hoy). No gasta batería: Isla solo escucha el aviso que esas apps mandan al cambiar de canción.
- **Letra en vivo:** mientras suena algo, la pestaña Hoy enseña la **línea que se está cantando** en grande, con la anterior y la siguiente más tenues. Con **Letra completa** ves toda la letra avanzando sola; **toca una línea** para brincar a esa parte de la canción. La letra viene de **LRCLIB** (gratis, sin cuenta); no todas las canciones la tienen. Con **Agenda** regresas a tus juntas; abajo de la letra siempre ves tu próxima junta con su botón **Unirme**.
- **Con la isla cerrada:** cuando suena música, el compañero **se pone audífonos** y mueve la cabeza, y del otro lado del notch salen unas **barritas del color de la carátula**. Si tienes al compañero apagado, se ven la carátula chiquita y las barritas.
- **Agenda:** tus juntas de hoy y mañana, con la que va **ahora** marcada y un botón **Unirme** cuando traen link de **Teams, Google Meet, Zoom o Webex** (Teams se abre en su app si la tienes).
- **De dónde sale tu agenda:** del **Calendario de la Mac**, que puede traer tu cuenta de **Google (Gmail)** y de **Microsoft (Outlook / Teams)** si las agregas en Ajustes del Sistema › Cuentas de internet; o de un **link de calendario (.ics)**: el "link secreto" de Google Calendar o el de "Publicar calendario" de Outlook. Todo se lee en tu Mac.
- **Te avisa antes de cada junta** (5 min por defecto): el compañero te dice cuál es, con botón **Unirme**.

**Estante**
- Tus **capturas de pantalla** aparecen solas en la isla, con un aviso a los lados del notch (como la Dynamic Island).
- Tus **descargas nuevas** también llegan solas (ignora las que van a medias: `.crdownload`, `.download`, `.part`…).
- **Arrastra cualquier archivo hacia el notch**: la isla se abre y lo guarda en el estante.
- **Arrastra desde la isla** a la pestaña, correo o carpeta que quieras (Gmail, WhatsApp Web, Finder, Slack…).
- Doble clic abre el archivo. Con clic derecho puedes mostrarlo en Finder, copiarlo o quitarlo.
- **AirDrop:** pasa el mouse por un archivo y toca el botón azul (o clic derecho › Mandar por AirDrop) para mandarlo a tu iPhone, iPad u otra Mac. Con clic derecho también puedes mandar todos los de la vista.
- **Arrastra al lado derecho de la isla** y suéltalo en **AirDrop**: se manda sin guardarlo en el estante. Del lado izquierdo se guarda como siempre.

**Portapapeles**
- **⌘C y, sin soltar ⌘, un número del 1 al 9** → guarda lo copiado en esa ranura.
- **⌘V y, sin soltar ⌘, un número del 1 al 9** → pega esa ranura. Lo que tenías copiado se queda como estaba.
- Las 9 ranuras se guardan aunque apagues la Mac.
- Historial de lo último que copiaste (30 elementos, solo en memoria). Con clic lo copias y con clic derecho lo guardas en una ranura.
- No guarda en el historial lo que los gestores de contraseñas marcan como privado (por ejemplo, 1Password).

**Compañero** (vive junto al notch)
- Un personajito original vive junto al notch **todo el tiempo** y tiene más de 30 animaciones: se asoma detrás del notch, **camina de un lado al otro**, se **cuelga de un hilo** y se columpia, brinca, gira, saluda, bosteza, baila, toma café, lee, se estira, estornuda y te manda corazones. **Te sigue con la mirada** cuando acercas el mouse.
- **Vehículos:** cruza al otro lado del notch en **patineta** (con "ollie"), llega un **cochecito** que pita "¡pip pip!", despega en **cohete** con cuenta regresiva (y cae mareado), un **ovni** se lo lleva con su rayo y lo deja del otro lado, y una **avioneta** pasa por debajo del notch jalando un letrero ("¡Tú puedes!", "Toma agua", "México Makers"…).
- **Su amigo:** un cuadradito con antena (del color contrario al suyo) sale de detrás del notch; se saludan, chocan las manos, bailan juntos y se despiden.
- **Juegos:** pesca desde la barra de menús, hace malabares, juega fútbol, hace burbujas de jabón, se toma fotos con flash y hace magia (¡puf! y aparece del otro lado).
- Cuando Claude trabaja saca su **caja de herramientas** y martilla; cuando piensa le salen puntitos; si te espera levanta la mano; al terminar una tarea **festeja con confeti**.
- **Se duerme** (con sus "z") si no usas la Mac unos minutos o en la noche, y bosteza al despertar.
- **Te presenta lo que abres:** cuando abres algo por voz (un chat, Cowork, la terminal, ChatGPT…), vuela con su gorrito de hélice hasta la ventana, se para en ella, dice "¡Aquí está!" y regresa. No mueve tus ventanas. Se apaga en Configuración › Compañero.
- **Sale de paseo:** de vez en cuando se deja caer del notch (a veces en **paracaídas**), **aterriza arriba del Dock** (o abajo de la pantalla si el Dock se esconde) y ahí camina, anda en **patineta**, maneja su **coche**, recibe a su **amigo**, hace magia, juega fútbol, se tapa de la **lluvia con su paraguas** y hace sus cosas. Regresa al notch **en globo, en ovni o en cohete**. Tócalo para que brinque; dos toques y regresa. No sale si hay una app en pantalla completa.
- Te habla con **globitos de texto**: cuando Claude termina, tips, RAM o batería baja, archivos en el estante. Si tocas un globito, abre lo que corresponde.
- En la noche se pone somnoliento; cuando lo llamas con la voz, te pone atención.
- **Reacciona a tu Mac:** si la Mac va a tope (mucho CPU o se calienta) **suda y se abanica**; con la batería en 10 % o menos **tiembla** con una pila roja; cuando suena tu música **mueve la cabeza al ritmo** con notitas; y al conectar el cargador se pone feliz ("¡Ñam! Energía"). Se apaga en Configuración › Compañero.
- Elige su **color** (azul, rosa, morado, verde, naranja, terracota… o uno a tu gusto) en **Configuración › Compañero**, donde también se apaga.

**Claude** (tus sesiones de Claude Code, en vivo y sin costo extra)
- **Actividad en vivo junto al notch:** con la isla cerrada, unos personajitos (uno por sesión) se asoman a los lados del notch. Trabajan, piensan, te esperan o festejan según lo que hace cada sesión, y a la derecha ves qué está haciendo (por ejemplo, "Edita · invoice.ts").
- **Permisos desde el notch:** cuando Claude Code pide permiso, la isla baja sola una tarjeta con **Permitir / Siempre / Negar / Terminal**. Si no eliges en 30 segundos, Claude Code te pregunta en la terminal como siempre.
- **Contesta sus preguntas desde el notch:** cuando Claude te pregunta algo con opciones (por ejemplo "¿qué base de datos uso?"), la tarjeta baja con las opciones. Toca una y listo; si puedes elegir varias, marca las que quieras y toca **Enviar**; con **Escribir…** contestas con tus palabras. Si son varias preguntas, van una tras otra. Te espera al menos 2 minutos; si no contestas (o tocas el botón de terminal), la pregunta aparece en la terminal como siempre.
- **Vista previa del cambio** (apagada de fábrica; se activa en Configuración › Claude): en la tarjeta de permiso ves qué renglones se quitan (rojo) y cuáles se agregan (verde) antes de aprobar una edición.
- **Pestaña exacta** (apagada de fábrica): el botón de terminal te lleva a la **pestaña exacta** de cada sesión en Terminal e iTerm2 (en Ghostty y Warp trae la app al frente). Aplica a sesiones nuevas.
- **Sonidos por evento:** uno distinto cuando pide permiso, cuando te pregunta algo, cuando termina, cuando empieza una sesión, al avisar tu límite de uso, si algo falla y antes de una junta. Se eligen (o se quitan) en Configuración › Claude › Sonidos.
- **Pestaña Claude:** cada sesión con lo último que pediste, sus pasos recientes (Lee, Edita, Ejecuta…), el resumen al terminar y un botón para abrir su terminal.
- **Avisos:** cuando termina una tarea de verdad (que tardó al menos 10 s; se cambia en Configuración), el compañero te lo dice en un globito, con un sonido suave (se puede apagar).
- **Sin ruido:** las sesiones automáticas (Agent SDK y plugins, como las `observer-sessions` de los plugins de memoria) no aparecen ni te avisan. También puedes poner carpetas a ignorar en Configuración › Claude Code.
- **Respóndele por voz:** cuando una sesión termina, Claude Code espera unos segundos (20 por defecto). Di **"responde…"** y tu mensaje (no hace falta "Oye Claudio"), o toca **Responder** en el globito. Tu mensaje le llega a **esa misma sesión** y Claude sigue trabajando, sin tocar la terminal. Si no dices nada o abres la terminal, todo sigue como siempre.
- **Tus límites de uso:** arriba a la derecha de la isla ves dos anillitos: tu **sesión de 5 h** y tu **semana** (verde, naranja arriba de 70 %, rojo arriba de 90 %). Pasa el mouse para ver cuándo se reinician. Te avisa al pasar 80 % y 95 % de la sesión y 90 % de la semana. Los manda Claude Code a su "línea de estado": Isla se pone ahí, sigue mostrando la línea de estado que ya tenías (o una cortita con tus límites) y te la regresa si apagas la opción. Se actualizan mientras usas Claude Code (es el mismo límite para el chat y Cowork).
- **Cómo funciona:** Isla agrega unos avisos (*hooks*) a `~/.claude/settings.json`. Antes guarda un respaldo (`settings.json.isla-respaldo-…`) y no toca tus otros ajustes. No usa la API ni gasta nada extra. Si Isla está cerrada, Claude Code funciona igual que siempre.
- **Para conectarlo:** pestaña Claude › **Conectar con Claude Code**, y luego abre una **sesión nueva** de Claude Code (las que ya estaban abiertas no lo ven).

**Modo programación** (botón ☕ arriba en la isla, o el menú de Isla)
- Mientras está activo, la Mac **no se duerme, no apaga la pantalla y no se bloquea** por inactividad, conectada o con batería. El compañero se queda despierto con su café.
- Ojo: si cierras la tapa, la Mac sí se duerme (salvo que esté conectada a corriente y a un monitor externo).
- También con la voz: "Oye Claudio, modo programación".

**"Oye Claudio"** (voz, 100 % en tu Mac)
- Di **"Oye Claudio"** y la isla se abre en la pestaña Claude. La frase se cambia en **Configuración** y puedes poner varias.
- Luego, o en la misma frase, puedes decir:
  - **"nuevo chat"** + tu mensaje: chat nuevo con Claude usando tu plan, sin costo extra.
  - **"a Gorgias"** (o el nombre de cualquiera de tus **proyectos**) + tu mensaje: se va directo a ese proyecto de Claude.
  - **"cowork"** + tu mensaje: tarea nueva de Cowork.
  - **"Claude Code"** + tu mensaje: sesión nueva de Claude Code en Claude para Mac.
  - **"ChatGPT"** + tu mensaje: chat nuevo en la app de ChatGPT para Mac (o en chatgpt.com si no la tienes), con tu mensaje enviado.
  - **"responde"** + tu mensaje: contesta a la sesión de Claude Code que acaba de terminar.
  - Al quedarte callado (o decir **"enviar"**), Isla lo abre en Claude para Mac con sus links oficiales (`claude://…`), escribe tu mensaje y lo envía. Di **"cancela"** al final para no mandar nada.
  - **"permitir"**, **"siempre"** o **"negar"**: responde el permiso pendiente. Por seguridad, un "sí" o "no" suelto no cuenta.
  - **"terminal"** + tu mensaje: trae la terminal al frente, **escribe lo que dictaste y le da Enter**, sin tocar el teclado (si solo dices "terminal", nada más la trae). Si hay un permiso pendiente, te lleva a la terminal para contestarlo ahí.
  - **"estante"**, **"portapapeles"**, **"Mac"** o **"agenda"**: abre esa pestaña (agenda = pestaña Hoy).
  - **"pausa"**, **"siguiente canción"** o **"canción anterior"**: controla tu música.
  - **"cierra"**: cierra la isla.
  - **"ignora"**: deja que la sesión que terminó siga normal, sin respuesta.
- **Tecla para hablar (más rápido):** mantén presionada la tecla **⌥ derecha**, di lo mismo pero **sin "Oye Claudio"** ("terminal …", "ChatGPT …", "cowork …") y suéltala para mandarlo. Si no dices a dónde, va a un chat nuevo de Claude. Si la usas para escribir (⌥ + otra tecla) no hace nada. Se apaga en Configuración › Voz.
- **¿No quieres el micrófono siempre prendido?** Apaga **Escuchar siempre** en Configuración › Voz: el micrófono se queda apagado y solo escucha mientras mantienes **⌥ derecha** (o tocas **Responder**). El "tink" te avisa cuando ya te escucha.
- En **Configuración › Registro** ves cuánto tardó en entender cada orden (por ejemplo, "entendí la orden 0.8 s después").
- El reconocimiento corre en tu Mac; el audio no sale de tu computadora. Mientras escucha, macOS muestra el punto naranja del micrófono.
- **Tu diccionario:** en Configuración › Voz agrega **palabras** que use mucho (nombres de clientes, marcas) para que las entienda mejor, y **correcciones** para lo que oye mal ("cloud code" → "Claude Code"). No necesitas ninguna app de dictado ni cuesta nada.
- **Limpieza automática:** antes de mandar lo que dictaste, Isla quita "eh", "mmm", "este…" y palabras repetidas, y pone mayúsculas, ¿? y punto final. Con **Apple Intelligence** (encendida de fábrica si tu Mac la tiene activada) queda todavía mejor: corre en tu Mac, es gratis y no usa internet. Si tarda más de 4 segundos, usa la limpieza normal. En una terminal sin Claude Code solo aplica tus correcciones (sin mayúsculas ni puntos, para no romper comandos).
- Si la isla dice "Activa Dictado en este idioma", ve a Ajustes del Sistema › Teclado › Dictado, actívalo con tu idioma y deja que se descargue.

**Configuración** (menú de Isla › Configuración… o el engrane ⚙︎ de la isla), en pestañas:
- **Voz:**
  - Frase para despertar, tecla ⌥ derecha, idioma, **tiempo para decir la orden** (10 s) y **silencio que termina un dictado**.
  - "Última frase escuchada", para ver cómo te está entendiendo.
  - **Diccionario y limpieza:** tus palabras, tus correcciones, limpieza automática, Apple Intelligence y un botón para **probar la limpieza**.
  - **Claude por voz:** dónde se abre (Claude para Mac o el navegador), si se envía solo, y un botón para **probar**.
  - **Proyectos de Claude:** agrega tus proyectos con su nombre y su link (`https://claude.ai/project/…`, cópialo del navegador). Puedes poner otras formas de decir el nombre, por si la voz lo entiende distinto.
- **Claude:**
  - Conectar o desconectar, aprobar desde la isla y **tiempo para responder un permiso**.
  - Contestar preguntas desde la isla, **vista previa del cambio** y **pestaña exacta** (estas dos, apagadas de fábrica).
  - Actividad en vivo, límites de uso, avisar solo si la tarea tardó al menos X segundos, ignorar sesiones automáticas y carpetas.
  - **Sonidos:** uno para cada cosa, con botón para escucharlo.
  - **Responder a Claude Code por voz:** activarlo, cuántos segundos espera y "solo si no estás viendo la terminal".
- **Hoy:** música (mostrarla, el aviso al cambiar de canción, los audífonos del monito con la isla cerrada y la letra) y agenda (Calendario de la Mac, agregar cuenta de Gmail/Outlook, links .ics y cuánto antes te avisa).
- **Compañero:** mostrarlo, globitos, cada cuánto platica, su **color**, si te sigue con la mirada, si te presenta las ventanas, sus **reacciones**, cada cuánto **sale a pasear**, cuándo **se duerme** y un botón para mandarlo de paseo.
- **Isla:** modo programación, estilo, espera al pasar el mouse, abrir al iniciar sesión, estante y limpieza, y portapapeles.
- **Registro:** paso a paso de lo que hizo Isla con tu voz y con Claude. Si algo falla, **Copiar registro** y pégalo en el chat.

Los cambios se aplican al momento, sin reinstalar.

**Mac** (datos en vivo de tu computadora)
- **CPU**, **memoria** (con la presión de memoria, como el Monitor de Actividad), **disco libre**, **temperatura** del chip y **batería** (porcentaje, carga y ciclos).
- **Apps que más RAM usan:** el top 5, sumando sus procesos auxiliares (Chrome, Slack, VS Code…). Con la ✕ cierras la app de forma normal; si hay algo sin guardar, la app te pregunta.
- **Liberar RAM:** vacía la caché de memoria del sistema (`purge`) y te pide tu contraseña. El efecto es temporal; lo que de verdad libera RAM es cerrar apps pesadas.
- **Liberar espacio:** mide y limpia, siempre con confirmación:
  - **Papelera**: la vacía con Finder. La primera vez macOS pregunta si Isla puede controlar Finder.
  - **Cachés de apps** (`~/Library/Caches`): se borran y las apps los vuelven a crear.
  - **Descargas de más de 30 días** y **capturas de más de 14 días**: van a la Papelera, así que puedes recuperarlas.
  - **Cachés de desarrollo** (DerivedData de Xcode y caché de npm): se borran y se regeneran solos.
- **Avisos automáticos** junto al notch (máximo uno por hora de cada tipo): disco casi lleno (menos de 10 GB), RAM al límite y Mac muy caliente.
- La isla solo mide mientras está abierta; cerrada, casi no consume nada.
- La temperatura del chip se lee con una función interna de macOS (la misma que usan apps como *Stats*). Si tu versión de macOS no la permite, se muestra la temperatura de la batería.

**Estilo**
- **Cristal líquido** (predeterminado): en macOS 26 Tahoe o superior usa el efecto *Liquid Glass* real de Apple. En versiones anteriores usa el vidrio esmerilado del sistema. Sigue tu modo claro u oscuro y tu color de acento.
- **Negro clásico**: toda la isla en negro, igual que la Dynamic Island del iPhone.
- Se cambia desde el ícono de la barra de menús.

---

## Requisitos

- Mac con **macOS 13 Ventura o superior** (con notch se ve mejor; sin notch aparece una "isla" virtual).
- **Herramientas de línea de comandos de Apple** (gratis). Si nunca las instalaste, abre **Terminal** y corre:
  ```bash
  xcode-select --install
  ```
  Acepta la ventana que aparece y espera a que termine (5 a 10 minutos).

## Instalación (3 pasos)

1. **Descomprime** `IslaMM.zip` donde quieras (por ejemplo, en Documentos).
2. Abre **Terminal**, escribe `cd ` (con espacio), **arrastra la carpeta IslaMM** a la Terminal y presiona Enter.
3. Corre:
   ```bash
   ./instalar.sh
   ```
   El script compila la app, la instala en **Aplicaciones** y la abre.

La primera vez macOS te pedirá permisos:

| Aviso | Para qué | Qué hacer |
|---|---|---|
| "Isla quiere controlar Finder" (solo al vaciar la Papelera) | Vaciar la Papelera | **OK** |
| "Isla quiere controlar Spotify / Música" (al usar los botones de música) | Pausar y cambiar de canción | **OK** (si dices que no, usa las teclas multimedia) |
| "Isla quiere acceder a tus Calendarios" (al activar la agenda) | Ver tus juntas en la pestaña Hoy | **Permitir acceso total** |
| Micrófono y Reconocimiento de voz | "Oye Claudio" | **Permitir** |
| Contraseña de tu Mac (solo al usar "Liberar RAM") | Ejecutar `purge` | Escribe tu contraseña |
| "Isla quiere acceder a Escritorio" | Detectar tus capturas | **Permitir** |
| "Isla quiere acceder a Descargas" | Mostrar descargas nuevas | **Permitir** |
| Accesibilidad | Atajos ⌘C / ⌘V + número | Ajustes del Sistema › Privacidad y seguridad › **Accesibilidad** › activa **Isla** |

Cuando actives Accesibilidad, verás el aviso "Atajos activos" en el notch.

## Uso diario

- **Abrir:** lleva el mouse al notch. **Cerrar:** aleja el mouse o haz clic fuera.
- **Menú** (ícono en la barra de menús): estilo, activar o desactivar capturas y descargas, abrir al iniciar sesión, vaciar el estante o el historial, salir.
- **Tip para capturas instantáneas:** por defecto macOS guarda la captura hasta que desaparece la miniatura flotante (unos 5 s). Para que lleguen al momento, presiona **⌘⇧5 › Opciones** y desactiva **"Mostrar miniatura flotante"**.

## Crear un instalador DMG

Si prefieres un `.dmg` (el clásico "arrastra la app a Aplicaciones"), corre desde la carpeta del proyecto:

```bash
./crear-dmg.sh
```

Se crea `Isla-<versión>.dmg` (por ejemplo `Isla-1.9.dmg`) en la carpeta del proyecto y Finder te lo muestra. Ábrelo y arrastra **Isla** a **Aplicaciones**. La primera vez, macOS puede preguntar si Terminal puede controlar Finder: dale **OK** para que la ventana del DMG quede acomodada (si no, funciona igual).

> **Si lo compartes con otra persona:** como la app no está firmada con una cuenta de desarrollador de Apple (99 USD al año), su Mac dirá que "no se puede verificar el desarrollador". Para abrirla: Ajustes del Sistema › Privacidad y seguridad › **Abrir de todos modos**. En tu propia Mac no pasa, porque el DMG lo creaste tú.

## Actualizar o reinstalar

Vuelve a correr `./instalar.sh` (o crea un DMG nuevo con `./crear-dmg.sh`) desde la carpeta del proyecto.

> Si no tienes cuenta de desarrollador de Apple, cada reinstalación te pedirá **reactivar Accesibilidad** (macOS lo exige cuando cambia la app) y volver a dar permiso de micrófono y de calendario. El script limpia los permisos anteriores por ti; solo vuelve a activarlos.

## Desinstalar

```bash
./desinstalar.sh
```

También quita los avisos de Claude Code que Isla agregó. Para quitar solo esos avisos, usa el menú de Isla › **Desconectar Claude Code**.

## Problemas comunes

| Problema | Solución |
|---|---|
| `xcrun: error: invalid active developer path` | Corre `xcode-select --install`. |
| Error de compilación con "SDK is not supported by the compiler" | Actualiza las herramientas: Ajustes del Sistema › General › Actualización de software, o reinstálalas con `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`. |
| Los atajos ⌘C/⌘V + número no hacen nada | En Accesibilidad, quita **Isla** con el botón "−", vuelve a abrir la app y actívala de nuevo. |
| No aparecen las capturas | Revisa en el menú que "Capturas de pantalla → isla" esté activado y que diste permiso a Escritorio (Ajustes › Privacidad › Archivos y carpetas). |
| La pestaña Claude no muestra nada | Conecta en la pestaña Claude y abre una **sesión nueva** de Claude Code. Si Claude Code avisa que los hooks cambiaron, revísalos con `/hooks`. |
| No reconoce el nombre de un proyecto | Ponle formas cortas en Configuración › Proyectos › "Otras formas de decirlo" (por ejemplo "cotizador" para "Vamos a cotizar una impresión"). En **Registro** ves exactamente qué oyó. Puedes hacer pausas: Isla junta lo que dices antes y después. |
| "Oye Claudio" no responde | En Configuración › Voz revisa "Última frase escuchada" para ver cómo te entiende y ajusta la frase. Revisa también los permisos de Micrófono y Reconocimiento de voz, y que el Dictado esté descargado. |
| "Nuevo chat" no abre Claude | En Configuración › Claude por voz toca **Abrir chat de prueba**. Si no abre, actualiza Claude para Mac (los links `claude://` son de versiones recientes) o cambia a "Claude en el navegador". En **Registro** ves en qué paso se quedó. |
| El texto no se pega en el proyecto | El proyecto tarda en cargar: queda copiado, pégalo con ⌘V. Revisa que el link del proyecto sea el correcto (botón ↗ en Configuración › Proyectos). |
| No me deja responder a Claude Code por voz | Aplica a **sesiones nuevas** de Claude Code (después de abrir Isla 1.4). "Oye Claudio" debe estar encendido. |
| No veo esta conversación de Cowork / claude.ai en la isla | Esas corren en la nube, no en tu Mac, así que los avisos de Claude Code no las ven. Isla muestra las sesiones de Claude Code que corren en tu Mac. |
| Isla se cerraba sola | Era un error del micrófono de macOS al cambiar de audífonos (quedaba "tragado" y minutos después cerraba Isla). Ya se atrapa. Además, si Isla se cierra de golpe, un **vigilante** la vuelve a abrir sola y el compañero te avisa; en **Registro** queda lo que pasaba antes. Si la cierras tú (Salir) o la fuerzas a salir, no la reabre. |
| La isla se congeló | Era el servicio de audio de macOS (`coreaudiod`) que a veces se atora al preparar el micrófono; desde la 1.12 eso pasa aparte y la isla ya no se congela (solo "Oye Claudio" dice "Reiniciando el micrófono…" y lo reintenta solo). Si el audio de la Mac se queda mal, en Terminal corre `sudo killall coreaudiod` (macOS lo vuelve a levantar). |
| No veo mis límites de uso | Aparecen al usar Claude Code en una **sesión nueva** (Claude Code los manda después de su primera respuesta) y solo con planes Pro o Max. |
| La isla no se ve | Está sobre el notch de la pantalla integrada. En un monitor externo sin notch aparece como una pastilla negra arriba al centro. |
| La pregunta de Claude no aparece en la isla | Aplica a **sesiones nuevas** de Claude Code después de instalar la 1.9, y "Contestar las preguntas de Claude desde la isla" debe estar encendido (Configuración › Claude). |
| No veo mis juntas | Configuración › Hoy: enciende "Calendario de la Mac" y da el permiso (si lo negaste: Ajustes del Sistema › Privacidad y seguridad › Calendarios › Isla). Para Gmail u Outlook/Teams, agrega la cuenta en **Cuentas de internet** con "Calendarios" activado, o pega el link .ics. Debajo de cada link ves si se pudo leer. |
| No sale lo que suena | Funciona con Spotify y Música (Apple Music). Cambia de canción una vez para que Isla lo vea. |
| La letra no avanza o va desfasada | La primera vez macOS pregunta si Isla puede controlar Spotify o Música: dale **OK** (así sabe en qué segundo va la canción). Si lo negaste: Ajustes del Sistema › Privacidad y seguridad › Automatización › Isla. |
| "No encontré la letra de esta canción" | LRCLIB no la tiene (pasa con canciones nuevas o poco conocidas). Sigue viendo la carátula y los controles. |
| Apple Intelligence dice "no disponible" | Actívala en Ajustes del Sistema › Apple Intelligence y Siri (necesita una Mac con chip Apple y macOS 26). Mientras, Isla usa la limpieza normal. |

## Estructura del proyecto

```
IslaMM/
├── Package.swift              Proyecto Swift (se compila con `swift build`)
├── Sources/IslaObjC/          Ayudante en Objective-C que atrapa errores de macOS (NSException)
├── instalar.sh                Compila e instala directo en Aplicaciones
├── crear-dmg.sh               Compila y crea el instalador Isla-<versión>.dmg
├── desinstalar.sh             Quita la app, sus datos y permisos
├── scripts/compilar.sh        Parte compartida: compila, arma Isla.app y la firma
├── Resources/
│   ├── Info.plist             Nombre, ícono, sin ícono en el Dock, textos de permisos
│   └── AppIcon.icns           Ícono
└── Sources/IslaMM/
    ├── IslaMMApp.swift        Punto de entrada
    ├── AppDelegate.swift      Arranque, ícono y menú de la barra superior
    ├── NotchWindow.swift      Ventana flotante sobre el notch + medida del notch
    ├── NotchController.swift  Abrir al pasar el mouse, cerrar, avisos, estilo
    ├── IslandView.swift       Forma de la isla, cristal, encabezado, avisos
    ├── ShelfStore.swift       Estante: capturas, descargas y archivos arrastrados
    ├── ShelfView.swift        Interfaz del estante + miniaturas Quick Look
    ├── FolderWatcher.swift    Vigila carpetas y detecta archivos nuevos y completos
    ├── ClipboardStore.swift   Historial + 9 ranuras (se guardan en disco)
    ├── ClipboardView.swift    Interfaz del portapapeles
    ├── SystemStats.swift      Lectura de CPU, RAM, disco, batería, temperatura y RAM por app
    ├── SystemCleaner.swift    Medición y limpieza de Papelera, cachés, descargas y capturas
    ├── SystemMonitor.swift    Datos en vivo, "Liberar RAM", limpiezas y avisos automáticos
    ├── MacView.swift          Interfaz de la pestaña Mac
    ├── ClaudeHooks.swift      Conexión con Claude Code: socket local, "mensajero" e instalador de hooks
    ├── ClaudeCodeMonitor.swift Sesiones, permisos y actividad en vivo de Claude Code
    ├── ClaudeView.swift       Personajitos, tarjeta de permiso y pestaña Claude
    ├── ClaudeQuestions.swift  Preguntas de Claude (opciones en la isla) y vista previa del cambio
    ├── Sounds.swift           Un sonido para cada evento
    ├── PersonalDictionary.swift Tu diccionario, limpieza del dictado y Apple Intelligence
    ├── NowPlaying.swift       Lo que suena en Spotify / Música: carátula, avance y controles
    ├── Lyrics.swift           La letra sincronizada (LRCLIB)
    ├── CalendarStore.swift    Tu agenda (Calendario de la Mac y links .ics) y links de Teams/Meet/Zoom
    ├── TodayView.swift        Pestaña Hoy: letra en vivo, letra completa, música y agenda
    ├── VoiceWake.swift        "Oye Claudio" (reconocimiento de voz local y dictado)
    ├── HoldToTalk.swift       Tecla para hablar (⌥ derecha)
    ├── ChatGPT.swift          "ChatGPT …": abre la app de ChatGPT (o chatgpt.com) y envía tu mensaje
    ├── ClaudeUsage.swift      Límites de uso (5 h y semana) y la línea de estado de Claude Code
    ├── CrashGuard.swift       Vigilante que reabre Isla y atrapa errores de macOS
    ├── ClaudeChat.swift       Abre Claude con links claude:// (chat, proyecto, Cowork, Code) o el navegador
    ├── ClaudeProjects.swift   Tus proyectos de Claude para mandarles mensajes por voz
    ├── Companion.swift        El compañero: travesuras, sueño, mirada, colores y globitos
    ├── CompanionStage.swift   Dónde está y cómo se mueve junto al notch (caminar, vehículos, su amigo…)
    ├── CompanionRoam.swift    Paseo por la pantalla: caída, Dock, coche, amigo y regreso en globo/ovni/cohete
    ├── BuddyFigure.swift      Dibujo del personaje: ojos, bracito, piecitos y sus cosas
    ├── StageExtras.swift      Vehículos, el amigo, humo y letreros (todo dibujado, sin imágenes)
    ├── AirDrop.swift          Mandar por AirDrop y las dos zonas al soltar (estante / AirDrop)
    ├── KeepAwake.swift        Modo programación (que la Mac no se duerma)
    ├── IslaLog.swift          Registro de lo que hace Isla (Configuración › Registro)
    ├── SettingsView.swift     Ventana de Configuración
    ├── KeyInterceptor.swift   Atajos ⌘C/⌘V + número a nivel sistema
    ├── Permissions.swift      Permiso de Accesibilidad
    └── Theme.swift            Colores del sistema, cristal y utilidades
```

**Datos de la app:** `~/Library/Application Support/IslaMM/` (ranuras, lista del estante e imágenes arrastradas desde el navegador). Los archivos del estante **no se mueven ni se copian**: la isla solo los enlaza. Si quitas un archivo de la isla, sigue en su carpeta.

## Personalizar rápido

- **Tamaño de la isla abierta:** `expandedSize` en `NotchController.swift`.
- **Cuánto espera ⌘V a que presiones un número:** `pasteWindow` en `KeyInterceptor.swift` (0.9 s).
- **Número de elementos del historial:** `maxHistory` en `ClipboardStore.swift`.
- **Máximo de archivos en el estante:** `maxItems` en `ShelfStore.swift`.
