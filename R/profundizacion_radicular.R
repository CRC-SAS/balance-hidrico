#' Profundizacion radicular potencial (Paso 2)
#'
#' Implementa la Seccion 5 del documento maestro: profundidad constante
#' entre siembra y emergencia, luego crecimiento a una tasa `pr` (cm/°C,
#' base `tb_c`) desde emergencia hasta `fecha_hito2` (cuaje de granos:
#' Z71 en trigo, R2 en maiz, R5 en soja), momento en que se congela. Esta
#' es la profundidad **potencial**; la limitacion por sequia (PR-2 / BH-5)
#' pertenece al Paso 4 y no esta implementada aca.
#'
#' A diferencia de la hoja `fenologia` del xlsx de referencia (que no tiene
#' contexto de suelo), esta funcion aplica explicitamente el tope contra la
#' profundidad maxima del suelo que pide el documento ("hasta la prof.
#' maxima del suelo o el cuaje de granos, lo que ocurra primero" -- duda
#' PR-1): si se provee `profundidad_maxima_suelo`, la profundidad calculada
#' nunca la supera.
#'
#' @param clima_estacion Tibble de una unica estacion (con `date`, `tx`,
#'   `tn`, `tm`), tal como devuelve [leer_clima_csv()].
#' @param fecha_emergencia Date. Fecha de emergencia (de
#'   [calcular_fenologia()]).
#' @param fecha_hito2 Date. Fecha de cuaje de granos -hito2- (de
#'   [calcular_fenologia()]); a partir de esta fecha la profundidad se
#'   congela.
#' @param tb_c Numeric. Temperatura base (°C) para el crecimiento radicular.
#' @param pr_s_e Numeric. Profundidad constante entre siembra y emergencia
#'   (m).
#' @param pr Numeric. Tasa de profundizacion radicular (cm/°C).
#' @param profundidad_maxima_suelo Numeric. Profundidad maxima del suelo
#'   (m). Por defecto `Inf` (sin tope).
#' @param fecha_inicio Date opcional. Primera fecha de la serie devuelta
#'   (por defecto, la primera fecha disponible en `clima_estacion`; en la
#'   practica deberia ser la fecha de siembra).
#' @param fecha_fin Date opcional. Ultima fecha de la serie devuelta (por
#'   defecto, la ultima fecha disponible en `clima_estacion`).
#'
#' @return Tibble con columnas `date` y `profundidad_radical_m`.
#' @export
calcular_profundidad_radicular <- function(clima_estacion,
                                            fecha_emergencia,
                                            fecha_hito2,
                                            tb_c,
                                            pr_s_e,
                                            pr,
                                            profundidad_maxima_suelo = Inf,
                                            fecha_inicio = NULL,
                                            fecha_fin = NULL) {
  fecha_emergencia <- as.Date(fecha_emergencia)
  fecha_hito2 <- as.Date(fecha_hito2)
  fecha_inicio <- if (is.null(fecha_inicio)) min(clima_estacion$date) else as.Date(fecha_inicio)
  fecha_fin <- if (is.null(fecha_fin)) max(clima_estacion$date) else as.Date(fecha_fin)

  clima <- dplyr::filter(clima_estacion, .data$date >= fecha_inicio, .data$date <= fecha_fin)
  clima <- dplyr::arrange(clima, .data$date)
  clima <- dplyr::mutate(clima, tm = calcular_temperatura_media(.data$tx, .data$tn, .data$tm))

  if (nrow(clima) == 0) {
    rlang::abort("No hay datos climaticos disponibles en el rango solicitado")
  }

  # Unidades termicas de raiz: 0 antes de emergencia, pmax(0, tm - tb_c) desde emergencia
  incr_raiz <- dplyr::if_else(clima$date < fecha_emergencia, 0, pmax(0, clima$tm - tb_c))
  acum_raiz <- cumsum(incr_raiz)

  # Congelar en el valor alcanzado en fecha_hito2 (acum_raiz es monotona no decreciente)
  idx_hasta_hito2 <- which(clima$date <= fecha_hito2)
  acum_en_hito2 <- if (length(idx_hasta_hito2) > 0) acum_raiz[max(idx_hasta_hito2)] else 0
  acum_efectiva <- pmin(acum_raiz, acum_en_hito2)

  profundidad <- dplyr::if_else(
    clima$date < fecha_emergencia,
    pr_s_e,
    pr_s_e + (pr * acum_efectiva) / 100
  )
  profundidad <- pmin(profundidad, profundidad_maxima_suelo)

  tibble::tibble(date = clima$date, profundidad_radical_m = profundidad)
}
