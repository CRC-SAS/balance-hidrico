# balancehidrico

Paquete R que implementa el método propio de CRC-SAS (no DSSAT) de:

1. **Fenología** de trigo, maíz y soja, por acumulación de unidades térmicas (UT).
2. **Profundización radicular** potencial.
3. **Curva de Kcb** (coeficiente basal de cultivo, FAO-56).
4. **Balance hídrico diario** del suelo (escorrentía, infiltración,
   transpiración, evaporación, drenaje, por horizonte).
5. **Salidas**: eventos de lluvia pre-siembra, estado hídrico a la siembra
   y confort hídrico durante el período crítico.

para la herramienta de balance hídrico de cultivos de CRC-SAS.

> **Estado:** los 5 pasos del método están completos e implementados,
> validados contra la planilla de referencia de CRC-SAS. Ver
> `documentacion/MANUAL_TECNICO.md` para el detalle completo de fórmulas,
> decisiones de diseño e historia del proyecto, y `documentacion/FUTURE_WORK.md`
> para lo que sigue pendiente (no bloqueante).

## Contenido

- [Que hace y que no hace](#que-hace-y-que-no-hace)
- [Instalacion](#instalacion)
- [Configuracion (inputs)](#configuracion-inputs)
- [Ejemplo de uso](#ejemplo-de-uso)
- [Script de corrida](#script-de-corrida)
- [Tests](#tests)
- [Documentacion adicional](#documentacion-adicional)

## Que hace y que no hace

El paquete expone funciones puras (sin efectos de lado, testeables de forma
aislada) para los 5 pasos del método, más utilidades compartidas de lectura
de datos:

| Paso | Función principal | Archivo |
|---|---|---|
| 1. Fenología | `calcular_fenologia()` (dispatcher) + `calcular_fenologia_trigo()` / `_maiz()` / `_soja()` | `R/fenologia.R` |
| 2. Profundización radicular | `calcular_profundidad_radicular()` | `R/profundizacion_radicular.R` |
| 3. Curva de Kcb | `calcular_curva_kcb()` | `R/curva_kcb.R` |
| 4. Balance hídrico diario | `calcular_balance_hidrico()` | `R/balance_hidrico.R` |
| 5. Salidas | `calcular_salidas()` (+ `calcular_eventos_lluvia_10mm_14a_7d_siembra()`, `calcular_estado_hidrico_siembra()`, `calcular_confort_hidrico()`) | `R/salidas.R` |

Utilidades compartidas de lectura de datos y cálculo climático:

| Utilidad | Función | Archivo |
|---|---|---|
| Leer clima diario desde CSV | `leer_clima_csv()` | `R/io.R` |
| Leer parámetros de escenario desde YAML | `leer_parametros_yaml()`, `obtener_parametros_cultivo()`, `obtener_latitud_estacion()`, `obtener_profundidad_maxima_suelo()`, `obtener_suelo_balance_hidrico()` | `R/io.R` |
| Leer constantes categóricas fijas desde YAML | `leer_constantes_yaml()`, `obtener_factor_rastrojo()`, `obtener_fraccion_humedad_inicial()` | `R/io.R` |
| Temperatura media / fotoperíodo | `calcular_temperatura_media()`, `calcular_declinacion_solar()`, `calcular_fotoperiodo()` | `R/utils_clima.R` |

**No incluye** (todavía, ver `documentacion/FUTURE_WORK.md` para el detalle):

- Uso de ENSO en el cálculo del balance en sí (es un dato de entrada
  descripto por CRC-SAS, pero sin criterio de uso definido todavía).
- Un script de orquestación de simulaciones que corra un **conjunto** de
  estaciones/suelos/cultivos/cultivares y agregue resultados (climatología,
  reporte por campaña). Lo que sí existe es `scripts/simular.R`, que corre
  **un** escenario puntual y exporta CSV (ver sección
  [Script de corrida](#script-de-corrida)).
- Fixtures cruzados contra la planilla de referencia para maíz y soja
  (Pasos 1 y 3) — solo trigo tiene ese fixture; maíz/soja usan climas sintéticos.
- El catálogo completo de suelos de CRC-SAS (600+ filas) — solo hay 2
  suelos de ejemplo cargados en `inst/extdata/parametros_ejemplo.yml`.
- Cualquier lógica DSSAT (CUL/ECO, CERES, CROPGRO). Este paquete es un
  método alternativo, desarrollado en paralelo; no depende del paquete
  `DSSAT` de R ni de archivos `.CUL`/`.ECO`/`.SOL`, aunque el diseño de la
  fenología (Paso 1) sigue el mismo esquema conceptual que los modelos
  CERES/CROPGRO de DSSAT (ver `documentacion/PAPER.md`).

## Instalacion

Requiere R >= 4.1 (desarrollado y probado con R 4.3.0).

```r
# Paquetes de los que depende balancehidrico
install.packages(c("dplyr", "tibble", "lubridate", "readr", "yaml", "rlang", "glue"))

# Para desarrollo/tests
install.packages(c("devtools", "roxygen2", "testthat"))
```

### Para desarrollo (recomendado)

Clonar el repo y cargar el paquete sin instalarlo:

```r
devtools::load_all(".")
```

### Para instalarlo como paquete

```r
devtools::install(".")
# o, una vez publicado el repo:
# remotes::install_github("CRC-SAS/balance-hidrico")
```

## Configuracion (inputs)

El paquete no asume ninguna fuente de datos particular (no lee de una base
de datos ni de un servicio): recibe un **CSV de clima**, un **YAML de
parámetros de escenario** y un **YAML de constantes fijas**, todos con
ejemplos incluidos en `inst/extdata/`.

### Clima (CSV)

Una fila por día y estación. Columnas requeridas: `station_id`, `date`
(`YYYY-MM-DD`), `tx` (temperatura máxima, °C), `tn` (temperatura mínima,
°C). Columnas opcionales: `tm` (temperatura media provista por la base
climática; si falta se recalcula como `(tx+tn)/2`), `pp` (precipitación,
mm), `eto` (evapotranspiración de referencia diaria, mm — dato de entrada,
no se calcula; la usa el Paso 4).

```csv
station_id,date,tx,tn,tm,pp,eto
87480,1983-01-01,35.2,21.1,27.8,1.4,6.5
87480,1983-01-02,28.4,24.2,27,0,2.2
```

Se lee con `leer_clima_csv(path)`, que devuelve un tibble y agrega la
columna `doy` (día del año).

### Parametros de escenario (YAML)

Contiene `estaciones` (latitud), `suelos` (profundidad máxima para Paso 2,
y opcionalmente los horizontes + escalares completos para Paso 4 — ver
`obtener_suelo_balance_hidrico()`) y `cultivos` (coeficientes fenológicos,
de raíz y de Kcb por cultivo y cultivar). Ver
`inst/extdata/parametros_ejemplo.yml`, comentado campo por campo, y
`documentacion/MANUAL_TECNICO.md` para el significado agronómico de cada
parámetro.

### Constantes fijas (YAML)

`inst/extdata/constantes.yml` tiene las clases categóricas de rastrojo y
humedad inicial que usa el Paso 4 (no varían entre escenarios, por eso
están separadas del YAML de parámetros). Se lee con
`leer_constantes_yaml()`, que por defecto apunta al archivo empaquetado —
es el único caso del paquete con una ruta default.

```r
parametros <- leer_parametros_yaml("inst/extdata/parametros_ejemplo.yml")
p <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")
constantes <- leer_constantes_yaml()  # usa el YAML empaquetado
```

## Ejemplo de uso

Ejemplo end-to-end con los datos de ejemplo incluidos en el paquete
(estación 87480, trigo, cultivar intermedio-largo, siembra 1983-05-30,
suelo `IN64MARC02`):

```r
devtools::load_all(".")  # o library(balancehidrico)

# 1) Leer inputs
clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
constantes <- leer_constantes_yaml()

# 2) Paso 1: Fenologia
fenologia <- calcular_fenologia(
  cultivo = "trigo",
  cultivar = "intermedio-largo",
  clima_estacion = clima,
  fecha_siembra = "1983-05-30",
  parametros = parametros
)
fenologia$hitos       # fechas de siembra, emergencia, fin Kcb inicial, ...
fenologia$serie_diaria # serie diaria de UT acumuladas (sin fotoperiodo)

# 3) Paso 2: Profundizacion radicular (potencial)
p_cultivar <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")
profundidad_maxima_suelo <- obtener_profundidad_maxima_suelo(parametros, "IN64MARC02")

raices <- calcular_profundidad_radicular(
  clima_estacion = clima,
  fecha_emergencia = fenologia$hitos$emergencia,
  fecha_hito2 = fenologia$hitos$hito2,
  tb_c = p_cultivar$raiz$tb_c,
  pr_s_e = p_cultivar$raiz$pr_s_e,
  pr = p_cultivar$raiz$pr,
  profundidad_maxima_suelo = profundidad_maxima_suelo
)

# 4) Paso 3: Curva de Kcb
kcb <- calcular_curva_kcb(
  serie_ut_simple = fenologia$serie_diaria,
  ut_fkcbini = p_cultivar$ut_e_fkcbini,
  ut_ikcbmax = p_cultivar$ut_e_ikcbmax,
  kcb_ini = p_cultivar$kcb$kcb_ini,
  kcb_max = p_cultivar$kcb$kcb_max
)

# 5) Paso 4: Balance hidrico diario
suelo <- obtener_suelo_balance_hidrico(parametros, "IN64MARC02")

balance <- calcular_balance_hidrico(
  clima_estacion = clima,
  fecha_inicio = "1983-03-01",
  serie_profundidad_radicular = raices,
  serie_kcb = kcb,
  suelo = suelo,
  rastrojo_clase = "Moderada",
  humedad_inicial_clase_m1 = "Hu",
  humedad_inicial_clase_m2 = "Hu",
  constantes = constantes
)
balance$serie_diaria  # ~78 columnas: agua por horizonte, escorrentia, transpiracion, evaporacion, drenaje...

# 6) Paso 5: Salidas
salidas <- calcular_salidas(
  clima_estacion = clima,
  fecha_siembra = "1983-05-30",
  hitos = fenologia$hitos,
  serie_diaria_balance = balance$serie_diaria
)
salidas$eventos_lluvia_10mm_14a_7d_siembra  # entero
salidas$estado_hidrico_siembra      # tibble 1 fila: au_pct_m1, au_pct_m2, au_pct_total (0-100), sandwich_seco
salidas$confort_hidrico             # numeric, porcentaje (0-100)
```

## Script de corrida

`scripts/simular.R` corre los 5 pasos para un escenario puntual y escribe
cuatro CSV (`<prefix>_hitos.csv`, `<prefix>_serie_diaria.csv`,
`<prefix>_balance_diario.csv`, `<prefix>_salidas.csv`) pensados para que el
experto de dominio de CRC-SAS los compare contra la planilla de referencia. Se
ejecuta desde la raíz del repo, pasándole la ruta a un **YAML de
configuración de escenario**:

```bash
Rscript scripts/simular.R scripts/escenario_ejemplo.yml
```

El YAML de configuración (ver `scripts/escenario_ejemplo.yml`) tiene estas
claves:

```yaml
clima: ../inst/extdata/clima_ejemplo.csv            # CSV de clima
parametros: ../inst/extdata/parametros_ejemplo.yml  # YAML de parametros de escenario
# constantes: opcional, default usa el YAML empaquetado (rastrojo/humedad inicial)
escenario:
  cultivo: trigo
  cultivar: intermedio-largo
  estacion: "87480"
  suelo: IN64MARC02
  siembra: "1983-05-30"
  fecha_inicio_balance: "1983-03-01"   # primer dia simulado de Paso 4
  rastrojo_clase: Moderada
  humedad_inicial_clase_m1: Hu
  humedad_inicial_clase_m2: Hu
  # sandwich_seco_inicial: opcional, default false
salida:
  outdir: salidas       # default "salidas"
  # prefix: opcional; default "<cultivo>_<estacion>_<siembra>"
```

Las rutas de `clima`, `parametros` y `constantes` son relativas a la
ubicación del propio YAML (no al directorio desde donde se corre el
script), así que un mismo archivo de configuración funciona sin importar
desde dónde se invoque. Para correr otro escenario, se copia
`scripts/escenario_ejemplo.yml` y se edita — no hace falta tocar
`simular.R`.

Las salidas se escriben por defecto en `salidas/` (ignorado por git).

## Script de corrida batch

`scripts/simular_batch.R` corre los 5 pasos para **múltiples**
combinaciones de escenario a la vez (una estación fija, varios
suelos/cultivos/cultivares/condiciones iniciales x varios años de
siembra) y escribe los mismos cuatro CSV pero **acumulados** (una fila,
o bloque de filas, por simulación, con columnas identificatorias al
principio: `id_simulacion`, `escenario`, `cultivo`, `cultivar`,
`estacion`, `suelo`, `siembra`, `fecha_inicio_balance`,
`rastrojo_clase`, `humedad_inicial_clase_m1/m2`,
`sandwich_seco_inicial`), más un quinto CSV (`<prefix>_errores.csv`) con
las combinaciones que fallaron y su mensaje de error — el batch no
aborta si una combinación falla, la loggea y sigue con las demás.

```bash
Rscript scripts/simular_batch.R scripts/batch_ejemplo.yml
```

El YAML de configuración (ver `scripts/batch_ejemplo.yml`) tiene estas
claves:

```yaml
condiciones_iniciales: ../condiciones_iniciales.xlsx  # xlsx de 6 hojas (no commiteado, dato real de CRC-SAS)
anios:
  desde: 1991
  hasta: 2025
offset_inicio_balance_dias: 90  # fecha_inicio_balance = siembra - N dias, fijo para todo el batch
semilla_imputacion: 1234  # opcional; default 1234 -- ver completar_gaps_clima()
salida:
  outdir: salidas_batch   # default "salidas_batch"
  # prefix: opcional; default "batch"
```

El xlsx de `condiciones_iniciales` (6 hojas: `estaciones`, `clima`,
`suelos`, `horizontes`, `cultivares`, `escenarios`) reemplaza a
`clima`/`parametros` del escenario puntual — `scripts/lib_simular.R`
arma en memoria la misma estructura que devolverían
`leer_clima_csv()`/`leer_parametros_yaml()` a partir de esas hojas (sin
generar un YAML intermedio en disco). El clima pasa primero por
`completar_gaps_clima()` (rellena días puntuales sin dato real en la
estación, ver `R/imputacion_clima.R`) y después por
`calcular_eto_hargreaves()` (cuando la hoja `clima` no trae `ETo`). El
grid del batch es el producto cartesiano de las filas de la hoja
`escenarios` (cada una ya fija suelo + cultivo/cultivar + condición
inicial) por los años del rango configurado (cada año deriva una fecha
de siembra distinta a partir del día-del-año de cada fila).

Alcance actual: una sola estación por batch (multi-estación no está
soportado), y el catálogo de suelos depende enteramente de lo que traiga
el xlsx (no hay catálogo completo de CRC-SAS cargado — ver
`documentacion/FUTURE_WORK.md`).

## Tests

```r
devtools::test()   # corre tests/testthat/*.R
devtools::check()  # R CMD check completo
```

Los tests de trigo (Pasos 1-4) comparan los resultados contra valores
**reales cacheados** en la planilla de referencia de CRC-SAS (no solo
contra las fórmulas), con tolerancia `1e-9` — ver
`tests/testthat/fixtures/` para el fixture de 428 días del Paso 4. Los de
maíz y soja (Pasos 1 y 3) usan climas sintéticos con resultado calculable
a mano (ver `documentacion/FUTURE_WORK.md` para el porqué de esta
limitación). Los de Paso 5 usan fixtures sintéticos (no hay valores de
referencia cacheados para esas 3 salidas).

## Documentacion adicional

- **`documentacion/MANUAL_TECNICO.md`** — documento central: cómo está
  implementado cada proceso (fórmulas exactas, contrato de datos), qué
  decisiones de diseño se tomaron y por qué, y la historia completa del
  proyecto (incluida la validación con el experto de dominio de CRC-SAS).
  Autocontenido: no hace falta ninguna fuente externa para entenderlo.
- **`documentacion/FUTURE_WORK.md`** — lo que sigue pendiente (no
  bloqueante): uso de ENSO en el cálculo, límite de días para ciclos
  largos, script de orquestación batch, fixtures cruzados de maíz/soja,
  catálogo completo de suelos.
- **`documentacion/PAPER.md`** — reporte estilo paper sobre el método
  agronómico-hidrológico implementado, con citas bibliográficas.
