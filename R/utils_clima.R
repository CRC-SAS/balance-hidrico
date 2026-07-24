#' Temperatura media diaria
#'
#' Si la temperatura media (`tm`) esta disponible en la base climatica se usa
#' directamente (ver duda F-7 del documento maestro). Si no, se calcula como
#' el promedio aritmetico entre la temperatura maxima y minima.
#'
#' @param tx Numeric. Temperatura maxima diaria (°C).
#' @param tn Numeric. Temperatura minima diaria (°C).
#' @param tm Numeric. Temperatura media diaria (°C), si esta disponible.
#'   `NA` (el default) indica que no esta disponible y debe recomputarse.
#'
#' @return Numeric. Temperatura media diaria (°C).
#' @export
calcular_temperatura_media <- function(tx, tn, tm = NA_real_) {
  dplyr::if_else(is.na(tm), (tx + tn) / 2, tm)
}

#' Declinacion solar
#'
#' Formula usada en la hoja `clima` del xlsx de referencia (columna
#' "declinacion solar"): `23.45 * sin(radians(360/365 * (dia_anio - 81)))`.
#'
#' @param dia_anio Integer. Dia del anio (1-366).
#'
#' @return Numeric. Declinacion solar en grados.
#' @export
calcular_declinacion_solar <- function(dia_anio) {
  23.45 * sin((360 / 365 * (dia_anio - 81)) * pi / 180)
}

#' Fotoperiodo (Fp)
#'
#' Horas de luz solar en funcion del dia del anio y la latitud, siguiendo la
#' formula de la hoja `clima` del xlsx de referencia (celda `J2`). Maneja los
#' casos extremos de dia y noche polar de la misma forma que el `IFERROR` de
#' la formula original: si el argumento del arco-coseno es mayor a 1 (noche
#' polar) el fotoperiodo es 0 h; si es menor a -1 (dia polar) es 24 h.
#'
#' @param dia_anio Integer. Dia del anio (1-366).
#' @param latitud Numeric. Latitud en grados decimales (negativa = hemisferio
#'   sur).
#'
#' @return Numeric. Fotoperiodo en horas.
#' @export
calcular_fotoperiodo <- function(dia_anio, latitud) {
  declinacion <- calcular_declinacion_solar(dia_anio)
  x <- -tan(latitud * pi / 180) * tan(declinacion * pi / 180)

  # acos() solo esta definido en [-1, 1]; se recorta el argumento para evitar
  # NaN con warning en los casos de dia/noche polar, que igual se resuelven
  # explicitamente en las dos primeras ramas.
  dplyr::case_when(
    x > 1  ~ 0,
    x < -1 ~ 24,
    TRUE   ~ 24 / pi * acos(pmin(pmax(x, -1), 1))
  )
}
