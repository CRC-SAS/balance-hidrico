#!/usr/bin/env Rscript
# Construye la base de datos SQLite de la plataforma de escenarios
# individuales a partir de las primeras 5 solapas de un xlsx de catalogo
# (estaciones, clima, suelos, horizontes, cultivares -- las hojas
# "escenarios", "equivalencias", "UI Entrada", "UI Salida" del xlsx no se
# cargan, son referencia de diseno).
#
# La tabla `clima` queda pre-calculada: huecos rellenados con
# completar_gaps_clima() (R/imputacion_clima.R) y `eto` calculada con
# calcular_eto_hargreaves() (R/utils_clima.R) -- ver decision de diseno en
# el README, seccion "Base de datos de la plataforma". Reproducibilidad:
# misma semilla en cada corrida (`--semilla`, default 1234) da siempre la
# misma SQLite.
#
# Uso (desde la raiz del repo):
#   Rscript scripts/construir_base_datos.R <catalogo.xlsx> <salida.sqlite> [--semilla N]
#   Rscript scripts/construir_base_datos.R base_datos_balance_hidrico.xlsx balance_hidrico.sqlite

suppressPackageStartupMessages({
  if (requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all(".", quiet = TRUE)
  } else {
    library(balancehidrico)
  }
  library(DBI)
})

source("scripts/lib_simular.R")

# --- 0) Argumentos -----------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  rlang::abort(paste(
    "Uso: Rscript scripts/construir_base_datos.R <catalogo.xlsx> <salida.sqlite> [--semilla N]"
  ))
}
ruta_xlsx <- args[1]
ruta_sqlite <- args[2]
semilla_idx <- which(args == "--semilla")
semilla_imputacion <- if (length(semilla_idx) == 1) as.integer(args[semilla_idx + 1]) else 1234L

if (!file.exists(ruta_xlsx)) {
  rlang::abort(sprintf("No existe el archivo de catalogo '%s'", ruta_xlsx))
}

# --- 1) Leer las 5 solapas del xlsx ------------------------------------------

cat(sprintf("Leyendo '%s'...\n", ruta_xlsx))

estaciones <- readxl::read_excel(ruta_xlsx, sheet = "estaciones")
suelos <- readxl::read_excel(ruta_xlsx, sheet = "suelos")
horizontes <- readxl::read_excel(ruta_xlsx, sheet = "horizontes")
cultivares <- readxl::read_excel(ruta_xlsx, sheet = "cultivares")
clima_raw <- readxl::read_excel(ruta_xlsx, sheet = "clima")

# --- 2) Armar tabla `clima`: gaps rellenados + eto, todas las estaciones ----

cat(sprintf(
  "Completando gaps climaticos y calculando ETo (Hargreaves-Samani, semilla=%d) para %d estaciones...\n",
  semilla_imputacion, nrow(estaciones)
))

clima_completo <- tibble::tibble(
  station_id = as.character(clima_raw$omm_id),
  date = as.Date(clima_raw$fecha),
  doy = lubridate::yday(date),
  tx = suppressWarnings(as.numeric(clima_raw$tmax)),
  tn = suppressWarnings(as.numeric(clima_raw$tmin)),
  tm = suppressWarnings(as.numeric(clima_raw$tmed)),
  pp = suppressWarnings(as.numeric(clima_raw$prcp))
)

latitud_por_estacion <- stats::setNames(
  as.numeric(estaciones$latitud), as.character(estaciones$omm_id)
)

clima_relleno <- lapply(sort(unique(clima_completo$station_id)), function(id) {
  clima_estacion <- clima_completo[clima_completo$station_id == id, ]
  clima_estacion <- completar_gaps_clima(clima_estacion, semilla = semilla_imputacion)
  clima_estacion$eto <- calcular_eto_hargreaves(
    clima_estacion$doy, latitud_por_estacion[[id]],
    clima_estacion$tx, clima_estacion$tn, clima_estacion$tm
  )
  clima_estacion
})
clima_completo <- dplyr::bind_rows(clima_relleno)

n_pendientes <- sum(is.na(clima_completo$tx) | is.na(clima_completo$tn) | is.na(clima_completo$pp))
if (n_pendientes > 0) {
  cat(sprintf(
    "Aviso: %d dias quedan con NA en tx/tn/pp (huecos que tocan el borde de la serie, no rellenados a proposito).\n",
    n_pendientes
  ))
}

# --- 3) Armar tabla `estaciones` con nombres de columna en minuscula --------

estaciones_tabla <- dplyr::transmute(
  estaciones,
  omm_id = as.integer(omm_id),
  nombre = nombre,
  longitud = as.numeric(longitud),
  latitud = as.numeric(latitud),
  localidad = localidad
)

clima_tabla <- dplyr::transmute(
  clima_completo,
  omm_id = as.integer(station_id),
  fecha = as.character(date),
  tmax = tx,
  tmin = tn,
  tmed = tm,
  prcp = pp,
  eto = eto
)

# --- 4) Armar tablas `suelos`/`horizontes`/`cultivares` ---------------------

suelos_tabla <- dplyr::transmute(
  suelos,
  suelo = suelo,
  u = suppressWarnings(as.numeric(U)),
  dr = suppressWarnings(as.numeric(DR)),
  cn = suppressWarnings(as.numeric(CN)),
  kl = suppressWarnings(as.numeric(kl)),
  um = suppressWarnings(as.numeric(Um)),
  localidad = localidad,
  tipo_suelo = tipo_suelo,
  serie_suelo = serie_suelo
)

horizontes_tabla <- dplyr::transmute(
  horizontes,
  suelo = suelo,
  pfh_m = suppressWarnings(as.numeric(PFH)),
  horiz = Horiz,
  pmp = suppressWarnings(as.numeric(PMP)),
  cc = suppressWarnings(as.numeric(CC)),
  sat = suppressWarnings(as.numeric(Sat))
)

cultivares_tabla <- dplyr::transmute(
  cultivares,
  cultivo = cultivo,
  cultivar = cultivar,
  parametro = parametro,
  valor = suppressWarnings(as.numeric(valor)),
  unidad = unidad
)

# --- 5) Escribir la SQLite ----------------------------------------------------

if (file.exists(ruta_sqlite)) invisible(file.remove(ruta_sqlite))
con <- DBI::dbConnect(RSQLite::SQLite(), ruta_sqlite)
ejecutar <- function(sql) invisible(DBI::dbExecute(con, sql))

ejecutar("PRAGMA foreign_keys = ON")

ejecutar("
  CREATE TABLE estaciones (
    omm_id INTEGER PRIMARY KEY,
    nombre TEXT NOT NULL,
    longitud REAL NOT NULL,
    latitud REAL NOT NULL,
    localidad TEXT NOT NULL
  )
")
ejecutar("
  CREATE TABLE clima (
    omm_id INTEGER NOT NULL,
    fecha TEXT NOT NULL,
    tmax REAL,
    tmin REAL,
    tmed REAL,
    prcp REAL,
    eto REAL,
    PRIMARY KEY (omm_id, fecha),
    FOREIGN KEY (omm_id) REFERENCES estaciones(omm_id)
  )
")
ejecutar("
  CREATE TABLE suelos (
    suelo TEXT PRIMARY KEY,
    u REAL NOT NULL,
    dr REAL NOT NULL,
    cn REAL NOT NULL,
    kl REAL NOT NULL,
    um REAL NOT NULL,
    localidad TEXT NOT NULL,
    tipo_suelo TEXT,
    serie_suelo TEXT
  )
")
ejecutar("
  CREATE TABLE horizontes (
    suelo TEXT NOT NULL,
    pfh_m REAL NOT NULL,
    horiz TEXT,
    pmp REAL NOT NULL,
    cc REAL NOT NULL,
    sat REAL NOT NULL,
    PRIMARY KEY (suelo, pfh_m),
    FOREIGN KEY (suelo) REFERENCES suelos(suelo)
  )
")
ejecutar("
  CREATE TABLE cultivares (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cultivo TEXT NOT NULL,
    cultivar TEXT,
    parametro TEXT NOT NULL,
    valor REAL NOT NULL,
    unidad TEXT
  )
")
ejecutar("CREATE INDEX idx_estaciones_localidad ON estaciones(localidad)")
ejecutar("CREATE INDEX idx_suelos_localidad ON suelos(localidad)")
ejecutar("CREATE INDEX idx_horizontes_suelo ON horizontes(suelo)")
ejecutar("CREATE INDEX idx_cultivares_cultivo ON cultivares(cultivo)")

DBI::dbWriteTable(con, "estaciones", estaciones_tabla, append = TRUE)
DBI::dbWriteTable(con, "clima", clima_tabla, append = TRUE)
DBI::dbWriteTable(con, "suelos", suelos_tabla, append = TRUE)
DBI::dbWriteTable(con, "horizontes", horizontes_tabla, append = TRUE)
DBI::dbWriteTable(con, "cultivares", cultivares_tabla, append = TRUE)

DBI::dbDisconnect(con)

cat(sprintf(
  "SQLite escrita en '%s': %d estaciones, %d dias de clima, %d suelos, %d horizontes, %d filas de cultivares.\n",
  ruta_sqlite, nrow(estaciones_tabla), nrow(clima_tabla), nrow(suelos_tabla),
  nrow(horizontes_tabla), nrow(cultivares_tabla)
))
