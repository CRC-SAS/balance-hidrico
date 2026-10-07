# Guía de uso avanzado: correr el método desde R

Esta guía es para quien quiere **ejecutar el método de balance hídrico desde
R**: simular un escenario puntual, simular un lote de escenarios, o usar las
funciones del paquete por separado. Se asume conocimiento básico de R (abrir
una sesión, instalar paquetes, leer un `data.frame`); no hace falta conocer el
código del paquete.

Si preferís usar el método desde el navegador, sin programar, ver
[`GUIA_PLATAFORMA_WEB.md`](GUIA_PLATAFORMA_WEB.md). Para entender qué calcula
cada paso, ver el [`MANUAL_TECNICO.md`](MANUAL_TECNICO.md).

**Índice**

1. [Requisitos](#1-requisitos)
2. [Descargar el repositorio](#2-descargar-el-repositorio)
3. [Instalar el paquete](#3-instalar-el-paquete)
4. [Archivos de entrada](#4-archivos-de-entrada)
5. [Correr un escenario](#5-correr-un-escenario)
6. [Correr un lote de escenarios](#6-correr-un-lote-de-escenarios)
7. [Preparar el clima: ETo y relleno de huecos](#7-preparar-el-clima-eto-y-relleno-de-huecos)
8. [Regenerar la base de la plataforma web](#8-regenerar-la-base-de-la-plataforma-web)
9. [Verificar la instalación: tests](#9-verificar-la-instalación-tests)
10. [Errores frecuentes](#10-errores-frecuentes)

---

## 1. Requisitos

- **R versión 4.1 o superior** (desarrollado y probado con R 4.3.0).
  Descarga: <https://cran.r-project.org/>
- **Git** (opcional, para clonar el repositorio; también se puede descargar un
  ZIP): <https://git-scm.com/downloads>
- **Herramientas de compilación**, necesarias para instalar algunos paquetes de
  R:
  - Windows: [Rtools](https://cran.r-project.org/bin/windows/Rtools/) (versión
    que corresponda a tu versión de R).
  - Mac: *Xcode Command Line Tools* (se instalan con `xcode-select --install`
    en la Terminal).
  - Linux: `build-essential` y las librerías de desarrollo habituales
    (`libcurl4-openssl-dev`, `libssl-dev`, `libxml2-dev`).
- Opcional: **RStudio** (<https://posit.co/download/rstudio-desktop/>) como
  entorno de trabajo.

## 2. Descargar el repositorio

**Con Git** (recomendado: permite actualizar con `git pull`). En una terminal:

```bash
git clone https://github.com/CRC-SAS/balance-hidrico.git
cd balance-hidrico
```

**Sin Git:** entrá a <https://github.com/CRC-SAS/balance-hidrico>, hacé clic en
**Code → Download ZIP**, descomprimí el archivo y entrá a la carpeta resultante.

> **Toda esta guía asume que el directorio de trabajo es la carpeta raíz del
> repositorio** (la que contiene `DESCRIPTION`, `R/` y `scripts/`). Los scripts
> usan rutas relativas a esa carpeta. En una terminal, usá `cd`; en RStudio,
> abrí el proyecto o usá `setwd("ruta/a/balance-hidrico")`.

## 3. Instalar el paquete

### 3.1 Dependencias

En una sesión de R:

```r
# Dependencias del paquete
install.packages(c(
  "dplyr", "tibble", "lubridate", "readr", "yaml", "rlang", "glue",
  "stlplus", "MASS"
))

# Dependencias de los scripts de corrida (scripts/)
install.packages(c("tidyr", "readxl", "devtools"))

# Solo si vas a regenerar la base de la plataforma web (sección 8)
install.packages(c("DBI", "RSQLite"))
```

### 3.2 Opción A — cargar el paquete sin instalarlo (recomendada para trabajar)

```r
devtools::load_all(".")
```

Carga las funciones directamente desde `R/`. Los scripts de la carpeta
`scripts/` usan esta opción automáticamente si `devtools` está instalado.

### 3.3 Opción B — instalarlo como un paquete más

Desde la carpeta raíz del repositorio:

```r
devtools::install(".")
library(balancehidrico)
```

O, directamente desde GitHub, sin descargar el repositorio:

```r
install.packages("remotes")
remotes::install_github("CRC-SAS/balance-hidrico")
library(balancehidrico)
```

> Si instalás desde GitHub no tenés la carpeta `scripts/` ni los archivos de
> ejemplo de configuración; para correr los scripts hay que descargar el
> repositorio (sección 2). Los datos de ejemplo del paquete se encuentran con
> `system.file("extdata", package = "balancehidrico")`.

### 3.4 Comprobar la instalación

```r
library(balancehidrico)   # o devtools::load_all(".")
packageVersion("balancehidrico")
```

Si responde con un número de versión (por ejemplo `0.1.0`), el paquete está
listo.

## 4. Archivos de entrada

Un escenario individual necesita **tres archivos**; un lote necesita **uno**
(más el YAML de configuración del propio lote). Todos se pueden abrir con un
editor de texto (los YAML y el CSV) o con Excel (el CSV y el xlsx).

| Archivo | Se usa en | Qué contiene |
|---|---|---|
| CSV de **clima** | escenario | Clima diario de la estación |
| YAML de **parámetros** | escenario | Estaciones, suelos y cultivos/cultivares |
| YAML de **constantes** | escenario (opcional) | Clases de rastrojo y de humedad inicial |
| YAML de **escenario** | escenario | Qué simular y dónde guardar los resultados |
| xlsx de **condiciones iniciales** | lote | Estación, clima, suelos, cultivares y escenarios del lote |
| YAML de **lote** | lote | Rango de años y opciones del lote |

Hay un ejemplo completo de cada uno de los tres primeros en
`inst/extdata/` (`clima_ejemplo.csv`, `parametros_ejemplo.yml`,
`constantes.yml`) y de los YAML de configuración en `scripts/`
(`escenario_ejemplo.yml`, `batch_ejemplo.yml`).

### 4.1 CSV de clima

Una fila por día. Todas las filas de un archivo de escenario deben
corresponder a la misma estación.

| Columna | Obligatoria | Descripción |
|---|---|---|
| `station_id` | sí | Identificador de la estación (se compara como texto) |
| `date` | sí | Fecha, formato `AAAA-MM-DD` |
| `tx` | sí | Temperatura máxima (°C) |
| `tn` | sí | Temperatura mínima (°C) |
| `tm` | no | Temperatura media (°C). Si falta, se calcula como `(tx + tn) / 2` |
| `pp` | no\* | Precipitación diaria (mm) |
| `eto` | no\* | Evapotranspiración de referencia diaria (mm) |

\* `pp` y `eto` son opcionales para leer el archivo, pero **el balance hídrico
las necesita**. Si el CSV no trae `eto`, calculala antes (sección 7).

```csv
station_id,date,tx,tn,tm,pp,eto
87480,1983-01-01,35.2,21.1,27.8,1.4,6.5
87480,1983-01-02,28.4,24.2,27,0,2.2
```

### 4.2 YAML de parámetros

Tiene tres secciones. El archivo `inst/extdata/parametros_ejemplo.yml` está
comentado campo por campo.

```yaml
estaciones:
  "87480":                    # identificador de la estación, entre comillas
    latitud: -32.9036         # grados decimales; negativa = hemisferio sur

suelos:
  IN64MARC02:                 # identificador del suelo
    profundidad_maxima_m: 2.1 # tope de profundización radicular (m)
    cn: 77                    # Curva Número
    kl: 0.1                   # facilidad de extracción
    um: 0.5                   # umbral de reducción de kl
    u: 8                      # agua evaporable en fase 1 (mm)
    dr: 0.6                   # factor de drenaje
    horizontes:               # de arriba hacia abajo
      - {nombre: Ap,   pfh_m: 0.2, pmp: 0.15, cc: 0.30, sat: 0.52}
      - {nombre: B21t, pfh_m: 0.4, pmp: 0.19, cc: 0.33, sat: 0.47}
      # ... un renglón por horizonte
      #   pfh_m: profundidad inferior del horizonte (m)
      #   pmp, cc, sat: contenido volumétrico (fracción 0–1) en punto de
      #                 marchitez, capacidad de campo y saturación

cultivos:
  trigo:
    tb_a: 0                   # temperatura base (°C)
    ut_s_e: 150               # unidades térmicas siembra → emergencia
    # ... resto de los umbrales térmicos del cultivo
    raiz: {pr_s_e: 0.2, pr: 0.13, tb_c: 0}
    kcb:  {kcb_ini: 0.15, kcb_max: 1.10}
    cultivares:
      intermedio-largo:
        rcf: 0.85
```

- Los suelos que solo tienen `profundidad_maxima_m` sirven para los Pasos 1–3;
  para el balance hídrico (Paso 4) el suelo necesita además los escalares
  (`cn`, `kl`, `um`, `u`, `dr`) y los `horizontes`.
- Las temperaturas están en °C, las unidades térmicas (`ut_*`) en °C·día, los
  fotoperíodos umbral (`fpu_*`) en horas, `pr` en cm/°C, y las profundidades en
  metros.
- Los parámetros de cada cultivo y cultivar y su significado agronómico están
  en el [manual técnico](MANUAL_TECNICO.md), secciones 4 y 12.

### 4.3 YAML de constantes (opcional)

`inst/extdata/constantes.yml` define las clases con las que se describe el
rastrojo y la humedad inicial. **Normalmente no hay que tocarlo ni indicarlo**:
si no se especifica, se usa el archivo empaquetado.

```yaml
rastrojo:
  Baja: 1            # 0–20 % de cobertura
  Moderada: 0.8      # 30–50 %
  Muy_Alta: 0.5      # 80–100 %

humedad_inicial:
  Se: 0.10           # Seco
  mS: 0.35           # Moderadamente seco
  mH: 0.65           # Moderadamente húmedo
  Hu: 0.90           # Húmedo
```

Los **nombres** de clase (`Baja`, `Moderada`, `Muy_Alta`; `Se`, `mS`, `mH`,
`Hu`) son los que se usan en el escenario.

### 4.4 YAML de escenario

`scripts/escenario_ejemplo.yml`:

```yaml
clima: ../inst/extdata/clima_ejemplo.csv            # CSV de clima
parametros: ../inst/extdata/parametros_ejemplo.yml  # YAML de parámetros
# constantes: ../mis_constantes.yml                 # opcional

escenario:
  cultivo: trigo                  # trigo | maiz | soja
  cultivar: intermedio-largo      # debe existir en el YAML de parámetros
  estacion: "87480"               # entre comillas
  suelo: IN64MARC02               # debe tener datos completos de Paso 4
  siembra: "1983-05-30"           # AAAA-MM-DD
  fecha_inicio_balance: "1983-03-01"   # primer día simulado (monitoreo)
  rastrojo_clase: Moderada        # Baja | Moderada | Muy_Alta
  humedad_inicial_clase_m1: Hu    # Se | mS | mH | Hu  (primer metro)
  humedad_inicial_clase_m2: Hu    # Se | mS | mH | Hu  (segundo metro)
  # sandwich_seco_inicial: true   # opcional; por defecto false

salida:
  outdir: salidas                 # carpeta de resultados (por defecto "salidas")
  # prefix: mi_corrida            # opcional; por defecto <cultivo>_<estacion>_<siembra>
```

- Las rutas de `clima`, `parametros` y `constantes` son **relativas a la
  ubicación del propio YAML** (no a la carpeta desde donde se ejecuta), así que
  el mismo archivo funciona se corra desde donde se corra. También se aceptan
  rutas absolutas.
- Para simular otro escenario, copiá `escenario_ejemplo.yml`, cambiale el
  nombre y editá los valores: no hace falta tocar ningún script.
- `fecha_inicio_balance` puede ser anterior a la siembra (lo habitual) y debe
  tener clima disponible desde esa fecha hasta la madurez del cultivo.

### 4.5 xlsx de condiciones iniciales (lote)

Libro de Excel con **seis hojas**, con estos nombres exactos y estas columnas:

| Hoja | Columnas | Contenido |
|---|---|---|
| `estaciones` | `omm_id`, `nombre`, `longitud`, `latitud` | **Una sola fila**: el lote usa una única estación |
| `clima` | `omm_id`, `fecha`, `tmax`, `tmin`, `tmed`, `prcp` | Clima diario de la estación. Los huecos (`NA`) se rellenan automáticamente (sección 7) |
| `suelos` | `suelo`, `U`, `DR`, `CN`, `kl`, `Um` | Una fila por suelo |
| `horizontes` | `suelo`, `Horiz`, `PFH`, `PMP`, `CC`, `Sat` | Una fila por horizonte de cada suelo. `PFH` en metros |
| `cultivares` | `cultivo`, `cultivar`, `parametro`, `valor`, `unidad` | Parámetros en formato largo (ver abajo) |
| `escenarios` | `escenario`, `suelo`, `cultivo`, `cultivar`, `dda_S`, `cantidad_rastrojo`, `au_m1`, `au_m2`, `sandwich_seco` | Una fila por escenario del lote |

**Hoja `cultivares`.** Una fila por parámetro. Las filas con `cultivar` vacío
son parámetros comunes a todo el cultivo; las filas con `cultivar` completo son
específicas de cada cultivar. Nombres de parámetro (los mismos que en las tablas
del [manual técnico](MANUAL_TECNICO.md#12-tablas-de-parámetros)):

| Cultivo | Parámetros del cultivo (`cultivar` vacío) | Parámetros por cultivar |
|---|---|---|
| trigo | `Tb_a`, `UT_S-E`, `UT_E-fKcbIni`, `UT_E-iKcbMax`, `UT_E-ET`, `UT_ET-iPC`, `UT_ET-Z71`, `UT_ET-fPC`, `UT_fPC-MF`, `PR_S-E`, `PR`, `Tb_c`, `KcbIni`, `KcbMax` | `RCF` |
| maíz | `Tb_a`, `Tb_b`, `UT_S-E`, `UT_E-fKcbIni`, `UT_E-iKcbMax`, `PR_S-E`, `PR`, `Tb_c`, `KcbIni`, `KcbMax` | `UT_E-R2`, `UT_E-iPC`, `UT_E-fPC`, `UT_R2-MF` |
| soja | `Tb_a`, `Tb_b`, `To_a`, `UT_S-E`, `UT_E-fKcbIni`, `UT_E-iKcbMax`, `UT_E-R1`, `UT-R1-R5`, `UT_R1-iPC`, `UT_R5-fPC`, `UT-R5-MF`, `PR_S-E`, `PR`, `Tb_c`, `KcbIni`, `KcbMax` | `FpU_E-R1`, `FpU_R1-MF` |

**Hoja `escenarios`.**

| Columna | Valores |
|---|---|
| `escenario` | Número entero que identifica el escenario |
| `suelo` | Debe existir en la hoja `suelos` |
| `cultivo`, `cultivar` | Deben existir en la hoja `cultivares` |
| `dda_S` | **Día del año** de siembra (1–366). Ejemplos: 152 ≈ 1 de junio; 264 ≈ 21 de septiembre |
| `cantidad_rastrojo` | `Baja`, `Moderada` o `Muy_Alta` |
| `au_m1`, `au_m2` | `Se`, `mS`, `mH` o `Hu` |
| `sandwich_seco` | `Si` o `No` |

Cada fila de `escenarios` se simula una vez **por cada año** del rango
elegido (sección 6). Este archivo no está incluido en el repositorio: lo
provee CRC-SAS, o podés armarlo en Excel con las hojas y columnas anteriores.

### 4.6 YAML de lote

`scripts/batch_ejemplo.yml`:

```yaml
condiciones_iniciales: ../condiciones_iniciales.xlsx   # ruta al xlsx

anios:                       # años de siembra a simular
  desde: 1991
  hasta: 2025

offset_inicio_balance_dias: 90   # fecha de monitoreo = siembra − N días
semilla_imputacion: 1234         # opcional; semilla del relleno de huecos

salida:
  outdir: salidas_batch          # por defecto "salidas_batch"
  # prefix: mi_lote              # opcional; por defecto "batch"
```

- `offset_inicio_balance_dias` es obligatorio (no tiene valor por defecto) y
  vale **igual para todo el lote**: la fecha de inicio del balance de cada
  simulación es `siembra − N días`.
- Las rutas son relativas a la ubicación del YAML, igual que en el escenario.
- El rango de años debe estar cubierto por el clima del xlsx: cada simulación
  necesita clima desde unos días antes del monitoreo hasta la madurez del
  cultivo.

## 5. Correr un escenario

Hay dos formas: con el **script** (lo más simple: de un YAML a unos CSV) o
**paso a paso en R** (para explorar o integrar con tu propio código).

### 5.1 Con el script `scripts/simular.R`

Desde una terminal, en la carpeta raíz del repositorio:

```bash
Rscript scripts/simular.R scripts/escenario_ejemplo.yml
```

(En RStudio: pestaña **Terminal**. En Windows, `Rscript` debe estar en el
`PATH`; si no, usá la ruta completa, por ejemplo
`"C:\Program Files\R\R-4.3.0\bin\Rscript.exe"`.)

Para correr tu propio escenario: copiá y editá el YAML (sección 4.4) y
pasale la ruta del nuevo archivo.

El script imprime las rutas de los cuatro archivos que escribió en la carpeta
`outdir` (por defecto `salidas/`):

```
Escenario: cultivo=trigo cultivar=intermedio-largo estacion=87480 suelo=IN64MARC02 siembra=1983-05-30
Hitos escritos en:          salidas/trigo_87480_1983-05-30_hitos.csv
Serie diaria escrita en:    salidas/trigo_87480_1983-05-30_serie_diaria.csv
Balance diario escrito en:  salidas/trigo_87480_1983-05-30_balance_diario.csv
Salidas escritas en:        salidas/trigo_87480_1983-05-30_salidas.csv
```

**Qué contiene cada archivo**

| Archivo | Filas | Contenido |
|---|---|---|
| `*_hitos.csv` | 1 | Fechas de los hitos fenológicos: siembra, emergencia, fin Kcb inicial, inicio Kcb máximo, `hito1`/`hito2` (con `nombre_hito1`/`nombre_hito2`: ET/Z71 en trigo, R2/R2 en maíz, R1/R5 en soja), inicio y fin del período crítico y madurez fisiológica |
| `*_serie_diaria.csv` | 1 por día desde la emergencia | `date`, `doy`, `tm` (temperatura media), `fp` (fotoperíodo, h), `ut_simple_acum` (unidades térmicas acumuladas), `profundidad_radical_m` (raíz potencial, m) y `kcb` |
| `*_balance_diario.csv` | 1 por día desde `fecha_inicio_balance` | El balance del suelo, unas 80 columnas (ver abajo) |
| `*_salidas.csv` | 1 | Las salidas del método (ver abajo) |

**Columnas principales del balance diario.** Los sufijos `_1`, `_2`, … indican
el horizonte del suelo (1 = superficial).

| Columna | Descripción |
|---|---|
| `date` | Fecha |
| `esc`, `inf` | Escorrentía e infiltración (mm) |
| `demt`, `deme` | Demanda transpirativa y evaporativa (mm) |
| `trr`, `er` | Transpiración real y evaporación real (mm) |
| `drenaje_profundo` | Agua que sale por debajo del último horizonte (mm) |
| `ch_i` | Contenido hídrico inicial del día en el horizonte `i` (mm) |
| `chf_i` | Contenido hídrico del horizonte `i` al final del día, antes de truncar a saturación (mm) |
| `tr_i`, `at_i`, `at` | Transpiración y agua transpirable por horizonte, y total (mm) |
| `pre_m`, `lhpr` | Profundidad radical efectiva (m) y limitación hídrica de su avance (0–1) |
| `au_mm_m1`, `au_mm_m2`, `au_mm_total` | Agua útil (mm) en el primer metro, el segundo y todo el perfil |
| `au_pct_m1`, `au_pct_m2`, `au_pct_total` | Agua útil como **fracción** (0–1; puede superar 1 si el suelo está sobre capacidad de campo) |
| `sandwich_seco` | `Si`/`No`: capa seca en el horizonte 4 |

El significado de cada columna, con sus ecuaciones, está en la sección 7 del
[manual técnico](MANUAL_TECNICO.md#7-paso-4--balance-hídrico-diario).

**Columnas de `*_salidas.csv`**

| Columna | Descripción |
|---|---|
| `eventos_lluvia_10mm_14a_7d_siembra` | Días con lluvia ≥ 10 mm entre 14 días antes y 7 días después de la siembra |
| `au_pct_m1`, `au_pct_m2`, `au_pct_total` | Agua útil a la siembra, en **porcentaje** (0–100): primer metro, segundo metro, perfil completo |
| `sandwich_seco` | `Si`/`No` el día de la siembra |
| `confort_hidrico` | Porcentaje (0–100) de la demanda transpirativa cubierta durante el período crítico |

> Ojo con las unidades: en `*_balance_diario.csv` el agua útil es una fracción
> (0–1) y en `*_salidas.csv` es un porcentaje (0–100).

Para leer los resultados en R:

```r
salidas <- readr::read_csv("salidas/trigo_87480_1983-05-30_salidas.csv")
balance <- readr::read_csv("salidas/trigo_87480_1983-05-30_balance_diario.csv")

# Evolución del agua útil total (en %) a lo largo del balance
plot(balance$date, 100 * balance$au_pct_total, type = "l",
     xlab = "Fecha", ylab = "Agua útil total (%)")
```

### 5.2 Paso a paso en R

Útil para explorar resultados intermedios o armar tu propio flujo. Cada paso
es una función que recibe y devuelve tablas, sin leer ni escribir archivos.

```r
devtools::load_all(".")   # o library(balancehidrico)

# 1) Leer las entradas
clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
constantes <- leer_constantes_yaml()   # usa el YAML empaquetado

# 2) Paso 1 — Fenología
fenologia <- calcular_fenologia(
  cultivo = "trigo",
  cultivar = "intermedio-largo",
  clima_estacion = clima,
  fecha_siembra = "1983-05-30",
  parametros = parametros
)
fenologia$hitos          # fechas de los hitos (tabla de 1 fila)
fenologia$serie_diaria   # serie diaria de unidades térmicas acumuladas

# 3) Paso 2 — Profundización radicular potencial
p_cultivar <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")
raices <- calcular_profundidad_radicular(
  clima_estacion = clima,
  fecha_emergencia = fenologia$hitos$emergencia,
  fecha_hito2 = fenologia$hitos$hito2,
  tb_c = p_cultivar$raiz$tb_c,
  pr_s_e = p_cultivar$raiz$pr_s_e,
  pr = p_cultivar$raiz$pr,
  profundidad_maxima_suelo = obtener_profundidad_maxima_suelo(parametros, "IN64MARC02")
)

# 4) Paso 3 — Curva de Kcb
kcb <- calcular_curva_kcb(
  serie_ut_simple = fenologia$serie_diaria,
  ut_fkcbini = p_cultivar$ut_e_fkcbini,
  ut_ikcbmax = p_cultivar$ut_e_ikcbmax,
  kcb_ini = p_cultivar$kcb$kcb_ini,
  kcb_max = p_cultivar$kcb$kcb_max
)

# 5) Paso 4 — Balance hídrico diario
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
  # sandwich_seco_inicial = TRUE   # opcional
)
balance$serie_diaria     # el balance diario (~80 columnas)

# 6) Paso 5 — Salidas
salidas <- calcular_salidas(
  clima_estacion = clima,
  fecha_siembra = "1983-05-30",
  hitos = fenologia$hitos,
  serie_diaria_balance = balance$serie_diaria
)
salidas$eventos_lluvia_10mm_14a_7d_siembra   # número entero
salidas$estado_hidrico_siembra               # AU % (0–100) y sándwich seco
salidas$confort_hidrico                      # porcentaje (0–100)
```

Para ver la documentación de cualquier función: `?calcular_fenologia`,
`?calcular_balance_hidrico`, etc.

> **Cuidado con la ventana de clima.** `calcular_balance_hidrico()` recorre
> **todos** los días de `clima_estacion` desde `fecha_inicio`, sin detenerse en
> la madurez. Si le pasás décadas de clima, simulará décadas. Para un
> escenario puntual, pasale el clima ya recortado a `[fecha de inicio,
> madurez fisiológica]`, que es lo que hace el lote automáticamente.

## 6. Correr un lote de escenarios

El lote simula **cada escenario de la hoja `escenarios` para cada año** del
rango elegido. Ejemplo: 24 escenarios × 35 años = 840 simulaciones.

### 6.1 Preparación

1. Tené el xlsx de condiciones iniciales (sección 4.5).
2. Copiá `scripts/batch_ejemplo.yml`, y editá:
   - `condiciones_iniciales`: ruta al xlsx;
   - `anios`: rango de años de siembra;
   - `offset_inicio_balance_dias`: cuántos días antes de la siembra arranca el
     balance;
   - `salida.outdir` y, si querés, `salida.prefix`.

### 6.2 Ejecución

Desde una terminal, en la carpeta raíz del repositorio:

```bash
Rscript scripts/simular_batch.R scripts/batch_ejemplo.yml
```

El script:

1. Lee el xlsx, **rellena los huecos de clima** y calcula la `ETo` (sección 7).
2. Arma la grilla `escenarios × años` e informa cuántas simulaciones son.
3. Simula una por una, mostrando el avance:

   ```
   Grid del batch: 840 simulaciones (24 escenarios x 35 anios)
   [1/840] esc01_1991 OK
   [2/840] esc02_1991 OK
   ...
   ```

4. Escribe los resultados y un resumen final:
   `840/840 simulaciones OK`.

**Si una simulación falla, el lote continúa.** La combinación que falló se
registra con su mensaje de error en `*_errores.csv` y el script sigue con las
demás. Un lote de 840 simulaciones tarda del orden de minutos.

### 6.3 Resultados

Se escriben cinco archivos en la carpeta `outdir` (por defecto
`salidas_batch/`), con el prefijo `prefix` (por defecto `batch`):

| Archivo | Contenido |
|---|---|
| `batch_hitos.csv` | Una fila por simulación |
| `batch_serie_diaria.csv` | Serie diaria de cada simulación (apilada) |
| `batch_balance_diario.csv` | Balance diario de cada simulación (apilado) |
| `batch_salidas.csv` | Una fila por simulación con las salidas del método |
| `batch_errores.csv` | Una fila por simulación que falló, con `mensaje_error` (vacío si no hubo errores) |

Los cuatro primeros son los mismos archivos del escenario individual (sección
5.1), **acumulados**, con estas columnas identificatorias al comienzo de cada
fila:

| Columna | Descripción |
|---|---|
| `id_simulacion` | Identificador único, por ejemplo `esc01_1991` (escenario 1, año 1991) |
| `escenario` | Número del escenario (hoja `escenarios`) |
| `cultivo`, `cultivar`, `estacion`, `suelo` | Datos del escenario |
| `siembra`, `fecha_inicio_balance` | Fechas de esa simulación |
| `rastrojo_clase`, `humedad_inicial_clase_m1`, `humedad_inicial_clase_m2`, `sandwich_seco_inicial` | Condiciones iniciales |

Ejemplo de análisis de los resultados en R:

```r
library(dplyr)

salidas <- readr::read_csv("salidas_batch/batch_salidas.csv")
errores <- readr::read_csv("salidas_batch/batch_errores.csv")

nrow(errores)   # cuántas simulaciones fallaron

# Confort hídrico por escenario: media, mediana y percentil 20 entre años
salidas |>
  group_by(escenario, cultivo, cultivar, suelo) |>
  summarise(
    confort_medio = mean(confort_hidrico, na.rm = TRUE),
    confort_p50   = median(confort_hidrico, na.rm = TRUE),
    confort_p20   = quantile(confort_hidrico, 0.2, na.rm = TRUE),
    .groups = "drop"
  )
```

### 6.4 Alcance del lote

- **Una sola estación por lote** (la hoja `estaciones` debe tener una fila).
- Todos los escenarios del lote comparten el rango de años y el
  desplazamiento `offset_inicio_balance_dias`.
- El lote es reproducible: con la misma semilla (`semilla_imputacion`) y los
  mismos datos produce siempre los mismos resultados.

## 7. Preparar el clima: ETo y relleno de huecos

El balance hídrico necesita `pp` y `eto` completos en todos los días de la
ventana de simulación. El paquete ofrece dos utilidades de preparación del
clima (las ecuaciones y el procedimiento están en la sección 3 del
[manual técnico](MANUAL_TECNICO.md#3-preparación-del-clima)). El **lote las
aplica automáticamente**; en un escenario individual las usás vos.

### 7.1 Calcular la ETo

Si tu CSV de clima no trae `eto`, calculala con Hargreaves-Samani a partir de
las temperaturas y la latitud de la estación:

```r
clima <- leer_clima_csv("mi_clima.csv")

clima$eto <- calcular_eto_hargreaves(
  dia_anio = clima$doy,
  latitud  = -32.9036,     # grados decimales (negativa = sur)
  tx = clima$tx, tn = clima$tn, tm = clima$tm
)
```

### 7.2 Rellenar huecos de clima

Si la serie tiene días sin dato **entre** observaciones reales, el balance
hídrico (que es secuencial) queda inválido. `completar_gaps_clima()` rellena
`tx`, `tn`, `tm` y `pp` en esos huecos:

```r
clima <- leer_clima_csv("mi_clima.csv")          # una sola estación
clima <- completar_gaps_clima(clima, semilla = 1234)
clima$eto <- calcular_eto_hargreaves(clima$doy, -32.9036, clima$tx, clima$tn, clima$tm)
```

Condiciones y comportamiento:

- La serie debe ser **diaria y completa**: una fila por cada día entre la
  primera y la última fecha, ordenadas, de **una sola estación**. (Un día sin
  dato debe estar como fila con valores `NA`, no ausente.)
- Solo se rellenan los huecos **rodeados de datos reales**. Los días `NA` del
  principio o del final de la serie (por ejemplo, el resto del año en curso)
  quedan como están.
- Es un procedimiento estocástico; la `semilla` lo hace **reproducible**.
  Modifica el generador de números aleatorios global de la sesión.
- Calculá `eto` **después** de rellenar los huecos: la función no modifica la
  columna `eto`.

## 8. Regenerar la base de la plataforma web

La plataforma web lee un archivo `balance_hidrico.sqlite` que ya viene en el
repositorio. Solo hay que regenerarlo para **cambiar el catálogo o actualizar
el clima**. Requiere el xlsx de catálogo (con hojas `estaciones`, `clima`,
`suelos`, `horizontes` y `cultivares`) y los paquetes `DBI` y `RSQLite`:

```bash
Rscript scripts/construir_base_datos.R base_datos_balance_hidrico.xlsx balance_hidrico.sqlite
```

El clima, que es lo que más seguido se actualiza, puede venir de un CSV
aparte (columnas `omm_id`, `date`, `tmax`, `tmin`, `tmed`, `prcp`) en lugar de
la hoja `clima`:

```bash
Rscript scripts/construir_base_datos.R base_datos_balance_hidrico.xlsx balance_hidrico.sqlite --clima observaciones.csv
```

Opciones: `--semilla N` (semilla del relleno de huecos, por defecto 1234). El
script rellena los huecos y calcula la `ETo` de todas las estaciones **una sola
vez**, de modo que la plataforma no lo recalcula en cada consulta. Para que la
plataforma publicada use la base nueva hay que volver a construir las imágenes
(ver [`ARQUITECTURA.md`](ARQUITECTURA.md#9-despliegue-docker-y-cicd)).

## 9. Verificar la instalación: tests

El paquete trae una batería de pruebas automáticas. Con el directorio de
trabajo en la raíz del repositorio:

```r
devtools::test()    # corre las pruebas (tests/testthat/)
devtools::check()   # verificación completa del paquete (más lenta)
```

Si `devtools::test()` termina sin fallas, la instalación y el método funcionan
como se espera.

## 10. Errores frecuentes

**`Error: there is no package called 'xxx'`.**
Falta instalar una dependencia: `install.packages("xxx")` (sección 3.1).

**`No existe el archivo de clima / de parametros / de configuracion`.**
La ruta es incorrecta. Recordá que, dentro de un YAML, las rutas son
relativas al **propio YAML**; en la línea de comandos, relativas a la carpeta
raíz del repositorio.

**`cannot open file 'scripts/lib_simular.R'` o similar.**
El directorio de trabajo no es la raíz del repositorio. Usá `cd` (terminal) o
`setwd()` (R) antes de correr los scripts.

**`Cultivo 'xxx' no encontrado` / `Cultivar 'xxx' no encontrado` / `Suelo 'xxx'
no encontrado`.**
El nombre pedido no existe en los parámetros. El mensaje lista las opciones
válidas; compará mayúsculas, guiones y espacios (por ejemplo, el catálogo de la
plataforma usa `GM 3C`, con espacio, y el YAML de ejemplo, `GM3C`).

**`No hay datos climaticos para la estacion 'xxx'`.**
El `estacion` del escenario no coincide con la columna `station_id` del CSV.
Escribilo entre comillas en el YAML (`"87480"`).

**`No hay suficientes datos climaticos para alcanzar la emergencia / R1`.**
El clima termina antes de que el cultivo complete esa etapa. Agregá más días de
clima después de la siembra o adelantá la siembra.

**`La ventana de simulacion [..] excede el rango de clima disponible [..]`.**
Entre la fecha de monitoreo (menos 14 días de la siembra) y la madurez
fisiológica, algún día queda fuera del rango del clima. Acortá el rango de años
o ampliá el clima.

**Resultados `NA` en el balance (o `NaN`).**
Faltan datos de `pp` o `eto` en algún día de la ventana: el balance es
secuencial y un día sin dato contamina el resto. Rellená los huecos y calculá
la ETo (sección 7).

**En el lote: `El archivo de condiciones iniciales ... no existe` o `la hoja
'estaciones' tiene N filas`.**
Revisá la ruta del xlsx, y que la hoja `estaciones` tenga **una sola fila**.

**En el lote: algunas simulaciones aparecen en `batch_errores.csv`.**
Mirá la columna `mensaje_error` de cada fila; los mensajes son los mismos de
esta lista. Las demás simulaciones no se ven afectadas.
