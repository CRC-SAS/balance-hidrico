# Diseño y arquitectura — balancehidrico

Este documento describe el método de balance hídrico **desde el punto de
vista de la ingeniería de software**: cómo está organizado el código, qué
contratos de datos hay entre componentes, cómo se despliega la plataforma web
y cómo se prueba. Las ecuaciones y procedimientos agronómicos están en el
[`MANUAL_TECNICO.md`](MANUAL_TECNICO.md); la instalación y el uso, en las
guías enlazadas desde el [`README.md`](../README.md).

## Índice

1. [Visión general](#1-visión-general)
2. [Principios de diseño](#2-principios-de-diseño)
3. [Estructura del repositorio](#3-estructura-del-repositorio)
4. [El paquete R](#4-el-paquete-r)
5. [Scripts de corrida](#5-scripts-de-corrida)
6. [Base de datos de la plataforma](#6-base-de-datos-de-la-plataforma)
7. [API (R/plumber)](#7-api-rplumber)
8. [Frontend (Next.js)](#8-frontend-nextjs)
9. [Despliegue: Docker y CI/CD](#9-despliegue-docker-y-cicd)
10. [Estrategia de pruebas](#10-estrategia-de-pruebas)
11. [Extender el sistema](#11-extender-el-sistema)

---

## 1. Visión general

El sistema tiene tres capas que comparten el mismo motor de cálculo:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Plataforma web (un escenario, todos los años de clima)             │
│                                                                     │
│   Navegador ──► frontend (Next.js :3000) ──► api (R/plumber :8000)  │
│                      │                              │               │
│                      └──── lee catálogo ────┐       │ lee clima     │
│                                             ▼       ▼               │
│                                      balance_hidrico.sqlite         │
└─────────────────────────────────────────────────────────────────────┘
            │ usa
            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  scripts/lib_simular.R   (orquesta los 5 pasos de un escenario)     │
└─────────────────────────────────────────────────────────────────────┘
            │ llama
            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Paquete R `balancehidrico`  (motor: funciones puras, un archivo    │
│  por paso)                                                          │
└─────────────────────────────────────────────────────────────────────┘
            ▲ usa
            │
   scripts/simular.R (1 escenario)   scripts/simular_batch.R (lote)
```

- **Motor** (`R/`): el método CRC-SAS como paquete R formal.
- **Orquestación** (`scripts/`): lectura de insumos, armado de escenarios y
  escritura de resultados, fuera del paquete.
- **Plataforma** (`api/`, `frontend/`): interfaz web sobre el mismo motor.

El motor no sabe nada de archivos, bases de datos ni HTTP; esas
responsabilidades viven en las capas de arriba.

## 2. Principios de diseño

- **Paquete R formal** (`DESCRIPTION`, `NAMESPACE`, `R/`, `man/`,
  `tests/testthat/`, documentación con roxygen2), no scripts sueltos. Lo
  consumen tanto los scripts de corrida como la API.
- **Un archivo por paso del método**, con alta cohesión y bajo acoplamiento
  (`fenologia.R`, `profundizacion_radicular.R`, `curva_kcb.R`,
  `balance_hidrico.R`, `salidas.R`).
- **Funciones puras.** Cada paso recibe datos ya parseados (tibbles, listas,
  fechas), no hace E/S y no depende del estado interno de otros pasos: se
  comunican solo por argumentos y valores de retorno. Cada paso se prueba de
  forma aislada.
- **Entradas por archivos legibles:** clima en **CSV**, parámetros de
  cultivo/estación/suelo y constantes en **YAML** comentado.
- **Fallar rápido y cerca del origen.** Los `obtener_*()` validan que el
  cultivo, cultivar, estación o suelo pedidos existan y abortan con
  `rlang::abort()` listando las opciones válidas, en lugar de dejar que un
  `NULL` se propague hasta romper lejos del origen.
- **Reproducibilidad.** Todo lo estocástico (relleno de huecos climáticos)
  usa una semilla explícita y fija por defecto; la misma entrada produce
  siempre la misma salida.
- **Pruebas automáticas obligatorias** con testthat, con valores de referencia
  reales siempre que sea posible.

## 3. Estructura del repositorio

```
balance-hidrico/
├── README.md                     punto de entrada
├── DESCRIPTION, NAMESPACE, LICENSE   metadatos del paquete R
├── R/                            código del paquete (motor)
│   ├── fenologia.R                 Paso 1
│   ├── profundizacion_radicular.R  Paso 2
│   ├── curva_kcb.R                 Paso 3
│   ├── balance_hidrico.R           Paso 4
│   ├── salidas.R                   Paso 5
│   ├── utils_clima.R               Tm, fotoperíodo, ETo
│   ├── imputacion_clima.R          relleno de huecos climáticos
│   └── io.R                        lectura de CSV/YAML y `obtener_*()`
├── man/                          documentación de funciones (generada)
├── tests/testthat/               pruebas automáticas y fixtures
├── inst/extdata/                 datos de ejemplo y constantes empaquetadas
│   ├── clima_ejemplo.csv
│   ├── parametros_ejemplo.yml
│   └── constantes.yml
├── scripts/                      orquestación fuera del paquete
│   ├── lib_simular.R               lógica compartida
│   ├── simular.R                   un escenario → CSV
│   ├── simular_batch.R             un lote → CSV acumulados
│   ├── construir_base_datos.R      catálogo xlsx/CSV → SQLite
│   ├── escenario_ejemplo.yml
│   └── batch_ejemplo.yml
├── api/                          servicio R/plumber
│   ├── plumber.R                   endpoint POST /simular
│   ├── agregar_salidas.R           estadísticos multianuales
│   ├── run.R                       entrypoint
│   └── Dockerfile
├── frontend/                     aplicación Next.js
│   └── Dockerfile
├── balance_hidrico.sqlite        catálogo + clima de la plataforma
├── docker-compose.yml            plataforma con imágenes publicadas
├── docker-compose.dev.yml        override: construir desde el código
├── .github/workflows/build.yml   CI/CD de imágenes
└── documentacion/                MANUAL_TECNICO, ARQUITECTURA y guías de uso
```

Archivos que **no** se versionan: `base_datos_balance_hidrico.xlsx`
(catálogo fuente), `salidas/` y `salidas_batch/` (resultados de corridas).

## 4. El paquete R

### 4.1 Contrato de datos entre pasos

Cada paso es una función con entradas y salidas explícitas:

```
calcular_fenologia(cultivo, cultivar, clima_estacion, fecha_siembra, parametros)
  -> list(
       hitos        = tibble 1 fila: siembra, emergencia, fin_kcb_inicial,
                      inicio_kcb_maximo, hito1, nombre_hito1, hito2, nombre_hito2,
                      inicio_periodo_critico, fin_periodo_critico, madurez_fisiologica
       serie_diaria = tibble: date, doy, tm, fp, ut_simple_acum
     )

calcular_profundidad_radicular(clima_estacion, fecha_emergencia, fecha_hito2,
                               tb_c, pr_s_e, pr, profundidad_maxima_suelo)
  -> tibble: date, profundidad_radical_m

calcular_curva_kcb(serie_ut_simple, ut_fkcbini, ut_ikcbmax, kcb_ini, kcb_max)
  -> tibble: date, kcb

calcular_balance_hidrico(clima_estacion, fecha_inicio,
                         serie_profundidad_radicular, serie_kcb, suelo,
                         rastrojo_clase, humedad_inicial_clase_m1,
                         humedad_inicial_clase_m2, constantes,
                         sandwich_seco_inicial = FALSE)
  -> list(serie_diaria = tibble de ~80 columnas)

calcular_salidas(clima_estacion, fecha_siembra, hitos, serie_diaria_balance)
  -> list(eventos_lluvia_10mm_14a_7d_siembra, estado_hidrico_siembra, confort_hidrico)
```

`hito1`/`hito2` son alias genéricos (el nombre real depende del cultivo:
ET/Z71 en trigo, R2/R2 en maíz, R1/R5 en soja), de modo que
`calcular_profundidad_radicular()` es **independiente del cultivo**: solo
necesita las fechas de emergencia y de hito 2.

`calcular_balance_hidrico()` trata las fechas anteriores al comienzo de las
series de raíz y Kcb (por ejemplo, antes de la emergencia) como
`profundidad_radical_m = 0` y `kcb = 0`: todavía no hay cultivo.

Columnas del clima (`clima_estacion`): `station_id`, `date`, `doy`, `tx`,
`tn`, `tm`, `pp`, `eto`. Una sola estación por llamada.

### 4.2 Estructuras de entrada

| Estructura | Se obtiene con | Contenido |
|---|---|---|
| Clima | `leer_clima_csv()` | tibble con las columnas anteriores; agrega `doy` y completa con `NA` las opcionales ausentes |
| Parámetros | `leer_parametros_yaml()` | lista con `estaciones` (latitud), `suelos` (horizontes y escalares) y `cultivos` (umbrales térmicos, raíz, Kcb, cultivares) |
| Constantes | `leer_constantes_yaml()` | clases de rastrojo y de humedad inicial; por defecto apunta al YAML empaquetado |

Accesores validados (`R/io.R`): `obtener_parametros_cultivo()`,
`obtener_latitud_estacion()`, `obtener_profundidad_maxima_suelo()`,
`obtener_suelo_balance_hidrico()` (arma `list(cn, kl, um, u, dr, horizontes)`),
`obtener_factor_rastrojo()` y `obtener_fraccion_humedad_inicial()`. Todos
siguen el mismo patrón: validar pertenencia en una lista con nombre y abortar
listando las opciones válidas.

### 4.3 Funciones exportadas

| Área | Funciones |
|---|---|
| Pasos del método | `calcular_fenologia()` (+ `_trigo`, `_maiz`, `_soja`), `calcular_profundidad_radicular()`, `calcular_curva_kcb()`, `calcular_balance_hidrico()`, `calcular_salidas()` (+ sus tres componentes) |
| Clima | `calcular_temperatura_media()`, `calcular_declinacion_solar()`, `calcular_fotoperiodo()`, `calcular_eto_hargreaves()`, `completar_gaps_clima()` |
| Entrada | `leer_clima_csv()`, `leer_parametros_yaml()`, `leer_constantes_yaml()` y los `obtener_*()` |

Las funciones auxiliares internas empiezan con punto (`.fecha_en_umbral()`,
`.escorrentia_infiltracion()`, etc.) y no se exportan.

### 4.4 Notas de implementación

- **Balance secuencial.** `calcular_balance_hidrico()` recorre los días con un
  bucle `for` (el estado de un día depende del anterior) y arma matrices de
  `n días × n horizontes` por magnitud. No es vectorizable entre días. El
  número de horizontes se deduce de los datos (`nrow(suelo$horizontes)`); no
  está fijo en 8.
- **Búsqueda de hitos.** `.fecha_en_umbral()` resuelve la primera fecha en que
  un acumulado monótono alcanza un umbral.
- **Tolerancias.** Los tests de referencia comparan con tolerancia `1e-9`, así
  que constantes literales de las fórmulas (como `0.01745` en el fotoperíodo)
  se conservan tal cual y no se reemplazan por equivalentes (`pi/180`).
- **Efecto de lado documentado.** `completar_gaps_clima()` llama a
  `set.seed(semilla)`, lo que modifica el estado global del generador
  aleatorio.

## 5. Scripts de corrida

Los scripts viven fuera del paquete (no se instalan con él) y se ejecutan con
`Rscript` desde la raíz del repositorio. Cargan el paquete con
`devtools::load_all()` si está disponible, o con `library(balancehidrico)`.

### 5.1 `scripts/lib_simular.R`

Lógica compartida por los scripts y la API (se carga con `source()`):

| Función | Responsabilidad |
|---|---|
| `simular_escenario()` | Núcleo puro: ejecuta los 5 pasos para un escenario ya resuelto y devuelve `hitos`, `serie_diaria`, `balance_diario` y `salidas_tabla`. Los errores se propagan; quien llama decide cómo manejarlos |
| `.recortar_clima_escenario()` | Recorta el clima a la ventana `[min(monitoreo, siembra − 14), madurez]` y falla si excede el rango disponible |
| `leer_inputs_comunes()` | Lee clima, parámetros y constantes de un escenario individual |
| `leer_condiciones_iniciales_xlsx()` | Lee el xlsx de un lote (6 hojas), rellena huecos de clima, calcula `ETo` y arma las mismas estructuras que `leer_*()` |
| `construir_grid_batch()` | Producto cartesiano de escenarios × años de siembra (fecha por día del año) |
| `construir_grid_escenario_individual()` | Grid de un escenario de la plataforma × todos los años del clima (fechas por día y mes) |
| `.resolver_anio_monitoreo()` | Decide en qué año calendario cae el monitoreo respecto de la siembra |
| `leer_clima_estacion_sqlite()` | Lee el clima de una estación de la SQLite con la forma que espera el motor |
| `.armar_suelos()`, `.armar_cultivos()` | Convierten tablas planas (xlsx o SQLite) en la lista anidada de parámetros |

### 5.2 `scripts/simular.R`

Un escenario → cuatro CSV. Lee un YAML de configuración
(`escenario_ejemplo.yml`), resuelve rutas relativas a la ubicación del propio
YAML, llama a `simular_escenario()` y escribe `*_hitos.csv`,
`*_serie_diaria.csv`, `*_balance_diario.csv` y `*_salidas.csv`.

### 5.3 `scripts/simular_batch.R`

Un lote → cuatro CSV acumulados más `*_errores.csv`. Lee un YAML de
configuración (`batch_ejemplo.yml`) y un xlsx de condiciones iniciales,
construye el grid y simula cada combinación dentro de un `tryCatch`: **una
combinación que falla se registra con su mensaje de error y el lote continúa**.
Cada fila de salida lleva columnas identificatorias (`id_simulacion`,
`escenario`, `cultivo`, `cultivar`, `estacion`, `suelo`, `siembra`, …).

### 5.4 `scripts/construir_base_datos.R`

Construye `balance_hidrico.sqlite` a partir de un xlsx de catálogo (hojas
`estaciones`, `clima`, `suelos`, `horizontes`, `cultivares`) y, opcionalmente,
de un CSV de clima aparte (`--clima`). Para cada estación completa los huecos
(`completar_gaps_clima()`, semilla `--semilla`, por defecto 1234) y calcula
`eto` (`calcular_eto_hargreaves()`) **una sola vez**, de modo que la API no
recalcule nada en cada consulta.

## 6. Base de datos de la plataforma

`balance_hidrico.sqlite` es la única fuente de datos de la plataforma. Esquema:

```
estaciones (omm_id PK, nombre, longitud, latitud, localidad)
clima      (omm_id, fecha, tmax, tmin, tmed, prcp, eto)   PK (omm_id, fecha), FK estaciones
suelos     (suelo PK, u, dr, cn, kl, um, localidad, tipo_suelo, serie_suelo)
horizontes (suelo, pfh_m, horiz, pmp, cc, sat)            PK (suelo, pfh_m), FK suelos
cultivares (id PK, cultivo, cultivar, parametro, valor, unidad)
```

Decisiones:

- El **clima ya viene completo** (huecos rellenados, `eto` calculada). La API
  y el frontend lo consumen en modo solo lectura.
- `cultivares` está en **formato largo** (una fila por parámetro); `.armar_cultivos()`
  lo convierte en la lista anidada que consume el motor.
- La SQLite se **versiona** en el repositorio y se copia dentro de ambas
  imágenes Docker en el build. Para cambiar el catálogo o el clima hay que
  regenerarla y volver a publicar las imágenes.

## 7. API (R/plumber)

Un único endpoint: **`POST /simular`**. Corre un escenario contra todos los
años de clima disponibles de la estación y devuelve las salidas agregadas y el
detalle por año.

**Entrada (JSON):**

```json
{
  "estacion": 87548,
  "suelo": "IN65JUNI01",
  "cultivo": "trigo",
  "cultivar": "intermedio-largo",
  "siembra":   { "dia": 1, "mes": 6 },
  "monitoreo": { "dia": 1, "mes": 3 },
  "cantidad_rastrojo": "Moderada",
  "au_m1": "Hu",
  "au_m2": "Hu",
  "sandwich_seco": "No"
}
```

`cantidad_rastrojo`, `au_m1` y `au_m2` usan los **códigos internos** de
`constantes.yml` (`Baja`/`Moderada`/`Muy_Alta`; `Se`/`mS`/`mH`/`Hu`), no las
etiquetas que ve el usuario.

**Salida (JSON):** `anios_simulados`, `anios_con_error`, `salidas`
(estadísticos de cada variable, agrupadas en `siembra` y `cultivo`) y `anios`
(una fila por año con las salidas sin agregar).

**Códigos de estado:** 200 correcto; 400 faltan campos obligatorios; 422 el
escenario no pudo simularse (entrada inexistente, ningún año simulable).

**Flujo interno:** valida el cuerpo → abre la SQLite en solo lectura → lee
clima, estación, suelo, horizontes y cultivares → arma la lista de parámetros
→ construye el grid de años → para cada año recorta el clima y llama a
`simular_escenario()` dentro de un `tryCatch` (los años fallidos se cuentan,
no abortan) → agrega con `agregar_salidas_multianio()`.

**Entrypoint (`api/run.R`).** Carga `library(balancehidrico)`, `plumber`, `DBI`
y `RSQLite`, hace `source()` de `scripts/lib_simular.R` y
`api/agregar_salidas.R`, y resuelve la ruta de la SQLite a absoluta **antes**
de `plumber::pr()`, porque plumber cambia el directorio de trabajo al parsear
`plumber.R`. Por eso las dependencias no se cargan dentro de `plumber.R`.
Variables de entorno: `BALANCE_HIDRICO_SQLITE` (ruta de la base) y `PORT`
(por defecto 8000).

**Agregación (`api/agregar_salidas.R`).** Media, P20, P50, P80, desvío e IQR
por variable, con `quantile(type = 7)`. El sándwich seco (categórico) no se
agrega.

## 8. Frontend (Next.js)

Aplicación Next.js (TypeScript, Tailwind) con rutas de servidor:

| Componente | Rol |
|---|---|
| `src/app/page.tsx` | Página principal; en build lee localidades y cultivos de la SQLite |
| `src/components/FormularioEscenario.tsx` | Formulario con cascadas localidad → suelos y cultivo → cultivares |
| `src/components/TablaResultado.tsx` | Tablas de estadísticos (Siembra, Cultivo) y detalle por año |
| `src/lib/db.ts` | Acceso de solo lectura a la SQLite (`better-sqlite3`) |
| `src/lib/equivalencias.ts` | Etiquetas visibles ↔ códigos internos (rastrojo, humedad, sándwich seco, meses) |
| `src/app/api/suelos`, `api/cultivares` | Rutas que sirven el catálogo desde la SQLite |
| `src/app/api/simular/route.ts` | Proxy servidor → API R (`POST {API_URL}/simular`) |

Decisiones:

- El **catálogo** (localidades, suelos, cultivares) se lee **directamente de la
  SQLite**, no de la API. La API se usa solo para simular.
- El navegador **nunca** habla con la API R: llama a `/api/simular` del propio
  frontend, que reenvía el pedido con la URL interna (`API_URL`). Por eso la
  API no necesita publicarse al exterior.
- Las equivalencias etiqueta/código están fijas en el código del frontend
  (la etiqueta "Muy Alta" corresponde al código `Muy_Alta`).
- La estación queda implícita: cada localidad tiene una estación.

## 9. Despliegue: Docker y CI/CD

### 9.1 Imágenes

| Imagen | Base | Contenido |
|---|---|---|
| `balance-hidrico-api` | `rocker/r-ver:4.3.0` | paquete `balancehidrico` instalado formalmente (`R CMD INSTALL`), `plumber`, `DBI`, `RSQLite`, `scripts/lib_simular.R`, `api/` y la SQLite |
| `balance-hidrico-frontend` | `node:22-bookworm-slim` (multi-etapa) | build standalone de Next.js y la SQLite |

Ambos Dockerfile se construyen con el **contexto en la raíz del repositorio**
(no en `api/` ni `frontend/`) para poder copiar `DESCRIPTION`, `R/`,
`scripts/` y `balance_hidrico.sqlite`.

Detalles que importan al mantener las imágenes:

- La API instala el paquete con `R CMD INSTALL`, no con `devtools::load_all()`.
  Cada paso de instalación verifica con `stopifnot(requireNamespace(...))`
  porque `install.packages()` no propaga el fallo de un paquete individual
  como error de shell. La dependencia de sistema `libsodium-dev` es necesaria
  (`plumber` depende de `sodium`).
- El frontend usa Node 22 por `better-sqlite3`, y una base Debian (no Alpine)
  para evitar problemas glibc/musl con el addon nativo. La SQLite se necesita
  **durante el build** porque la página principal se prerenderiza.

### 9.2 Orquestación con Docker Compose

`docker-compose.yml` levanta ambos servicios con las imágenes publicadas:

- `api`: puerto 8000 **solo expuesto a la red interna** de Compose (no se
  publica en el host).
- `frontend`: publica el puerto 3000 y recibe `API_URL=http://api:8000`;
  `depends_on: api`.
- Ambos con `restart: unless-stopped`.

`docker-compose.dev.yml` es un *override* que agrega `build:` a cada servicio
para construir desde el código fuente en vez de usar las imágenes publicadas:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build
```

### 9.3 CI/CD

`.github/workflows/build.yml` se dispara en cada *push* a `main` (incluido el
*merge* de un pull request). Construye en paralelo (matriz) las dos imágenes y
las publica en GitHub Container Registry con tres etiquetas:

```
ghcr.io/crc-sas/balance-hidrico-api:{latest, <sha-del-commit>, main}
ghcr.io/crc-sas/balance-hidrico-frontend:{latest, <sha-del-commit>, main}
```

Se autentica con el `GITHUB_TOKEN` automático (sin *secrets* manuales) y usa
caché de build por servicio. Los cambios se desarrollan en una rama `dev` y
llegan a `main` por pull request.

## 10. Estrategia de pruebas

Pruebas con testthat en `tests/testthat/` (un archivo por módulo):

| Archivo | Cubre |
|---|---|
| `test-fenologia.R` | Paso 1, trigo contra valores de referencia; maíz y soja con climas sintéticos de resultado calculable a mano |
| `test-profundizacion_radicular.R` | Paso 2 |
| `test-curva_kcb.R` | Paso 3 |
| `test-balance_hidrico.R` | Paso 4, contra un fixture de referencia de 428 días con comparación de las ~78 columnas de salida en fechas de control (`fixtures/`) |
| `test-salidas.R` | Paso 5, con fixtures sintéticos |
| `test-utils_clima.R` | Tm, declinación, fotoperíodo y Hargreaves-Samani |
| `test-imputacion_clima.R` | Relleno de huecos, incluido un chequeo numérico independiente del puente AR(1) |
| `test-io.R` | Lectura y validación de CSV/YAML |

Criterios:

- **Valores de referencia reales** con tolerancia `1e-9` para trigo (Pasos 1–4);
  la prueba del balance usa profundidad radicular y Kcb **de referencia** como
  entrada (no la salida de los Pasos 2–3) para desacoplar la validación del
  Paso 4 de la corrección de los pasos anteriores.
- **Fixtures sintéticos** de resultado calculable a mano para maíz, soja y
  Paso 5.
- **Propiedades** del relleno de huecos: no deja `NA` internos, nunca genera
  `Tn > Tx` ni `Pp < 0`, es reproducible con la misma semilla.

Ejecución:

```r
devtools::test()    # todas las pruebas
devtools::check()   # R CMD check completo
```

## 11. Extender el sistema

**Agregar un cultivar.** Es solo datos: nuevas filas en la hoja `cultivares`
(o en el YAML de parámetros) con los mismos nombres de parámetro que los
cultivares existentes del cultivo. Para la plataforma, regenerar la SQLite
(`construir_base_datos.R`) y republicar las imágenes.

**Agregar un suelo.** Nuevas filas en `suelos` y `horizontes` (con la
localidad a la que pertenece) y regenerar la SQLite.

**Agregar una estación o ampliar el clima.** Nueva fila en `estaciones` y
datos de clima (hoja `clima` o `--clima <csv>`); regenerar la SQLite.

**Agregar un cultivo.** Requiere código: una función
`calcular_fenologia_<cultivo>()` en `R/fenologia.R`, su registro en el
`switch` de `calcular_fenologia()` y en el `match.arg` de cultivos, sus
parámetros en el catálogo y sus pruebas. El resto de los pasos es independiente
del cultivo.

**Cambiar una fórmula de un paso.** Se modifica la función auxiliar interna
correspondiente (por ejemplo, `.evaporacion_real()` en `R/balance_hidrico.R`) y
se actualizan sus pruebas y la sección correspondiente del manual técnico.

**Agregar una salida.** Una función pura nueva en `R/salidas.R` y su inclusión
en `calcular_salidas()`; luego, en `simular_escenario()` (columnas de
`salidas_tabla`), `api/agregar_salidas.R` (variable agregada) y
`frontend/src/lib/equivalencias.ts` (etiqueta visible).
