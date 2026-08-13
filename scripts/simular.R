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

source("scripts/lib_simular.R")

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

# --- 1) Leer inputs ---------------------------------------------------------

inputs <- leer_inputs_comunes(config = config, config_dir = config_dir)

# --- 2-6) Pasos 1-5 -----------------------------------------------------------

resultado <- simular_escenario(
  cultivo = escenario$cultivo,
  cultivar = escenario$cultivar,
  estacion = escenario$estacion,
  suelo = escenario$suelo,
  siembra = escenario$siembra,
  fecha_inicio_balance = escenario$fecha_inicio_balance,
  rastrojo_clase = escenario$rastrojo_clase,
  humedad_inicial_clase_m1 = escenario$humedad_inicial_clase_m1,
  humedad_inicial_clase_m2 = escenario$humedad_inicial_clase_m2,
  sandwich_seco_inicial = .default_si_null(escenario$sandwich_seco_inicial, FALSE),
  clima_completo = inputs$clima_completo,
  parametros = inputs$parametros,
  constantes = inputs$constantes
)

# --- 7) Escribir salidas ------------------------------------------------------

if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

archivo_hitos <- file.path(outdir, paste0(prefix, "_hitos.csv"))
archivo_serie <- file.path(outdir, paste0(prefix, "_serie_diaria.csv"))
archivo_balance <- file.path(outdir, paste0(prefix, "_balance_diario.csv"))
archivo_salidas <- file.path(outdir, paste0(prefix, "_salidas.csv"))

readr::write_csv(resultado$hitos, archivo_hitos)
readr::write_csv(resultado$serie_diaria, archivo_serie)
readr::write_csv(resultado$balance_diario, archivo_balance)
readr::write_csv(resultado$salidas_tabla, archivo_salidas)

cat(sprintf(
  "Escenario: cultivo=%s cultivar=%s estacion=%s suelo=%s siembra=%s\n",
  escenario$cultivo, escenario$cultivar, escenario$estacion, escenario$suelo, escenario$siembra
))
cat(sprintf("Hitos escritos en:          %s\n", archivo_hitos))
cat(sprintf("Serie diaria escrita en:    %s\n", archivo_serie))
cat(sprintf("Balance diario escrito en:  %s\n", archivo_balance))
cat(sprintf("Salidas escritas en:        %s\n", archivo_salidas))
