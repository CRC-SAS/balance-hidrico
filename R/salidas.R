#' Numero de eventos de lluvia significativos alrededor de la siembra
#'
#' Cuenta los dias con precipitacion `>= umbral_mm` en la ventana
#' `[fecha_siembra - dias_previos, fecha_siembra + dias_posteriores]`
#' (ambos extremos incluidos).
#'
#' @param clima_estacion Tibble con columnas `date`, `pp` (ver [leer_clima_csv()]).
#' @param fecha_siembra Date o `"YYYY-MM-DD"`.
#' @param umbral_mm Numeric. Umbral diario de lluvia (mm). Default `10`.
#' @param dias_previos,dias_posteriores Integer. Ancho de la ventana antes y
#'   despues de la siembra. Default `14` y `7`.
#'
#' @return Integer. Cantidad de dias con `pp >= umbral_mm` en la ventana.
#' @export
calcular_eventos_lluvia_10mm_14a_7d_siembra <- function(clima_estacion, fecha_siembra,
                                                          umbral_mm = 10,
                                                          dias_previos = 14,
                                                          dias_posteriores = 7) {
  fecha_siembra <- as.Date(fecha_siembra)
  ventana <- dplyr::filter(
    clima_estacion,
    .data$date >= fecha_siembra - dias_previos,
    .data$date <= fecha_siembra + dias_posteriores
  )
  sum(ventana$pp >= umbral_mm, na.rm = TRUE)
}

#' Estado hidrico del suelo el dia de siembra
#'
#' Extrae el agua util (%) por metro y la presencia de "sandwich seco" del
#' dia de siembra, a partir de la serie diaria del balance hidrico (Paso 4)
#' -- son columnas que ya estan calculadas dia a dia en
#' [calcular_balance_hidrico()], esto es una seleccion, no una formula nueva.
#' `au_pct_m1`/`au_pct_m2`/`au_pct_total` vienen como fraccion 0-1 en
#' `serie_diaria_balance` (paridad con el xlsx de referencia); esta funcion
#' las expresa en porcentaje (x100) para esta salida.
#'
#' @param serie_diaria_balance Tibble `serie_diaria` de [calcular_balance_hidrico()].
#' @param fecha_siembra Date o `"YYYY-MM-DD"`.
#'
#' @return Tibble de 1 fila: `au_pct_m1`, `au_pct_m2`, `au_pct_total`
#'   (porcentaje, 0-100), `sandwich_seco`.
#' @export
calcular_estado_hidrico_siembra <- function(serie_diaria_balance, fecha_siembra) {
  fecha_siembra <- as.Date(fecha_siembra)
  fila <- dplyr::filter(serie_diaria_balance, .data$date == fecha_siembra)
  if (nrow(fila) != 1) {
    rlang::abort(glue::glue(
      "No hay exactamente una fila para fecha_siembra={fecha_siembra} en serie_diaria_balance ",
      "(encontradas: {nrow(fila)})"
    ))
  }
  fila <- dplyr::mutate(
    fila,
    au_pct_m1 = .data$au_pct_m1 * 100,
    au_pct_m2 = .data$au_pct_m2 * 100,
    au_pct_total = .data$au_pct_total * 100
  )
  dplyr::select(fila, "au_pct_m1", "au_pct_m2", "au_pct_total", "sandwich_seco")
}

#' Confort hidrico durante el periodo critico
#'
#' `100 * sum(TrR)/sum(DemT)` entre `inicio_periodo_critico` y
#' `fin_periodo_critico` (ambos extremos incluidos), sobre la serie diaria
#' del balance hidrico (Paso 4). Es una agregacion pura sobre columnas ya
#' calculadas, no una formula nueva.
#'
#' @param serie_diaria_balance Tibble `serie_diaria` de [calcular_balance_hidrico()].
#' @param hitos Tibble de 1 fila, `hitos` de [calcular_fenologia()] (usa
#'   `inicio_periodo_critico`, `fin_periodo_critico`).
#'
#' @return Numeric, porcentaje (0-100 en el caso tipico). `NA_real_` si
#'   `sum(DemT)` en la ventana es 0 (demanda transpirativa nula, cociente
#'   indefinido).
#' @export
calcular_confort_hidrico <- function(serie_diaria_balance, hitos) {
  ventana <- dplyr::filter(
    serie_diaria_balance,
    .data$date >= hitos$inicio_periodo_critico,
    .data$date <= hitos$fin_periodo_critico
  )
  demt_total <- sum(ventana$demt, na.rm = TRUE)
  if (demt_total == 0) return(NA_real_)
  100 * sum(ventana$trr, na.rm = TRUE) / demt_total
}

#' Salidas (Paso 5): reporte combinado de un escenario
#'
#' Junta las 3 salidas del metodo CRC-SAS para un escenario ya simulado
#' (Pasos 1 y 4): eventos de lluvia pre-siembra, estado hidrico a la
#' siembra y confort hidrico en el periodo critico.
#'
#' @param clima_estacion Tibble con columnas `date`, `pp`.
#' @param fecha_siembra Date o `"YYYY-MM-DD"`.
#' @param hitos Tibble de 1 fila, `hitos` de [calcular_fenologia()].
#' @param serie_diaria_balance Tibble `serie_diaria` de [calcular_balance_hidrico()].
#'
#' @return Lista: `eventos_lluvia_10mm_14a_7d_siembra` (integer),
#'   `estado_hidrico_siembra` (tibble de 1 fila, `au_pct_*` en porcentaje),
#'   `confort_hidrico` (numeric, porcentaje).
#' @export
calcular_salidas <- function(clima_estacion, fecha_siembra, hitos, serie_diaria_balance) {
  list(
    eventos_lluvia_10mm_14a_7d_siembra = calcular_eventos_lluvia_10mm_14a_7d_siembra(clima_estacion, fecha_siembra),
    estado_hidrico_siembra = calcular_estado_hidrico_siembra(serie_diaria_balance, fecha_siembra),
    confort_hidrico = calcular_confort_hidrico(serie_diaria_balance, hitos)
  )
}
