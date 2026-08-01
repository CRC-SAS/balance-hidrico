#' Leer datos climaticos diarios desde un CSV
#'
#' Lee un CSV con el formato descripto en `inst/extdata/clima_ejemplo.csv`:
#' una fila por dia y estacion, con columnas `station_id`, `date`, `tx`, `tn`
#' y, opcionalmente, `tm`, `pp` y `eto`. Agrega la columna `doy` (dia del
#' anio).
#'
#' @param path Character. Ruta al archivo CSV.
#'
#' @return Un tibble con columnas `station_id` (character), `date` (Date),
#'   `doy` (integer), `tx`, `tn`, `tm`, `pp`, `eto` (double, `tm`/`pp`/`eto`
#'   pueden venir `NA` si la columna no estaba en el CSV).
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
      pp = readr::col_double(),
      eto = readr::col_double()
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
  if (!"eto" %in% names(clima)) clima$eto <- NA_real_

  clima <- dplyr::mutate(clima, doy = lubridate::yday(.data$date))
  dplyr::select(clima, "station_id", "date", "doy", "tx", "tn", "tm", "pp", "eto")
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

#' Leer constantes categoricas fijas (rastrojo, humedad inicial) desde YAML
#'
#' A diferencia de [leer_parametros_yaml()] (que siempre requiere `path`
#' explicito porque el contenido varia por escenario), esta funcion tiene un
#' default que apunta al archivo empaquetado, porque estas constantes NO
#' varian entre escenarios (ver `inst/extdata/constantes.yml`). El default
#' puede sobreescribirse (p.ej. en tests, o si CRC-SAS decide versionar
#' estos valores por fuera del paquete).
#'
#' @param path Character. Ruta al YAML de constantes. Por defecto, el
#'   archivo empaquetado `inst/extdata/constantes.yml`.
#'
#' @return Lista con (al menos) los elementos `rastrojo` y `humedad_inicial`.
#' @export
leer_constantes_yaml <- function(path = system.file("extdata", "constantes.yml", package = "balancehidrico")) {
  if (!file.exists(path)) {
    rlang::abort(glue::glue("No existe el archivo de constantes: {path}"))
  }

  constantes <- yaml::read_yaml(path)

  if (is.null(constantes$rastrojo) || is.null(constantes$humedad_inicial)) {
    rlang::abort(glue::glue(
      "El archivo de constantes {path} debe tener las secciones 'rastrojo' y 'humedad_inicial'"
    ))
  }

  constantes
}

#' Factor de reduccion de demanda evaporativa por cobertura de rastrojo
#'
#' @param constantes Lista devuelta por [leer_constantes_yaml()].
#' @param clase Character. Una de `names(constantes$rastrojo)` (p.ej. `"Baja"`).
#'
#' @return Numeric (0-1).
#' @export
obtener_factor_rastrojo <- function(constantes, clase) {
  disponibles <- names(constantes$rastrojo)
  if (!clase %in% disponibles) {
    rlang::abort(glue::glue(
      "Clase de rastrojo '{clase}' no encontrada. Disponibles: {paste(disponibles, collapse = ', ')}"
    ))
  }
  constantes$rastrojo[[clase]]
}

#' Fraccion de agua util inicial por clase de humedad
#'
#' @param constantes Lista devuelta por [leer_constantes_yaml()].
#' @param clase Character. Una de `names(constantes$humedad_inicial)` (p.ej. `"Se"`).
#'
#' @return Numeric (0-1).
#' @export
obtener_fraccion_humedad_inicial <- function(constantes, clase) {
  disponibles <- names(constantes$humedad_inicial)
  if (!clase %in% disponibles) {
    rlang::abort(glue::glue(
      "Clase de humedad inicial '{clase}' no encontrada. Disponibles: {paste(disponibles, collapse = ', ')}"
    ))
  }
  constantes$humedad_inicial[[clase]]
}

#' Suelo completo (Paso 4): horizontes + parametros de suelo
#'
#' A diferencia de [obtener_profundidad_maxima_suelo()] (que solo necesita
#' el Paso 2), esta funcion arma la estructura completa que necesita
#' `calcular_balance_hidrico()`: los escalares de suelo (`cn`, `kl`, `um`,
#' `u`, `dr`) y los 8 horizontes (`nombre`, `pfh_m`, `pmp`, `cc`, `sat`).
#'
#' @param parametros Lista devuelta por [leer_parametros_yaml()].
#' @param soil_id Character. Identificador del suelo. Debe tener las claves
#'   `cn`, `kl`, `um`, `u`, `dr` y `horizontes` -- ver `IN64MARC02` en
#'   `inst/extdata/parametros_ejemplo.yml`.
#'
#' @return Lista `list(cn, kl, um, u, dr, horizontes = tibble(nombre, pfh_m, pmp, cc, sat))`.
#' @export
obtener_suelo_balance_hidrico <- function(parametros, soil_id) {
  soil_id <- as.character(soil_id)
  suelo <- parametros$suelos[[soil_id]]
  campos_requeridos <- c("cn", "kl", "um", "u", "dr", "horizontes")
  faltantes <- campos_requeridos[!campos_requeridos %in% names(suelo)]
  if (is.null(suelo) || length(faltantes) > 0) {
    rlang::abort(glue::glue(
      "El suelo '{soil_id}' no tiene los campos de Paso 4 requeridos: ",
      "{paste(faltantes, collapse = ', ')}. Revisar 'suelos' en el YAML de parametros."
    ))
  }

  list(
    cn = suelo$cn, kl = suelo$kl, um = suelo$um, u = suelo$u, dr = suelo$dr,
    horizontes = dplyr::bind_rows(lapply(suelo$horizontes, tibble::as_tibble))
  )
}
