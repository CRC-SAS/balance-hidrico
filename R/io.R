#' Leer datos climaticos diarios desde un CSV
#'
#' Lee un CSV con el formato descripto en `inst/extdata/clima_ejemplo.csv`:
#' una fila por dia y estacion, con columnas `station_id`, `date`, `tx`, `tn`
#' y, opcionalmente, `tm` y `pp`. Agrega la columna `doy` (dia del anio).
#'
#' @param path Character. Ruta al archivo CSV.
#'
#' @return Un tibble con columnas `station_id` (character), `date` (Date),
#'   `doy` (integer), `tx`, `tn`, `tm`, `pp` (double, `tm`/`pp` pueden venir
#'   `NA` si la columna no estaba en el CSV).
#' @importFrom rlang .data
#' @export
leer_clima_csv <- function(path) {
  if (!file.exists(path)) {
    rlang::abort(glue::glue("No existe el archivo de clima: {path}"))
  }

  clima <- readr::read_csv(
    path,
    col_types = readr::cols(
      station_id = readr::col_character(),
      date = readr::col_date(format = "%Y-%m-%d"),
      tx = readr::col_double(),
      tn = readr::col_double(),
      tm = readr::col_double(),
      pp = readr::col_double()
    )
  )

  columnas_requeridas <- c("station_id", "date", "tx", "tn")
  faltantes <- setdiff(columnas_requeridas, names(clima))
  if (length(faltantes) > 0) {
    rlang::abort(glue::glue(
      "Faltan columnas requeridas en {path}: {paste(faltantes, collapse = ', ')}"
    ))
  }

  if (!"tm" %in% names(clima)) clima$tm <- NA_real_
  if (!"pp" %in% names(clima)) clima$pp <- NA_real_

  clima <- dplyr::mutate(clima, doy = lubridate::yday(.data$date))
  dplyr::select(clima, "station_id", "date", "doy", "tx", "tn", "tm", "pp")
}

#' Leer parametros de cultivo/cultivar/estacion/suelo desde un YAML
#'
#' Lee y valida minimamente la estructura de un archivo de parametros como
#' `inst/extdata/parametros_ejemplo.yml` (documentado ahi mismo).
#'
#' @param path Character. Ruta al archivo YAML.
#'
#' @return Lista anidada con (al menos) el elemento `cultivos`.
#' @export
leer_parametros_yaml <- function(path) {
  if (!file.exists(path)) {
    rlang::abort(glue::glue("No existe el archivo de parametros: {path}"))
  }

  parametros <- yaml::read_yaml(path)

  if (is.null(parametros$cultivos)) {
    rlang::abort(glue::glue("El archivo de parametros {path} no tiene la seccion 'cultivos'"))
  }

  parametros
}

#' Extraer y validar los parametros de un cultivo (y opcionalmente cultivar)
#'
#' Devuelve la sublista de `parametros$cultivos` correspondiente al cultivo
#' pedido, con los parametros del cultivar (si se pide uno) mezclados al
#' mismo nivel. Falla con un mensaje explicito si el cultivo/cultivar no
#' existe, en vez de devolver `NULL`s silenciosos que despues rompen mas
#' abajo (ver antecedente de parametros faltantes en `lib/fenologia.R`).
#'
#' @param parametros Lista devuelta por [leer_parametros_yaml()].
#' @param cultivo Character. Uno de `"trigo"`, `"maiz"`, `"soja"`.
#' @param cultivar Character opcional. Debe existir en
#'   `parametros$cultivos[[cultivo]]$cultivares` si se especifica.
#'
#' @return Lista con los parametros del cultivo (y, si se pidio, del
#'   cultivar mezclados al mismo nivel, sin el elemento `cultivares`).
#' @export
obtener_parametros_cultivo <- function(parametros, cultivo, cultivar = NULL) {
  cultivos_disponibles <- names(parametros$cultivos)
  if (!cultivo %in% cultivos_disponibles) {
    rlang::abort(glue::glue(
      "Cultivo '{cultivo}' no encontrado. Disponibles: {paste(cultivos_disponibles, collapse = ', ')}"
    ))
  }

  params_cultivo <- parametros$cultivos[[cultivo]]

  if (!is.null(cultivar)) {
    cultivares_disponibles <- names(params_cultivo$cultivares)
    if (!cultivar %in% cultivares_disponibles) {
      rlang::abort(glue::glue(
        "Cultivar '{cultivar}' no encontrado para '{cultivo}'. ",
        "Disponibles: {paste(cultivares_disponibles, collapse = ', ')}"
      ))
    }
    params_cultivar <- params_cultivo$cultivares[[cultivar]]
    params_cultivo$cultivares <- NULL
    params_cultivo <- utils::modifyList(params_cultivo, params_cultivar)
  }

  params_cultivo
}

#' Latitud de una estacion
#'
#' @param parametros Lista devuelta por [leer_parametros_yaml()].
#' @param station_id Character o numeric. Identificador de la estacion.
#'
#' @return Numeric. Latitud en grados decimales.
#' @export
obtener_latitud_estacion <- function(parametros, station_id) {
  station_id <- as.character(station_id)
  estacion <- parametros$estaciones[[station_id]]
  if (is.null(estacion) || is.null(estacion$latitud)) {
    rlang::abort(glue::glue("No hay latitud configurada para la estacion '{station_id}'"))
  }
  estacion$latitud
}

#' Profundidad maxima de un suelo
#'
#' @param parametros Lista devuelta por [leer_parametros_yaml()].
#' @param soil_id Character. Identificador del suelo.
#'
#' @return Numeric. Profundidad maxima del suelo, en metros.
#' @export
obtener_profundidad_maxima_suelo <- function(parametros, soil_id) {
  soil_id <- as.character(soil_id)
  suelo <- parametros$suelos[[soil_id]]
  if (is.null(suelo) || is.null(suelo$profundidad_maxima_m)) {
    rlang::abort(glue::glue("No hay profundidad maxima configurada para el suelo '{soil_id}'"))
  }
  suelo$profundidad_maxima_m
}
