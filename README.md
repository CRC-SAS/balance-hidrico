# balancehidrico

Paquete R que implementa el metodo propio de CRC-SAS (no DSSAT) de:

1. **Fenologia** de trigo, maiz y soja, por acumulacion de unidades termicas (UT).
2. **Profundizacion radicular** potencial.
3. **Curva de Kcb** (coeficiente basal de cultivo, FAO-56).

para la herramienta de balance hidrico de cultivos de CRC-SAS.

> **Estado:** Pasos 1-3 (Fenologia, Profundizacion radicular, Curva Kcb) estan
> completos e implementados. El **Paso 4 (Balance hidrico diario)** todavia
> no esta especificado y **no forma parte de este paquete**. Ver
> `documentacion/CONTINUIDAD_DESARROLLO.md` para el detalle completo del
> estado del proyecto y que falta.

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
aislada) para tres procesos independientes:

| Proceso | Funcion principal | Archivo |
|---|---|---|
| Fenologia | `calcular_fenologia()` (dispatcher) + `calcular_fenologia_trigo()` / `_maiz()` / `_soja()` | `R/fenologia.R` |
| Profundizacion radicular | `calcular_profundidad_radicular()` | `R/profundizacion_radicular.R` |
| Curva de Kcb | `calcular_curva_kcb()` | `R/curva_kcb.R` |

Ademas hay utilidades compartidas de lectura de datos y calculo climatico:

| Utilidad | Funcion | Archivo |
|---|---|---|
| Leer clima diario desde CSV | `leer_clima_csv()` | `R/io.R` |
| Leer parametros desde YAML | `leer_parametros_yaml()`, `obtener_parametros_cultivo()`, `obtener_latitud_estacion()`, `obtener_profundidad_maxima_suelo()` | `R/io.R` |
| Temperatura media / fotoperiodo | `calcular_temperatura_media()`, `calcular_declinacion_solar()`, `calcular_fotoperiodo()` | `R/utils_clima.R` |

**No incluye** (todavia):

- El Paso 4 (Balance hidrico diario: escorrentia, infiltracion, transpiracion,
  evaporacion, drenaje, confort hidrico). La especificacion de ese paso esta
  incompleta (ver `documentacion/CONTINUIDAD_DESARROLLO.md`, seccion "Paso 4").
- Un script de orquestacion de simulaciones que corra un **conjunto** de
  estaciones/suelos/cultivos/cultivares y agregue resultados (climatologia,
  reporte por campaña). Lo que si existe es `scripts/simular.R`, que corre
  **un** escenario puntual y exporta CSV (ver seccion
  [Script de corrida](#script-de-corrida)) — pensado para generar salidas que
  el experto de dominio pueda validar, no para correr en batch.
- Cualquier logica DSSAT (CUL/ECO, CERES, CROPGRO). Este paquete es un metodo
  alternativo, mas simple, desarrollado en paralelo; no depende del paquete
  `DSSAT` de R ni de archivos `.CUL`/`.ECO`/`.SOL`.

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

El paquete no asume ninguna fuente de datos particular (no lee de una base de
datos ni de un servicio): recibe un **CSV de clima** y un **YAML de
parametros**, ambos con ejemplos incluidos en `inst/extdata/`.

### Clima (CSV)

Una fila por dia y estacion. Columnas requeridas: `station_id`, `date`
(`YYYY-MM-DD`), `tx` (temperatura maxima, °C), `tn` (temperatura minima, °C).
Columnas opcionales: `tm` (temperatura media provista por la base climatica;
si falta o viene vacia se recalcula como `(tx+tn)/2`), `pp` (precipitacion,
mm; no la usan los Pasos 1-3, se incluye para el futuro Paso 4).

```csv
station_id,date,tx,tn,tm,pp
87480,1983-01-01,35.2,21.1,27.8,1.4
87480,1983-01-02,28.4,24.2,27,0
```

Se lee con `leer_clima_csv(path)`, que devuelve un tibble y agrega la columna
`doy` (dia del anio).

### Parametros (YAML)

Contiene tres secciones: `estaciones` (latitud, para calcular el
fotoperiodo), `suelos` (profundidad maxima, para topear la profundizacion
radicular) y `cultivos` (coeficientes fenologicos, de raiz y de Kcb por
cultivo y cultivar). Ver `inst/extdata/parametros_ejemplo.yml`, que esta
comentado campo por campo, y `documentacion/MANUAL_TECNICO.md` para el
significado agronomico de cada parametro.

Se lee con `leer_parametros_yaml(path)`. Para extraer los parametros de un
cultivo/cultivar puntual (con validacion: falla con un mensaje claro si el
cultivo/cultivar no existe, en vez de devolver `NULL`s silenciosos):

```r
parametros <- leer_parametros_yaml("inst/extdata/parametros_ejemplo.yml")
p <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")
```

## Ejemplo de uso

Ejemplo end-to-end con los datos de ejemplo incluidos en el paquete (estacion
87480, trigo, cultivar intermedio-largo, siembra 1983-05-30):

```r
devtools::load_all(".")  # o library(balancehidrico)

# 1) Leer inputs
clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))

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

# 3) Paso 2: Profundizacion radicular
p_cultivar <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")
profundidad_maxima_suelo <- obtener_profundidad_maxima_suelo(parametros, "RC00000001")

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
```

## Script de corrida

`scripts/simular.R` corre los Pasos 1-3 para un escenario puntual y escribe
dos CSV (`<prefix>_hitos.csv` y `<prefix>_serie_diaria.csv`) pensados para que
el experto de dominio de CRC-SAS los compare contra el xlsx de referencia.
Se ejecuta desde la raiz del repo, pasandole la ruta a un **YAML de
configuracion de escenario**:

```bash
Rscript scripts/simular.R scripts/escenario_ejemplo.yml
```

El YAML de configuracion (ver `scripts/escenario_ejemplo.yml`) tiene 4 claves:

```yaml
clima: ../inst/extdata/clima_ejemplo.csv        # CSV de clima
parametros: ../inst/extdata/parametros_ejemplo.yml  # YAML de parametros
escenario:
  cultivo: trigo
  cultivar: intermedio-largo
  estacion: "87480"
  suelo: RC00000001
  siembra: "1983-05-30"
salida:
  outdir: salidas       # default "salidas"
  # prefix: opcional; default "<cultivo>_<estacion>_<siembra>"
```

Las rutas de `clima` y `parametros` son relativas a la ubicacion del propio
YAML (no al directorio desde donde se corre el script), asi que un mismo
archivo de configuracion funciona sin importar desde donde se invoque.
Para correr otro escenario (otro cultivo/cultivar/estacion/suelo/fecha, o
un CSV de clima distinto), se copia `scripts/escenario_ejemplo.yml` y se
edita — no hace falta tocar `simular.R`.

Las salidas se escriben por defecto en `salidas/` (ignorado por git).

## Tests

```r
devtools::test()   # corre tests/testthat/*.R
devtools::check()  # R CMD check completo
```

Los tests de trigo comparan los resultados contra valores **reales
cacheados** en `documentacion/referencias/Calculos fenologia y balance
hidrico.xlsx` (no solo contra las formulas). Los de maiz y soja usan climas
sinteticos con resultado calculable a mano (ver
`documentacion/CONTINUIDAD_DESARROLLO.md` para el porque de esta limitacion).

## Documentacion adicional

- **`documentacion/MANUAL_TECNICO.md`** — como esta implementado cada
  proceso: formulas, contrato de datos, decisiones de diseno.
- **`documentacion/CONTINUIDAD_DESARROLLO.md`** — contexto completo del
  proyecto, historial de decisiones, que falta (Paso 4), y como retomar el
  desarrollo.
- **`documentacion/referencias/`** — documentos fuente del metodo (documento
  maestro, documento de trabajo y planilla de calculo de CRC-SAS, y las
  respuestas del experto del dominio a las dudas planteadas durante el
  analisis).
