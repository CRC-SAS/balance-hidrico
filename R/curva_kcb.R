#' Curva de Kcb (Paso 3)
#'
#' Implementa la Seccion 6 del documento maestro: `kcb_ini` constante hasta
#' `ut_fkcbini`, rampa lineal hasta `ut_ikcbmax` (en funcion de la serie de
#' unidades termicas **sin** ajuste de fotoperiodo, ver duda KC-2), y
#' `kcb_max` constante desde ahi hasta madurez fisiologica. Que `kcb_max`
#' se mantenga constante (sin declinar) hasta madurez fisiologica es un
#' comportamiento confirmado como intencional, no un vacio de la
#' especificacion (duda KC-1): el output relevante de la herramienta se
#' calcula solo hasta el fin del periodo critico, por lo que una eventual
#' caida de Kcb en la fase de senescencia no afecta ningun resultado.
#'
#' @param serie_ut_simple Tibble con columnas `date` y `ut_simple_acum`,
#'   tal como devuelve el elemento `serie_diaria` de [calcular_fenologia()].
#' @param ut_fkcbini Numeric. Umbral de UT (sin Fp) al que termina el Kcb
#'   inicial.
#' @param ut_ikcbmax Numeric. Umbral de UT (sin Fp) al que empieza el Kcb
#'   maximo.
#' @param kcb_ini Numeric. Valor de Kcb inicial.
#' @param kcb_max Numeric. Valor de Kcb maximo.
#'
#' @return Tibble con columnas `date` y `kcb`.
#' @export
calcular_curva_kcb <- function(serie_ut_simple, ut_fkcbini, ut_ikcbmax, kcb_ini, kcb_max) {
  ut <- serie_ut_simple$ut_simple_acum

  kcb <- dplyr::case_when(
    ut <= ut_fkcbini ~ kcb_ini,
    ut >= ut_ikcbmax ~ kcb_max,
    TRUE ~ kcb_ini + (kcb_max - kcb_ini) * (ut - ut_fkcbini) / (ut_ikcbmax - ut_fkcbini)
  )

  tibble::tibble(date = serie_ut_simple$date, kcb = kcb)
}
