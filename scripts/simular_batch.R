#!/usr/bin/env Rscript
# Corrida batch de balancehidrico (Pasos 1-5) para multiples combinaciones
# de suelo/cultivo/cultivar/condicion inicial x anios de siembra.
#
# Lee un xlsx de condiciones iniciales (6 hojas: estaciones, clima, suelos,
# horizontes, cultivares, escenarios -- ver
# leer_condiciones_iniciales_xlsx() en scripts/lib_simular.R) y un YAML de
# configuracion del batch (ver scripts/batch_ejemplo.yml), y escribe cuatro
# CSV acumulados en <salida.outdir>:
#   <prefix>_hitos.csv          - una fila por simulacion OK
#   <prefix>_serie_diaria.csv   - serie diaria por simulacion OK
#   <prefix>_balance_diario.csv - serie diaria del balance por simulacion OK
#   <prefix>_salidas.csv        - una fila por simulacion OK
#   <prefix>_errores.csv        - una fila por simulacion que fallo (vacio con
#                                  headers si no hubo errores)
#
# Uso (desde la raiz del repo):
#   Rscript scripts/simular_batch.R scripts/batch_ejemplo.yml
#
# El YAML de configuracion tiene estas claves:
#   condiciones_iniciales: ruta al xlsx (relativa a la ubicacion del propio
#                           YAML si no es absoluta).
#   anios: desde, hasta (anios de siembra a simular).
#   offset_inicio_balance_dias: obligatorio (sin default). fecha_inicio_balance
#                                = siembra - N dias, fijo para todo el batch.
#   salida: outdir (default "salidas_batch") y prefix opcional (default
#           "batch").

suppressPackageStartupMessages({
  if (requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all(".", quiet = TRUE)
  } else {
    library(balancehidrico)
  }
})

source("scripts/lib_simular.R")

# --- 0) Leer YAML de configuracion ------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  rlang::abort("Uso: Rscript scripts/simular_batch.R <config.yml> (ver scripts/batch_ejemplo.yml)")
}
config_path <- args[1]
if (!file.exists(config_path)) {
  rlang::abort(sprintf("No existe el archivo de configuracion '%s'", config_path))
}

config <- yaml::read_yaml(config_path)
config_dir <- dirname(normalizePath(config_path))

if (is.null(config$condiciones_iniciales)) {
  rlang::abort("El YAML de configuracion no tiene la clave 'condiciones_iniciales'")
}
if (is.null(config$anios) || is.null(config$anios$desde) || is.null(config$anios$hasta)) {
  rlang::abort("El YAML de configuracion no tiene la clave 'anios' (con 'desde'/'hasta')")
}
if (is.null(config$offset_inicio_balance_dias)) {
  rlang::abort("El YAML de configuracion no tiene la clave 'offset_inicio_balance_dias'")
}
offset_dias <- config$offset_inicio_balance_dias
semilla_imputacion <- .default_si_null(config$semilla_imputacion, 1234)

salida <- .default_si_null(config$salida, list())
outdir <- .default_si_null(salida$outdir, "salidas_batch")
prefix <- .default_si_null(salida$prefix, "batch")

ruta_xlsx <- .resolver_ruta(config$condiciones_iniciales, config_dir)

# --- 1) Leer inputs y armar el grid ------------------------------------------

inputs <- leer_condiciones_iniciales_xlsx(ruta_xlsx, semilla_imputacion = semilla_imputacion)
grid <- construir_grid_batch(
  escenarios = inputs$escenarios,
  estacion = inputs$estacion,
  anio_desde = config$anios$desde,
  anio_hasta = config$anios$hasta,
  offset_dias = offset_dias
)

cat(sprintf("Grid del batch: %d simulaciones (%d escenarios x %d anios)\n",
            nrow(grid), length(unique(grid$escenario)),
            config$anios$hasta - config$anios$desde + 1))

# --- 2) Loop de simulaciones --------------------------------------------------

id_cols <- c(
  "id_simulacion", "escenario", "cultivo", "cultivar", "estacion", "suelo",
  "siembra", "fecha_inicio_balance", "rastrojo_clase",
  "humedad_inicial_clase_m1", "humedad_inicial_clase_m2", "sandwich_seco_inicial"
)

hitos_lista <- list()
serie_diaria_lista <- list()
balance_diario_lista <- list()
salidas_lista <- list()
errores_lista <- list()

clima_estacion <- inputs$clima_completo[inputs$clima_completo$station_id == inputs$estacion, ]

for (i in seq_len(nrow(grid))) {
  fila <- grid[i, ]
  identificatorias <- fila[, id_cols]

  resultado <- tryCatch(
    {
      clima_recortada <- .recortar_clima_escenario(
        clima_estacion = clima_estacion,
        cultivo = fila$cultivo,
        cultivar = fila$cultivar,
        siembra = fila$siembra,
        fecha_inicio_balance = fila$fecha_inicio_balance,
        parametros = inputs$parametros
      )
      simular_escenario(
        cultivo = fila$cultivo,
        cultivar = fila$cultivar,
        estacion = fila$estacion,
        suelo = fila$suelo,
        siembra = fila$siembra,
        fecha_inicio_balance = fila$fecha_inicio_balance,
        rastrojo_clase = fila$rastrojo_clase,
        humedad_inicial_clase_m1 = fila$humedad_inicial_clase_m1,
        humedad_inicial_clase_m2 = fila$humedad_inicial_clase_m2,
        sandwich_seco_inicial = fila$sandwich_seco_inicial,
        clima_completo = clima_recortada,
        parametros = inputs$parametros,
        constantes = inputs$constantes
      )
    },
    error = function(e) e
  )

  if (inherits(resultado, "error")) {
    cat(sprintf("[%d/%d] %s ERROR\n", i, nrow(grid), fila$id_simulacion))
    errores_lista[[fila$id_simulacion]] <- dplyr::bind_cols(
      identificatorias, tibble::tibble(mensaje_error = conditionMessage(resultado))
    )
    next
  }

  cat(sprintf("[%d/%d] %s OK\n", i, nrow(grid), fila$id_simulacion))
  hitos_sin_siembra <- dplyr::select(resultado$hitos, -"siembra")
  hitos_lista[[fila$id_simulacion]] <- dplyr::bind_cols(identificatorias, hitos_sin_siembra)
  serie_diaria_lista[[fila$id_simulacion]] <- dplyr::bind_cols(identificatorias, resultado$serie_diaria)
  balance_diario_lista[[fila$id_simulacion]] <- dplyr::bind_cols(identificatorias, resultado$balance_diario)
  salidas_lista[[fila$id_simulacion]] <- dplyr::bind_cols(identificatorias, resultado$salidas_tabla)
}

# --- 3) Acumular y escribir salidas -------------------------------------------

if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

archivo_hitos <- file.path(outdir, paste0(prefix, "_hitos.csv"))
archivo_serie <- file.path(outdir, paste0(prefix, "_serie_diaria.csv"))
archivo_balance <- file.path(outdir, paste0(prefix, "_balance_diario.csv"))
archivo_salidas <- file.path(outdir, paste0(prefix, "_salidas.csv"))
archivo_errores <- file.path(outdir, paste0(prefix, "_errores.csv"))

readr::write_csv(dplyr::bind_rows(hitos_lista), archivo_hitos)
readr::write_csv(dplyr::bind_rows(serie_diaria_lista), archivo_serie)
readr::write_csv(dplyr::bind_rows(balance_diario_lista), archivo_balance)
readr::write_csv(dplyr::bind_rows(salidas_lista), archivo_salidas)

errores_tabla <- if (length(errores_lista) > 0) {
  dplyr::bind_rows(errores_lista)
} else {
  tibble::tibble(
    id_simulacion = character(), escenario = integer(), cultivo = character(),
    cultivar = character(), estacion = character(), suelo = character(),
    siembra = as.Date(character()), fecha_inicio_balance = as.Date(character()),
    rastrojo_clase = character(), humedad_inicial_clase_m1 = character(),
    humedad_inicial_clase_m2 = character(), sandwich_seco_inicial = logical(),
    mensaje_error = character()
  )
}
readr::write_csv(errores_tabla, archivo_errores)

n_ok <- length(hitos_lista)
n_error <- length(errores_lista)
cat(sprintf("\n%d/%d simulaciones OK", n_ok, nrow(grid)))
if (n_error > 0) cat(sprintf(", %d con error (detalle en %s)", n_error, archivo_errores))
cat("\n")
if (n_ok == 0) {
  warning("Ninguna simulacion del batch se completo con exito -- revisar ", archivo_errores)
}

cat(sprintf("Hitos escritos en:          %s\n", archivo_hitos))
cat(sprintf("Serie diaria escrita en:    %s\n", archivo_serie))
cat(sprintf("Balance diario escrito en:  %s\n", archivo_balance))
cat(sprintf("Salidas escritas en:        %s\n", archivo_salidas))
cat(sprintf("Errores escritos en:        %s\n", archivo_errores))
