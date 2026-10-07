# Guía de instalación y uso de la plataforma web

Esta guía es para quien quiere **usar la plataforma de balance hídrico desde
el navegador**, sin programar. No hace falta saber R ni conocimientos
técnicos: solo seguir los pasos en orden.

Al terminar vas a tener la plataforma funcionando en tu computadora, abierta
en el navegador en la dirección `http://localhost:3000`, lista para simular un
cultivo de trigo, maíz o soja.

**Índice**

1. [Cómo funciona (en dos minutos)](#1-cómo-funciona-en-dos-minutos)
2. [Qué necesitás](#2-qué-necesitás)
3. [Instalar Docker](#3-instalar-docker)
   - [Windows](#31-windows)
   - [Mac](#32-mac)
   - [Comprobar que Docker funciona](#33-comprobar-que-docker-funciona)
4. [Preparar la plataforma](#4-preparar-la-plataforma)
5. [Instalar la plataforma (un solo comando, una sola vez)](#5-instalar-la-plataforma-un-solo-comando-una-sola-vez)
6. [Usar la plataforma](#6-usar-la-plataforma)
7. [Detener, reiniciar y actualizar](#7-detener-reiniciar-y-actualizar)
8. [Problemas frecuentes](#8-problemas-frecuentes)
9. [Desinstalar](#9-desinstalar)

---

## 1. Cómo funciona (en dos minutos)

La plataforma está formada por **dos programas** que trabajan juntos:

| Programa | Qué hace |
|---|---|
| **Frontend** | La página web que ves y en la que completás el formulario |
| **API** | El "motor" que hace los cálculos de balance hídrico |

Para no tener que instalar y configurar cada uno a mano, ambos vienen
empaquetados en **contenedores**. Un contenedor es una caja cerrada que ya trae
adentro el programa y todo lo que necesita para funcionar. El programa que
sabe abrir esas cajas se llama **Docker**.

Entonces el proceso es:

1. Instalás **Docker Desktop** (una sola vez): una aplicación con ventanas y
   botones, que incluye el motor de Docker.
2. Bajás un archivo de texto muy chico, `docker-compose.yml`, que le dice a
   Docker cómo levantar los dos programas juntos.
3. Copiás y pegás **un solo comando** (una única vez) para descargar los
   programas.
4. Desde ahí, todo se maneja con los **botones de Docker Desktop**: iniciar,
   detener, abrir la plataforma y ver mensajes de error. No hace falta volver
   a escribir comandos.

No se instala nada más en tu computadora, y se puede borrar todo sin dejar
rastros (sección 9).

## 2. Qué necesitás

- Una computadora con **Windows 10/11 (64 bits)** o con **macOS** (Intel o
  Apple Silicon: M1, M2, M3…).
- **Conexión a internet** durante la instalación y la primera vez que se
  inicia la plataforma (hay que descargar los programas). Después, para
  usarla, no hace falta.
- Aproximadamente **8 GB de memoria RAM**. En el disco, Docker Desktop ocupa
  unos 2 GB y la plataforma otros ~1,5 GB: conviene tener **al menos 10 GB
  libres**.
- Poder instalar programas en tu computadora (permisos de administrador).

## 3. Instalar Docker

Docker se instala en Windows y en Mac con una aplicación llamada **Docker
Desktop**, que ya incluye el *Docker Engine* (el motor de Docker) y la
herramienta *Docker Compose* que vamos a usar. No hace falta instalar nada más
por separado.

### 3.1 Windows

**Antes de empezar.** Docker en Windows necesita que tu computadora tenga
activada la *virtualización*. En la mayoría de las computadoras modernas ya
viene activada. Para comprobarlo: abrí el **Administrador de tareas**
(`Ctrl + Mayús + Esc`) → pestaña **Rendimiento** → **CPU**. Abajo a la derecha
tiene que decir **Virtualización: Habilitada**. Si dice *Deshabilitada*, ver
[problemas frecuentes](#8-problemas-frecuentes).

**Pasos.**

1. Entrá a <https://www.docker.com/products/docker-desktop/> y hacé clic en
   **Download for Windows**. Se descarga un archivo llamado
   `Docker Desktop Installer.exe`.
2. Abrí el archivo descargado. Cuando pregunte, dejá tildada la opción
   **Use WSL 2 instead of Hyper-V** (viene tildada por defecto). WSL 2 es un
   componente de Windows que Docker usa por dentro; el instalador lo prepara
   solo.
3. Hacé clic en **Ok** / **Install** y esperá a que termine (unos minutos).
4. Cuando lo pida, hacé clic en **Close and restart** para **reiniciar la
   computadora**.
5. Después del reinicio, abrí **Docker Desktop** desde el menú Inicio. La
   primera vez muestra los términos del servicio: hacé clic en **Accept**. Si
   ofrece crear una cuenta o iniciar sesión, podés elegir **Skip** (omitir):
   no hace falta cuenta.
6. Esperá a que, abajo a la izquierda de la ventana de Docker Desktop, el
   ícono de la ballena se ponga **verde** y diga **Engine running**. Mientras
   diga *starting* todavía no está listo.

> **Importante:** Docker Desktop tiene que estar **abierto** (aunque sea
> minimizado) cada vez que quieras usar la plataforma.

### 3.2 Mac

**Antes de empezar.** Fijate qué procesador tiene tu Mac: menú **Apple** (la
manzana, arriba a la izquierda) → **Acerca de esta Mac**. Si dice **Chip:
Apple M1/M2/M3…** es *Apple Silicon*; si dice **Procesador: Intel…** es
*Intel*.

**Pasos.**

1. Entrá a <https://www.docker.com/products/docker-desktop/> y hacé clic en
   **Download for Mac**. Elegí la versión que corresponde a tu procesador
   (**Apple Silicon** o **Intel chip**). Se descarga un archivo `Docker.dmg`.
2. Abrí `Docker.dmg` y **arrastrá el ícono de Docker a la carpeta
   Aplicaciones**.
3. Abrí **Docker** desde Aplicaciones (o con Spotlight: `Cmd + Espacio` y
   escribí *Docker*). La primera vez macOS avisa que es una aplicación
   descargada de internet: hacé clic en **Abrir**.
4. Aceptá los términos (**Accept**) y, si te pide una contraseña de tu Mac para
   instalar componentes, escribila. Si ofrece crear una cuenta, podés elegir
   **Skip**.
5. Esperá a que, abajo a la izquierda de la ventana de Docker, el ícono de la
   ballena se ponga **verde** y diga **Engine running**.
6. **Solo si tu Mac es Apple Silicon (M1/M2/M3…):** los programas de la
   plataforma están preparados para procesadores Intel/AMD, y Docker los
   ejecuta en modo compatibilidad. Para que ande bien: en Docker Desktop abrí
   **Settings** (el engranaje) → **General** y tildá **Use Rosetta for
   x86_64/amd64 emulation on Apple Silicon**. Hacé clic en **Apply & restart**.
   Si no ves esa opción, tu versión ya la trae activada. Los cálculos pueden
   ser algo más lentos que en una computadora Intel, pero funcionan igual.

> **Importante:** Docker Desktop tiene que estar **abierto** cada vez que
> quieras usar la plataforma.

### 3.3 Comprobar que Docker funciona

No hace falta usar comandos para esto: mirá la ventana de **Docker Desktop**.

- Abajo a la izquierda tiene que verse el ícono de la ballena en **verde** con
  el texto **Engine running**.
- En el menú de la izquierda ves las secciones **Containers**, **Images**,
  etc. Son las que vamos a usar.

Si dice *starting* o el ícono está en naranja, esperá un minuto. Si no
arranca, ver [problemas frecuentes](#8-problemas-frecuentes).

**Recomendado: que Docker se abra solo.** En Docker Desktop, hacé clic en el
engranaje (**Settings**) → **General** y dejá tildada la opción **Start Docker
Desktop when you sign in to your computer** (*Iniciar Docker Desktop al iniciar
sesión*). Así, cuando prendas la computadora, la plataforma vuelve a estar
disponible sin hacer nada.

## 4. Preparar la plataforma

Solo hace falta un archivo: `docker-compose.yml`. Es un archivo de texto que le
indica a Docker qué dos programas descargar y cómo conectarlos.

**1. Creá una carpeta** para la plataforma, por ejemplo `balance-hidrico` en
tu carpeta de Documentos.

**2. Poné el archivo `docker-compose.yml` en esa carpeta.** Elegí una de estas
dos formas:

- **Opción A — descargarlo.** Abrí este enlace en el navegador:
  <https://raw.githubusercontent.com/CRC-SAS/balance-hidrico/main/docker-compose.yml>
  Hacé clic derecho en la página → **Guardar como…** → guardalo dentro de la
  carpeta con el nombre exacto `docker-compose.yml`.
- **Opción B — copiarlo.** Abrí el Bloc de notas (Windows) o TextEdit (Mac, en
  modo *Formato → Convertir en texto plano*), pegá el contenido de abajo y
  guardalo en la carpeta con el nombre exacto `docker-compose.yml`.

```yaml
services:
  api:
    image: ghcr.io/crc-sas/balance-hidrico-api:latest
    platform: linux/amd64
    expose:
      - "8000"
    restart: unless-stopped

  frontend:
    image: ghcr.io/crc-sas/balance-hidrico-frontend:latest
    platform: linux/amd64
    ports:
      - "3000:3000"
    environment:
      - API_URL=http://api:8000
    depends_on:
      - api
    restart: unless-stopped
```

> **Cuidado con el nombre.** Windows suele esconder las extensiones y puede
> guardar el archivo como `docker-compose.yml.txt`. Para verificarlo, en el
> Explorador de archivos activá **Ver → Mostrar → Extensiones de nombre de
> archivo**. El nombre final tiene que ser exactamente `docker-compose.yml`.

**Qué dice este archivo, en palabras simples.** Define dos servicios: `api` (el
motor de cálculo) y `frontend` (la página web). Le pide a Docker que descargue
las dos imágenes publicadas por CRC-SAS, que publique la página en el puerto
**3000** de tu computadora y que mantenga el motor de cálculo accesible solo
para la página. `restart: unless-stopped` hace que se reinicien solos si tu
computadora se reinicia, salvo que los hayas detenido vos.

## 5. Instalar la plataforma (un solo comando, una sola vez)

La descarga inicial de los dos programas es el **único paso que requiere
escribir un comando**: copiás y pegás una línea. De ahí en adelante, todo se
maneja con botones desde Docker Desktop.

**1. Abrí una terminal dentro de la carpeta** donde guardaste
`docker-compose.yml`:

- **Windows:** en el Explorador de archivos, entrá a la carpeta, hacé clic en
  la barra de dirección (donde dice la ruta), escribí `powershell` y apretá
  Enter. Se abre una ventana azul o negra.
- **Mac:** abrí **Terminal** (`Cmd + Espacio`, escribí *Terminal*), escribí
  `cd ` (con un espacio al final), arrastrá la carpeta desde el Finder hasta la
  ventana de Terminal y apretá Enter.

**2. Copiá, pegá y apretá Enter** (con **Docker Desktop abierto**):

```bash
docker compose up -d
```

**La primera vez** Docker descarga los dos programas de internet (en total
poco más de 1 GB). Vas a ver barras de progreso y puede tardar **varios
minutos**, según tu conexión. Es normal. Cuando termine, vas a ver líneas con
la palabra **Started** o **Healthy** y vas a poder cerrar la terminal: no la
necesitás más.

**3. Mirá Docker Desktop.** En la sección **Containers** (menú de la izquierda)
aparece un grupo con el nombre de tu carpeta (por ejemplo `balance-hidrico`) que
contiene dos elementos: **api** y **frontend**, ambos con un punto **verde** y
el estado **Running**.

**4. Abrí la plataforma.** En la fila del `frontend`, en la columna **Port(s)**,
hacé clic en el enlace **3000:3000**: se abre el navegador en la plataforma.
También podés abrir el navegador y escribir

> **<http://localhost:3000>**

Tendría que aparecer el formulario *"Elegir localidad…"*.

> Podés guardar `http://localhost:3000` como favorito del navegador: es la
> dirección que vas a usar siempre.

## 6. Usar la plataforma

La plataforma corre **un escenario** (una combinación de lugar, suelo, cultivo,
fechas y condiciones iniciales) contra **todos los años de clima disponibles**
de esa localidad, y te muestra cómo se distribuyen los resultados entre años.

### 6.1 Completar el formulario

**Ubicación y suelo**

| Campo | Qué elegir |
|---|---|
| **Localidad** | El lugar de interés. Cada localidad usa los datos de su estación meteorológica |
| **Suelo** | Los suelos disponibles para esa localidad (se habilita al elegir la localidad). Se muestra el código y el tipo de suelo |

**Cultivo**

| Campo | Qué elegir |
|---|---|
| **Cultivo** | Trigo, maíz o soja |
| **Cultivar** | Variedad del cultivo (se habilita al elegir el cultivo). Por ejemplo, para trigo: intermedio-corto o intermedio-largo |

**Fechas** (solo día y mes; el año no se elige porque se simulan todos)

| Campo | Qué significa |
|---|---|
| **Fecha de siembra** | Cuándo planeás sembrar |
| **Fecha de monitoreo** | El día en que medís el agua del suelo y desde el cual arranca la simulación. Normalmente es **antes** de la siembra (por ejemplo, el 1° de marzo para una siembra de junio) |

**Condiciones iniciales**

| Campo | Qué significa | Opciones |
|---|---|---|
| **Cantidad de rastrojo** | Cuánto rastrojo (restos del cultivo anterior) cubre el suelo. Se elige la opción a la que más se parece tu lote | Baja (0–20 %), Moderada (30–50 %), Muy Alta (80–100 %) |
| **AU — 1er metro** | Cuánta agua útil hay en el primer metro de suelo el día del monitoreo | Seco, Moderadamente seco, Moderadamente húmedo, Húmedo |
| **AU — 2do metro** | Lo mismo para el segundo metro (de 1 a 2 metros de profundidad) | Seco, Moderadamente seco, Moderadamente húmedo, Húmedo |
| **Sandwich seco** | Si hay una capa seca en el medio del perfil (entre 0,6 y 0,9 m), aunque el resto esté húmedo | Sí / No |

*AU significa "agua útil": el agua del suelo que las raíces realmente pueden
aprovechar.* Los cuatro niveles de humedad corresponden aproximadamente a 10 %,
35 %, 65 % y 90 % de agua útil.

Cuando todos los campos obligatorios están completos, el botón **Correr
simulación** se habilita. Hacé clic y esperá unos segundos: la plataforma
simula cada año por separado.

### 6.2 Leer los resultados

Aparecen, de arriba hacia abajo:

1. **Resumen:** cuántos años se simularon y, si los hubo, cuántos no se
   pudieron simular (por ejemplo, por falta de datos de clima en ese año).
2. **Tabla "Siembra"**: situación del suelo y de la lluvia alrededor de la
   siembra.
3. **Tabla "Cultivo"**: confort hídrico durante el período crítico.
4. **Detalle por año:** una fila por cada año simulado.

Las tablas "Siembra" y "Cultivo" resumen los años con estos estadísticos:

| Columna | Significado |
|---|---|
| **Media** | El promedio de todos los años |
| **P20** | Percentil 20: en 2 de cada 10 años el resultado fue igual o menor a este valor |
| **P50** | La mediana: la mitad de los años quedó por debajo y la otra mitad por encima |
| **P80** | Percentil 80: en 8 de cada 10 años el resultado fue igual o menor a este valor |
| **Desvío** | Cuánto varía el resultado de un año a otro (a mayor desvío, más variable) |
| **IQR** | El rango en el que cae la mitad central de los años |

**Qué mide cada variable**

| Variable | Qué significa |
|---|---|
| **Eventos de lluvia ≥10 mm** (14 días antes / 7 después de la siembra) | Cantidad de días de lluvia de 10 mm o más en la ventana que va desde 14 días antes hasta 7 días después de la siembra |
| **Agua útil — 1er metro (%)** | Porcentaje de agua útil en el primer metro de suelo el día de la siembra |
| **Agua útil — 2do metro (%)** | Ídem para el segundo metro |
| **Agua útil — total (%)** | Ídem para todo el perfil (0–2,1 m) |
| **Confort hídrico — período crítico (%)** | Qué porcentaje del agua que el cultivo necesita para transpirar pudo realmente obtener durante su período crítico. 100 % significa que nunca le faltó agua |

> **¿Por qué el agua útil puede dar más de 100 %?** El 100 % corresponde al
> suelo en capacidad de campo (lleno de agua, pero sin exceso). Si llovió
> mucho, el suelo puede estar por encima de ese nivel (hasta saturación)
> y el porcentaje supera 100 %. No es un error.

La columna **Sandwich seco** de la tabla de detalle indica, para cada año, si
el día de la siembra había una capa seca intermedia (Sí/No). No se resume en
los estadísticos porque es una respuesta de tipo Sí/No.

Para simular otro caso, cambiá los campos del formulario y volvé a hacer clic
en **Correr simulación**.

## 7. Detener, reiniciar y actualizar

Todo se hace desde **Docker Desktop → Containers**, con los botones de la fila
del grupo (por ejemplo `balance-hidrico`). Al usar los botones del grupo, se
aplican a los dos programas a la vez.

| Quiero… | Qué hacer en Docker Desktop |
|---|---|
| **Detener** la plataforma | Botón **■ Stop** del grupo |
| **Volver a iniciarla** | Botón **▶ Start** del grupo, y esperar a que los dos digan *Running* |
| **Abrirla** | Enlace **3000:3000** del `frontend` (o <http://localhost:3000>) |
| **Ver los mensajes** (para diagnosticar un problema) | Hacer clic en el nombre del contenedor (`api` o `frontend`) → pestaña **Logs** |
| **Reiniciarla** si algo no responde | Botón **Restart** (↻) del grupo |

> **Si apagás la computadora:** la plataforma se reinicia sola cuando vuelva a
> abrirse Docker Desktop, salvo que la hayas detenido vos con **Stop**.

**Actualizar a la última versión.** Cuando CRC-SAS publica una versión nueva
(por ejemplo, con datos de clima más recientes), tu copia no cambia sola. Para
actualizarla hay que volver a descargar los programas, con otro comando de una
línea. Abrí la terminal en la carpeta (como en la sección 5) y ejecutá estas
dos líneas, una después de la otra:

```bash
docker compose pull
docker compose up -d
```

## 8. Problemas frecuentes

**Docker Desktop dice "Engine starting" mucho tiempo, o no abre.**
Esperá unos minutos la primera vez. Si sigue igual, cerralo por completo y
volvelo a abrir; si persiste, reiniciá la computadora.

**La terminal dice "Cannot connect to the Docker daemon", "error during
connect" o "docker: command not found".**
Docker Desktop no está abierto o todavía está arrancando. Abrilo y esperá a
que diga **Engine running**. Después volvé a ejecutar el comando.

**Windows: Docker Desktop dice que la virtualización está deshabilitada, o
que WSL 2 no está instalado.**
- *Virtualización:* hay que activarla en el BIOS/UEFI de la computadora
  (opción llamada *Intel VT-x*, *AMD-V* o *SVM Mode*). Los pasos dependen de la
  marca de la computadora; buscá "activar virtualización BIOS" junto con el
  modelo. En computadoras de trabajo, consultá al área de sistemas.
- *WSL 2:* abrí PowerShell **como administrador** (clic derecho → *Ejecutar
  como administrador*), escribí `wsl --install`, reiniciá la computadora y
  volvé a abrir Docker Desktop.

**Mac Apple Silicon: aparece el aviso *"The requested image's platform
(linux/amd64) does not match the detected host platform (linux/arm64)"*.**
Es solo un aviso: las imágenes están hechas para procesadores Intel/AMD y
Docker las ejecuta en modo compatibilidad. Si realmente no arranca, activá la
opción de Rosetta descripta en la sección [3.2](#32-mac).

**En Docker Desktop, el `frontend` o el `api` aparece en rojo / *Exited*, o
al iniciar dice "port is already allocated" / "Bind for 0.0.0.0:3000
failed".**
Otro programa de tu computadora ya está usando el puerto 3000. Cerralo, o
cambiá el puerto de la plataforma: en `docker-compose.yml`, reemplazá
`"3000:3000"` por `"3001:3000"`, ejecutá otra vez `docker compose up -d` (sección
5) y entrá a <http://localhost:3001>.

**El navegador dice "No se puede acceder a este sitio" en `localhost:3000`.**
Entrá a Docker Desktop → **Containers** y comprobá que el `frontend` y el
`api` estén en **Running**. Si alguno no lo está, apretá **Start** en el grupo.
Si recién los iniciaste, esperá unos segundos.

**La página carga pero al simular aparece "No se pudo conectar con el
servicio de simulación".**
El motor de cálculo (`api`) todavía está arrancando o se detuvo. En
**Containers**, verificá que `api` esté en **Running**, esperá medio minuto y
volvé a intentar. Si persiste, hacé clic en `api` → **Logs** para ver los
mensajes.

**Aparece "N año(s) no se pudieron simular".**
Para esos años, la ventana de simulación pedida se sale del rango de clima
disponible (por ejemplo, un monitoreo en el año anterior al primer año de la
serie). Los demás años se calculan y resumen normalmente.

**Al ejecutar `docker compose up -d` aparece "denied" o "unauthorized".**
Verificá que el nombre de las imágenes en `docker-compose.yml` sea exactamente
`ghcr.io/crc-sas/balance-hidrico-api:latest` y
`ghcr.io/crc-sas/balance-hidrico-frontend:latest`, y que tengas conexión a
internet.

## 9. Desinstalar

Todo desde **Docker Desktop**:

1. **Containers:** en la fila del grupo (por ejemplo `balance-hidrico`), hacé
   clic en el ícono del tacho de basura (**Delete**) y confirmá. Esto detiene y
   borra la plataforma.
2. **Images:** tildá las dos imágenes `ghcr.io/crc-sas/balance-hidrico-api` y
   `ghcr.io/crc-sas/balance-hidrico-frontend` y hacé clic en **Delete** para
   liberar el espacio en el disco.
3. Borrá la carpeta que contiene `docker-compose.yml`.

Para desinstalar Docker Desktop, usá el desinstalador habitual de tu sistema
(Windows: *Configuración → Aplicaciones*; Mac: arrastrá Docker de Aplicaciones a
la Papelera).
