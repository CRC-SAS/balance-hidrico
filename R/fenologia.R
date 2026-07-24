#' Encontrar la primera fecha en que una serie acumulada alcanza un umbral
#'
#' Equivalente a la resolucion de fechas por `COUNTIFS + INDEX` de la hoja
#' `fenologia` del xlsx de referencia: la serie acumulada es monotona no
#' decreciente (los incrementos diarios nunca son negativos), asi que el
#' primer indice que supera el umbral es unico y bien definido.
#'
#' @param fecha Vector de fechas (Date), ordenado.
#' @param acumulado Vector numeric de igual longitud, monotono no decreciente.
#' @param umbral Numeric. Umbral a alcanzar.
#'
#' @return Date. La primera fecha en que `acumulado >= umbral`, o `NA` (con
#'   clase Date) si el umbral nunca se alcanza con los datos disponibles.
#' @keywords internal
#' @noRd
.fecha_en_umbral <- function(fecha, acumulado, umbral) {
  idx <- which(acumulado >= umbral)[1]
  if (is.na(idx)) return(as.Date(NA))
  fecha[idx]
}

#' Fenologia de trigo, maiz o soja (metodo CRC-SAS)
#'
#' Dispatcher que delega en [calcular_fenologia_trigo()],
#' [calcular_fenologia_maiz()] o [calcular_fenologia_soja()] segun
#' `cultivo`. Implementa la Seccion 4 del documento maestro
#' (`docs/documento_maestro_fenologia_balance_hidrico.md`), ya verificada
#' contra el xlsx de referencia (`docs/v2/`).
#'
#' @param cultivo Character. Uno de `"trigo"`, `"maiz"`, `"soja"`.
#' @param cultivar Character. Cultivar dentro de `cultivo` (ver
#'   `inst/extdata/parametros_ejemplo.yml`).
#' @param clima_estacion Tibble de una unica estacion, con columnas
#'   `station_id`, `date`, `doy`, `tx`, `tn`, `tm` (puede tener `NA`, se
#'   recalcula), tal como devuelve [leer_clima_csv()].
#' @param fecha_siembra Date (o character `"YYYY-MM-DD"`). Fecha de siembra.
#' @param parametros Lista devuelta por [leer_parametros_yaml()].
#'
#' @return Lista con dos elementos:
#'   - `hitos`: tibble de una fila con las fechas de siembra, emergencia,
#'     fin de Kcb inicial, inicio de Kcb maximo, hito1/hito2 (cuaje de
#'     granos: ET/Z71 en trigo, R2/R2 en maiz, R1/R5 en soja, con
#'     `nombre_hito1`/`nombre_hito2` indicando cual es cada uno), inicio y
#'     fin del periodo critico, y madurez fisiologica.
#'   - `serie_diaria`: tibble con la serie diaria (desde emergencia en
#'     adelante) de unidades termicas acumuladas **sin** ajuste de
#'     fotoperiodo (`ut_simple_acum`), que es la serie que consume
#'     [calcular_curva_kcb()] (ver duda KC-2).
#' @export
calcular_fenologia <- function(cultivo, cultivar, clima_estacion, fecha_siembra, parametros) {
  cultivo <- match.arg(cultivo, c("trigo", "maiz", "soja"))
  fecha_siembra <- as.Date(fecha_siembra)

  station_ids <- unique(clima_estacion$station_id)
  if (length(station_ids) != 1) {
    rlang::abort("clima_estacion debe contener datos de una unica estacion")
  }
  latitud <- obtener_latitud_estacion(parametros, station_ids)
  params_cultivar <- obtener_parametros_cultivo(parametros, cultivo, cultivar)

  clima_prep <- dplyr::filter(clima_estacion, .data$date >= fecha_siembra)
  clima_prep <- dplyr::arrange(clima_prep, .data$date)
  clima_prep <- dplyr::mutate(
    clima_prep,
    tm = calcular_temperatura_media(.data$tx, .data$tn, .data$tm),
    fp = calcular_fotoperiodo(.data$doy, latitud)
  )

  if (nrow(clima_prep) == 0) {
    rlang::abort("No hay datos climaticos disponibles a partir de la fecha de siembra")
  }

  fn <- switch(cultivo,
    trigo = calcular_fenologia_trigo,
    maiz  = calcular_fenologia_maiz,
    soja  = calcular_fenologia_soja
  )

  fn(clima_prep, fecha_siembra, params_cultivar)
}

#' Fenologia de trigo
#'
#' El trigo responde al fotoperiodo (dia largo, factor cuadratico centrado
#' en 20 h, modulado por `rcf`) unicamente entre Emergencia y Espiguilla
#' Terminal (ET, hito1); a partir de ahi es insensible (F-6). Z71 (hito2,
#' cuaje de granos) y fin de periodo critico (fPC) son ambos relativos a
#' ET (`ET+700` y `ET+800`, distintos entre si, ver F-1); madurez
#' fisiologica es relativa a fPC (`fPC+400`).
#'
#' @param clima_prep Tibble ya filtrado desde la siembra en adelante, con
#'   columnas `date`, `doy`, `tm` (ya resuelta) y `fp` (ya calculado).
#' @param fecha_siembra Date.
#' @param params Lista de parametros del cultivar (`tb_a`, `rcf`, `ut_s_e`,
#'   `ut_e_fkcbini`, `ut_e_ikcbmax`, `ut_e_et`, `ut_et_ipc`, `ut_et_z71`,
#'   `ut_et_fpc`, `ut_fpc_mf`).
#'
#' @return Ver [calcular_fenologia()].
#' @export
calcular_fenologia_trigo <- function(clima_prep, fecha_siembra, params) {
  tb_a <- params$tb_a
  rcf <- params$rcf

  # --- Siembra -> Emergencia ---
  incr_s_e <- pmax(0, clima_prep$tm - tb_a)
  acum_s_e <- cumsum(incr_s_e)
  fecha_emergencia <- .fecha_en_umbral(clima_prep$date, acum_s_e, params$ut_s_e)
  if (is.na(fecha_emergencia)) {
    rlang::abort("No hay suficientes datos climaticos para alcanzar la emergencia")
  }

  post_e <- clima_prep[clima_prep$date >= fecha_emergencia, ]

  # --- Emergencia -> serie simple (sin Fp): fin Kcb inicial, inicio Kcb maximo ---
  incr_simple <- pmax(0, post_e$tm - tb_a)
  acum_simple <- cumsum(incr_simple)
  fecha_fkcbini <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_fkcbini)
  fecha_ikcbmax <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_ikcbmax)

  # --- Emergencia -> Espiguilla Terminal (hito1), ajustada por Fp y RCF ---
  factor_fp <- pmax(0, 1 - (((20 - pmin(20, post_e$fp))^2) * 0.01 * rcf))
  incr_hito1 <- incr_simple * factor_fp
  acum_hito1 <- cumsum(incr_hito1)
  fecha_et <- .fecha_en_umbral(post_e$date, acum_hito1, params$ut_e_et)
  if (is.na(fecha_et)) {
    rlang::abort("No hay suficientes datos climaticos para alcanzar espiguilla terminal (ET)")
  }

  # --- Desde ET: insensible al Fp. Z71, iPC, fPC y MF sobre la misma serie ---
  post_et <- clima_prep[clima_prep$date >= fecha_et, ]
  incr_post_et <- pmax(0, post_et$tm - tb_a)
  acum_post_et <- cumsum(incr_post_et)

  fecha_ipc <- .fecha_en_umbral(post_et$date, acum_post_et, params$ut_et_ipc)
  fecha_z71 <- .fecha_en_umbral(post_et$date, acum_post_et, params$ut_et_z71)
  fecha_fpc <- .fecha_en_umbral(post_et$date, acum_post_et, params$ut_et_fpc)
  fecha_mf  <- .fecha_en_umbral(post_et$date, acum_post_et, params$ut_et_fpc + params$ut_fpc_mf)

  list(
    hitos = tibble::tibble(
      siembra = fecha_siembra,
      emergencia = fecha_emergencia,
      fin_kcb_inicial = fecha_fkcbini,
      inicio_kcb_maximo = fecha_ikcbmax,
      hito1 = fecha_et, nombre_hito1 = "ET",
      hito2 = fecha_z71, nombre_hito2 = "Z71",
      inicio_periodo_critico = fecha_ipc,
      fin_periodo_critico = fecha_fpc,
      madurez_fisiologica = fecha_mf
    ),
    serie_diaria = tibble::tibble(
      date = post_e$date, doy = post_e$doy, tm = post_e$tm, fp = post_e$fp,
      ut_simple_acum = acum_simple
    )
  )
}

#' Fenologia de maiz
#'
#' El maiz no responde al fotoperiodo (F-6). Toda la fenologia posterior a
#' la emergencia (fin Kcb inicial, inicio Kcb maximo, inicio de periodo
#' critico, R2/cuaje de granos -que es a la vez hito1 y hito2-, fin de
#' periodo critico y madurez fisiologica) se resuelve sobre una unica
#' serie acumulada de unidades termicas (base `tb_b`), cada una en su
#' propio umbral absoluto tomado del cultivar.
#'
#' @param clima_prep,fecha_siembra Ver [calcular_fenologia_trigo()].
#' @param params Lista de parametros del cultivar (`tb_a`, `tb_b`,
#'   `ut_s_e`, `ut_e_fkcbini`, `ut_e_ikcbmax`, `ut_e_r2`, `ut_e_ipc`,
#'   `ut_e_fpc`, `ut_r2_mf`).
#'
#' @return Ver [calcular_fenologia()].
#' @export
calcular_fenologia_maiz <- function(clima_prep, fecha_siembra, params) {
  tb_a <- params$tb_a
  tb_b <- params$tb_b

  # --- Siembra -> Emergencia ---
  incr_s_e <- pmax(0, clima_prep$tm - tb_a)
  acum_s_e <- cumsum(incr_s_e)
  fecha_emergencia <- .fecha_en_umbral(clima_prep$date, acum_s_e, params$ut_s_e)
  if (is.na(fecha_emergencia)) {
    rlang::abort("No hay suficientes datos climaticos para alcanzar la emergencia")
  }

  post_e <- clima_prep[clima_prep$date >= fecha_emergencia, ]

  # --- Emergencia en adelante: una unica serie (sin Fp) para todos los hitos ---
  incr_simple <- pmax(0, post_e$tm - tb_b)
  acum_simple <- cumsum(incr_simple)

  fecha_fkcbini <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_fkcbini)
  fecha_ikcbmax <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_ikcbmax)
  fecha_ipc     <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_ipc)
  fecha_r2      <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_r2)
  fecha_fpc     <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_fpc)
  fecha_mf      <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_r2 + params$ut_r2_mf)

  list(
    hitos = tibble::tibble(
      siembra = fecha_siembra,
      emergencia = fecha_emergencia,
      fin_kcb_inicial = fecha_fkcbini,
      inicio_kcb_maximo = fecha_ikcbmax,
      hito1 = fecha_r2, nombre_hito1 = "R2",
      hito2 = fecha_r2, nombre_hito2 = "R2",
      inicio_periodo_critico = fecha_ipc,
      fin_periodo_critico = fecha_fpc,
      madurez_fisiologica = fecha_mf
    ),
    serie_diaria = tibble::tibble(
      date = post_e$date, doy = post_e$doy, tm = post_e$tm, fp = post_e$fp,
      ut_simple_acum = acum_simple
    )
  )
}

#' Fenologia de soja
#'
#' La soja responde al fotoperiodo (dia corto, umbral `fpu_e_r1` /
#' `fpu_r1_mf` segun etapa y cultivar, penalizacion lineal de 0.3) desde
#' Emergencia hasta Madurez Fisiologica, y tiene una temperatura optima
#' (`to_a`) por encima de la cual las UT diarias no siguen aumentando.
#' `UT_R1-R5` es siempre 300 (F-3): iPC, R5 (hito2, cuaje), fPC y MF se
#' resuelven sobre la misma serie acumulada iniciada en R1 (hito1).
#'
#' @param clima_prep,fecha_siembra Ver [calcular_fenologia_trigo()].
#' @param params Lista de parametros del cultivar (`tb_a`, `tb_b`, `to_a`,
#'   `fpu_e_r1`, `fpu_r1_mf`, `ut_s_e`, `ut_e_fkcbini`, `ut_e_ikcbmax`,
#'   `ut_e_r1`, `ut_r1_ipc`, `ut_r1_r5`, `ut_r5_fpc`, `ut_r5_mf`).
#'
#' @return Ver [calcular_fenologia()].
#' @export
calcular_fenologia_soja <- function(clima_prep, fecha_siembra, params) {
  tb_a <- params$tb_a
  tb_b <- params$tb_b
  to_a <- params$to_a

  # --- Siembra -> Emergencia (con tope de temperatura optima) ---
  incr_s_e <- pmax(0, pmin(clima_prep$tm, to_a) - tb_a)
  acum_s_e <- cumsum(incr_s_e)
  fecha_emergencia <- .fecha_en_umbral(clima_prep$date, acum_s_e, params$ut_s_e)
  if (is.na(fecha_emergencia)) {
    rlang::abort("No hay suficientes datos climaticos para alcanzar la emergencia")
  }

  post_e <- clima_prep[clima_prep$date >= fecha_emergencia, ]

  # --- Emergencia -> serie simple (sin Fp): fin Kcb inicial, inicio Kcb maximo ---
  incr_simple <- pmax(0, pmin(post_e$tm, to_a) - tb_b)
  acum_simple <- cumsum(incr_simple)
  fecha_fkcbini <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_fkcbini)
  fecha_ikcbmax <- .fecha_en_umbral(post_e$date, acum_simple, params$ut_e_ikcbmax)

  # --- Emergencia -> R1 (hito1), penalizada por Fp por encima de fpu_e_r1 ---
  factor_fpu_e_r1 <- pmin(1, pmax(0, 1 - pmax(0, post_e$fp - params$fpu_e_r1) * 0.3))
  incr_hito1 <- incr_simple * factor_fpu_e_r1
  acum_hito1 <- cumsum(incr_hito1)
  fecha_r1 <- .fecha_en_umbral(post_e$date, acum_hito1, params$ut_e_r1)
  if (is.na(fecha_r1)) {
    rlang::abort("No hay suficientes datos climaticos para alcanzar R1")
  }

  # --- Desde R1: iPC, R5 (hito2), fPC y MF sobre la misma serie, penalizada por fpu_r1_mf ---
  post_r1 <- clima_prep[clima_prep$date >= fecha_r1, ]
  incr_post_r1_base <- pmax(0, pmin(post_r1$tm, to_a) - tb_b)
  factor_fpu_r1_mf <- pmin(1, pmax(0, 1 - pmax(0, post_r1$fp - params$fpu_r1_mf) * 0.3))
  incr_post_r1 <- incr_post_r1_base * factor_fpu_r1_mf
  acum_post_r1 <- cumsum(incr_post_r1)

  fecha_ipc <- .fecha_en_umbral(post_r1$date, acum_post_r1, params$ut_r1_ipc)
  fecha_r5  <- .fecha_en_umbral(post_r1$date, acum_post_r1, params$ut_r1_r5)
  fecha_fpc <- .fecha_en_umbral(post_r1$date, acum_post_r1, params$ut_r1_r5 + params$ut_r5_fpc)
  fecha_mf  <- .fecha_en_umbral(post_r1$date, acum_post_r1, params$ut_r1_r5 + params$ut_r5_mf)

  list(
    hitos = tibble::tibble(
      siembra = fecha_siembra,
      emergencia = fecha_emergencia,
      fin_kcb_inicial = fecha_fkcbini,
      inicio_kcb_maximo = fecha_ikcbmax,
      hito1 = fecha_r1, nombre_hito1 = "R1",
      hito2 = fecha_r5, nombre_hito2 = "R5",
      inicio_periodo_critico = fecha_ipc,
      fin_periodo_critico = fecha_fpc,
      madurez_fisiologica = fecha_mf
    ),
    serie_diaria = tibble::tibble(
      date = post_e$date, doy = post_e$doy, tm = post_e$tm, fp = post_e$fp,
      ut_simple_acum = acum_simple
    )
  )
}
