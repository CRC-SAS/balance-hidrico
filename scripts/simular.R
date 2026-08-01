#!/usr/bin/env Rscript
# Corrida de prueba de balancehidrico (Pasos 1-5) para validacion por el
# experto de dominio de CRC-SAS.
#
# Corre fenologia + profundizacion radicular + curva de Kcb + balance
# hidrico diario + salidas para el escenario descripto en un YAML de
# configuracion (ver scripts/escenario_ejemplo.yml) y escribe cuatro CSV en
# <salida.outdir>:
#   <prefix>_hitos.csv          - una fila con las fechas de los hitos fenologicos
#   <prefix>_serie_diaria.csv   - serie diaria (UT, profundidad radicular, Kcb)
#   <prefix>_balance_diario.csv - serie diaria del balance hidrico (Paso 4)
#   <prefix>_salidas.csv        - una fila con las 3 salidas del metodo (Paso 5)
#
# Uso (desde la raiz del repo):
#   Rscript scripts/simular.R scripts/escenario_ejemplo.yml
#   Rscript scripts/simular.R /ruta/a/otro_escenario.yml
#
# El YAML de configuracion tiene estas claves:
#   clima:      ruta al CSV de clima (para leer_clima_csv()). Relativa a la
#               ubicacion del propio YAML si no es absoluta.
#   parametros: ruta al YAML de parametros de cultivo/cultivar/estacion/suelo
#               (para leer_parametros_yaml()). Misma regla de rutas relativas.
#   constantes: opcional, ruta al YAML de constantes categoricas fijas
#               (rastrojo/humedad inicial, para leer_constantes_yaml()).
#               Misma regla de rutas relativas. Si se omite, usa el archivo
#               empaquetado (inst/extdata/constantes.yml) -- estas
#               constantes no varian entre escenarios.
#   escenario:  cultivo, cultivar, estacion, suelo, siembra (fecha),
#               fecha_inicio_balance (fecha, primer dia simulado del Paso 4),
#               rastrojo_clase, humedad_inicial_clase_m1,
#               humedad_inicial_clase_m2 (ver inst/extdata/constantes.yml
#               para los nombres de clase validos), y opcionalmente
#               sandwich_seco_inicial (bool, default false).
#   salida:     outdir (default "salidas") y prefix opcional (default
#               "<cultivo>_<estacion>_<siembra>").

suppressPackageStartupMessages({
  if (requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all(".", quiet = TRUE)
  } else {
    library(balancehidrico)
  }
})

.default_si_null <- function(x, default) if (is.null(x)) default else x

.resolver_ruta <- function(ruta, base_dir) {
  if (is.null(ruta)) return(NULL)
  if (grepl("^(/|~|[A-Za-z]:)", ruta)) ruta else file.path(base_dir, ruta)
}

# --- 0) Leer YAML de configuracion ------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  rlang::abort("Uso: Rscript scripts/simular.R <config.yml> (ver scripts/escenario_ejemplo.yml)")
}
config_path <- args[1]
if (!file.exists(config_path)) {
  rlang::abort(sprintf("No existe el archivo de configuracion '%s'", config_path))
}

config <- yaml::read_yaml(config_path)
config_dir <- dirname(normalizePath(config_path))

escenario <- config$escenario
if (is.null(escenario)) {
  rlang::abort("El YAML de configuracion no tiene la clave 'escenario'")
}
salida <- .default_si_null(config$salida, list())
outdir <- .default_si_null(salida$outdir, "salidas")
prefix <- .default_si_null(
  salida$prefix,
  sprintf("%s_%s_%s", escenario$cultivo, escenario$estacion, escenario$siembra)
)

ruta_clima <- .resolver_ruta(config$clima, config_dir)
ruta_parametros <- .resolver_ruta(config$parametros, config_dir)
ruta_constantes <- .resolver_ruta(config$constantes, config_dir)

# --- 1) Leer inputs ---------------------------------------------------------

clima_completo <- leer_clima_csv(ruta_clima)
clima <- clima_completo[clima_completo$station_id == as.character(escenario$estacion), ]
if (nrow(clima) == 0) {
  rlang::abort(sprintf(
    "No hay datos climaticos para la estacion '%s' en '%s'", escenario$estacion, ruta_clima
  ))
}

parametros <- leer_parametros_yaml(ruta_parametros)
p_cultivar <- obtener_parametros_cultivo(parametros, escenario$cultivo, escenario$cultivar)
profundidad_maxima_suelo <- obtener_profundidad_maxima_suelo(parametros, escenario$suelo)
suelo_balance <- obtener_suelo_balance_hidrico(parametros, escenario$suelo)
constantes <- if (is.null(ruta_constantes)) leer_constantes_yaml() else leer_constantes_yaml(ruta_constantes)

# --- 2) Paso 1: Fenologia ---------------------------------------------------

fenologia <- calcular_fenologia(
  cultivo = escenario$cultivo,
  cultivar = escenario$cultivar,
  clima_estacion = clima,
  fecha_siembra = escenario$siembra,
  parametros = parametros
)

# --- 3) Paso 2: Profundizacion radicular ------------------------------------

raices <- calcular_profundidad_radicular(
  clima_estacion = clima,
  fecha_emergencia = fenologia$hitos$emergencia,
  fecha_hito2 = fenologia$hitos$hito2,
  tb_c = p_cultivar$raiz$tb_c,
  pr_s_e = p_cultivar$raiz$pr_s_e,
  pr = p_cultivar$raiz$pr,
  profundidad_maxima_suelo = profundidad_maxima_suelo
)

# --- 4) Paso 3: Curva de Kcb ------------------------------------------------

kcb <- calcular_curva_kcb(
  serie_ut_simple = fenologia$serie_diaria,
  ut_fkcbini = p_cultivar$ut_e_fkcbini,
  ut_ikcbmax = p_cultivar$ut_e_ikcbmax,
  kcb_ini = p_cultivar$kcb$kcb_ini,
  kcb_max = p_cultivar$kcb$kcb_max
)

# --- 5) Paso 4: Balance hidrico diario --------------------------------------

balance <- calcular_balance_hidrico(
  clima_estacion = clima,
  fecha_inicio = escenario$fecha_inicio_balance,
  serie_profundidad_radicular = raices,
  serie_kcb = kcb,
  suelo = suelo_balance,
  rastrojo_clase = escenario$rastrojo_clase,
  humedad_inicial_clase_m1 = escenario$humedad_inicial_clase_m1,
  humedad_inicial_clase_m2 = escenario$humedad_inicial_clase_m2,
  constantes = constantes,
  sandwich_seco_inicial = .default_si_null(escenario$sandwich_seco_inicial, FALSE)
)

# --- 6) Paso 5: Salidas ------------------------------------------------------

salidas <- calcular_salidas(clima, escenario$siembra, fenologia$hitos, balance$serie_diaria)
salidas_tabla <- dplyr::bind_cols(
  tibble::tibble(eventos_lluvia_pre_siembra = salidas$eventos_lluvia_pre_siembra),
  salidas$estado_hidrico_siembra,
  tibble::tibble(confort_hidrico = salidas$confort_hidrico)
)

# --- 7) Combinar y escribir salidas ------------------------------------------

serie_diaria <- fenologia$serie_diaria
serie_diaria <- dplyr::left_join(serie_diaria, raices, by = "date")
serie_diaria <- dplyr::left_join(serie_diaria, kcb, by = "date")

if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

archivo_hitos <- file.path(outdir, paste0(prefix, "_hitos.csv"))
archivo_serie <- file.path(outdir, paste0(prefix, "_serie_diaria.csv"))
archivo_balance <- file.path(outdir, paste0(prefix, "_balance_diario.csv"))
archivo_salidas <- file.path(outdir, paste0(prefix, "_salidas.csv"))

readr::write_csv(fenologia$hitos, archivo_hitos)
readr::write_csv(serie_diaria, archivo_serie)
readr::write_csv(balance$serie_diaria, archivo_balance)
readr::write_csv(salidas_tabla, archivo_salidas)

cat(sprintf(
  "Escenario: cultivo=%s cultivar=%s estacion=%s suelo=%s siembra=%s\n",
  escenario$cultivo, escenario$cultivar, escenario$estacion, escenario$suelo, escenario$siembra
))
cat(sprintf("Hitos escritos en:          %s\n", archivo_hitos))
cat(sprintf("Serie diaria escrita en:    %s\n", archivo_serie))
cat(sprintf("Balance diario escrito en:  %s\n", archivo_balance))
cat(sprintf("Salidas escritas en:        %s\n", archivo_salidas))
