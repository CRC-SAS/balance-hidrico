#' Contenido hidrico inicial por horizonte (dia 1)
#'
#' `CH_i = (CC_i - PMP_i) * AU_i + PMP_i`, con `AU_i` (fraccion 0-1) igual a
#' `au_inicial_m1` para los horizontes 1-4 (hasta 0.9 m) y `au_inicial_m2`
#' para los horizontes 5-8 (0.9-2.1 m), salvo que `sandwich_seco_inicial`
#' sea `TRUE`, en cuyo caso el horizonte 4 (0.6-0.9 m) se fuerza a 10% de AU
#' fijo, independientemente de `au_inicial_m1` (confirmado por CRC-SAS
#' 2026-08-01).
#'
#' @noRd
.contenido_hidrico_inicial <- function(pmp_mm, cc_mm, au_inicial_m1, au_inicial_m2,
                                        sandwich_seco_inicial) {
  ini_frac <- c(rep(au_inicial_m1, 4), rep(au_inicial_m2, 4))
  if (isTRUE(sandwich_seco_inicial)) ini_frac[4] <- 0.10
  (cc_mm - pmp_mm) * ini_frac + pmp_mm
}

#' Escorrentia e infiltracion del dia
#'
#' `Absi = 0.15*(Sat1-max(CH1,PMP1))/(Sat1-PMP1)`,
#' `Esc = max(0, Pp-Absi*AtM)^2 / (Pp+AtM*(1-Absi))`, `Inf = Pp - Esc`.
#'
#' @noRd
.escorrentia_infiltracion <- function(pp, ch1, pmp1_mm, sat1_mm, atm) {
  absi <- 0.15 * (sat1_mm - max(ch1, pmp1_mm)) / (sat1_mm - pmp1_mm)
  esc <- max(0, pp - absi * atm)^2 / (pp + atm * (1 - absi))
  list(absi = absi, esc = esc, inf = pp - esc)
}

#' Limitacion hidrica a la profundizacion radicular (LHPR)
#'
#' Segun el horizonte hacia el que avanza el frente radicular (comparando la
#' `PRE` de ayer contra los limites `pfh_m` del suelo): si todavia esta en el
#' horizonte 1, LHPR=1 (sin restriccion); si avanza hacia el horizonte `j`
#' (2-8), LHPR es la disponibilidad hidrica de ESE horizonte hoy, acotada a
#' 1; si ya supero el horizonte 8, LHPR=0 (sin mas suelo para profundizar).
#'
#' @noRd
.limitacion_hidrica_pr <- function(pre_ayer, ch_hoy, pmp_mm, cc_mm, pfh_m) {
  j <- which(pre_ayer < pfh_m)[1]
  if (is.na(j)) return(0)
  if (j == 1) return(1)
  min(1, (ch_hoy[j] - pmp_mm[j]) / (0.3 * (cc_mm[j] - pmp_mm[j])))
}

#' Profundidad radical efectiva (PRE) del dia
#'
#' `PRP` es la curva potencial (Paso 2). Antes de que `PRP` supere 0.2 m,
#' `PRE=0`; en el instante exacto en que `PRP=0.2` (piso siembra-emergencia),
#' `PRE=0.2`; despues, `PRE` acumula el incremento diario de `PRP` limitado
#' por `LHPR`. No lleva tope `MIN` contra la curva potencial (confirmado por
#' CRC-SAS 2026-08-01: no hace falta, `LHPR` siempre es `<=1`).
#'
#' @noRd
.profundidad_radical_efectiva <- function(prp_hoy, prp_ayer, pre_ayer, lhpr) {
  prp_incremento <- if (prp_hoy > 0.2) prp_hoy - prp_ayer else 0
  pre <- if (prp_hoy < 0.2) {
    0
  } else if (prp_hoy == 0.2) {
    0.2
  } else {
    pre_ayer + prp_incremento * lhpr
  }
  list(prp_incremento = prp_incremento, pre = pre)
}

#' Demanda hidrica diaria (transpirativa y evaporativa)
#'
#' `DemT = Eto*Kcb`, `DemE = max(0, Eto*max(0,1-Kcb)*Rastrojo)`.
#'
#' @noRd
.demanda_hidrica <- function(eto, kcb, rastrojo) {
  list(demt = eto * kcb, deme = max(0, eto * max(0, 1 - kcb) * rastrojo))
}

#' Agua transpirable y transpiracion real, por horizonte
#'
#' `AT_i` pondera el agua por encima de PMP por la facilidad de extraccion
#' del suelo (`kl`), que decrece por debajo del umbral `Um`, y por la
#' fraccion del horizonte efectivamente explorada por las raices (segun
#' `PRE` de hoy). `TrR = min(DemT, AT+Inf)`; el remanente sobre la
#' infiltracion (`TrRR`) se reparte entre horizontes proporcional a `AT_i`.
#'
#' @noRd
.agua_transpirable_y_transpiracion_real <- function(ch_hoy, pmp_mm, cc_mm, pfh_m,
                                                      kl, um, pre_hoy, demt, inf) {
  n_h <- length(ch_hoy)
  frac_explorada <- numeric(n_h)
  frac_explorada[1] <- min(1, pre_hoy / pfh_m[1])
  for (i in seq(2, n_h)) {
    frac_explorada[i] <- min(1, max(0, pre_hoy - pfh_m[i - 1]) / (pfh_m[i] - pfh_m[i - 1]))
  }

  at_i <- pmax(0, (ch_hoy - pmp_mm) * kl * pmin(1, (ch_hoy - pmp_mm) / (um * (cc_mm - pmp_mm)))) * frac_explorada
  at_total <- sum(at_i)
  trr <- min(demt, at_total + inf)
  trrr <- max(0, trr - inf)
  trr_i <- if (at_total > 0) trrr * (at_i / at_total) else rep(0, n_h)

  list(at_i = at_i, at_total = at_total, trr = trr, trrr = trrr, trr_i = trr_i)
}

#' Evaporacion real del suelo (dos etapas)
#'
#' `AEF` (agua evaporable facil) y `AER` (remanente); `ER` acumula `AEF` mas
#' una fraccion de `AER` que cae con la 4ta potencia a medida que el
#' horizonte superficial se acerca al punto de marchitez. La base de esa
#' potencia se acota explicitamente a `[0,1]` antes de exponenciar (pedido
#' por CRC-SAS 2026-08-01: la formula original del xlsx no la acota, pero
#' con parametros validos no deberia hacer falta -- se agrega como
#' salvaguarda).
#'
#' @noRd
.evaporacion_real <- function(deme, ch1_hoy, inf, trr, trr1, pmp1_mm, cc1_mm, u, rastrojo) {
  aef <- min(deme, max(0, ch1_hoy - (cc1_mm - u * rastrojo)) + max(0, inf - trr))
  aer <- deme - aef
  base <- (inf + ch1_hoy - trr1 - aef - pmp1_mm * 0.5) / (cc1_mm - u * rastrojo - pmp1_mm * 0.5)
  base <- pmin(pmax(base, 0), 1)
  er <- aef + min(aer, aer * base^4)
  list(aef = aef, aer = aer, er = er)
}

#' Drenaje interno y contenido hidrico final, por horizonte
#'
#' Cascada horizonte por horizonte (1 a 8, en ese orden -- cada uno depende
#' del contenido final y del excedente del horizonte inmediato superior
#' calculados el mismo dia): `CHv_i` es el contenido tras extraer
#' transpiracion (y, solo en el horizonte 1, evaporacion); `Dr_i` es el
#' excedente sobre capacidad de campo que drena a tasa `DR`; `CHf_i` (Cf)
#' suma lo que entra desde el horizonte de arriba (`Dr` + excedente sobre
#' saturacion `Me`); `Me_i` es el excedente sobre saturacion de `CHf_i`. El
#' horizonte 1 no resta su propio `Me` el mismo dia (no tiene horizonte por
#' encima que lo trunque) -- confirmado correcto por CRC-SAS 2026-08-01.
#'
#' @noRd
.drenaje_y_contenido_final <- function(ch_hoy, trr_i_hoy, er, cc_mm, sat_mm, dr, inf, trrr, trr1) {
  n_h <- length(ch_hoy)
  chv <- ch_hoy - trr_i_hoy
  chv[1] <- chv[1] - er

  dr_h <- pmax(0, (chv - cc_mm) * dr)

  cf <- numeric(n_h)
  me <- numeric(n_h)
  cf[1] <- chv[1] - dr_h[1] + max(0, inf - trrr - er)
  me[1] <- max(0, cf[1] - sat_mm[1])
  for (i in seq(2, n_h)) {
    cf[i] <- chv[i] - dr_h[i] + dr_h[i - 1] + me[i - 1]
    me[i] <- max(0, cf[i] - sat_mm[i])
  }

  list(chv = chv, dr_h = dr_h, cf = cf, me = me)
}

#' Balance hidrico diario del suelo (Paso 4)
#'
#' Simula dia a dia el contenido hidrico del suelo (8 horizontes) a partir
#' de la oferta (precipitacion, agua inicial) y la demanda (evapotranspira-
#' cion potencial ponderada por la curva de Kcb), siguiendo el metodo de
#' CRC-SAS -- formulas verificadas celda por celda contra la hoja
#' `balance hídrico` de `documentacion/referencias/v3/Calculos fenologia y
#' balance hidrico.xlsx`. El calculo es secuencial (el estado de cada dia
#' depende del dia anterior), no vectorizable entre dias.
#'
#' @param clima_estacion Tibble de una estacion con columnas `date`, `pp`,
#'   `eto` (ver [leer_clima_csv()]).
#' @param fecha_inicio Date o `"YYYY-MM-DD"`. Primer dia simulado (fecha de
#'   la condicion hidrica inicial).
#' @param serie_profundidad_radicular Tibble `date`, `profundidad_radical_m`
#'   (curva potencial, Paso 2 -- ver [calcular_profundidad_radicular()]).
#' @param serie_kcb Tibble `date`, `kcb` (Paso 3 -- ver [calcular_curva_kcb()]).
#' @param suelo Lista `list(cn, kl, um, u, dr, horizontes)`, con
#'   `horizontes` un tibble de 8 filas (`nombre`, `pfh_m`, `pmp`, `cc`,
#'   `sat`) -- ver [obtener_suelo_balance_hidrico()].
#' @param rastrojo_clase Character. Una de `names(constantes$rastrojo)`
#'   (p.ej. `"Moderada"`).
#' @param humedad_inicial_clase_m1,humedad_inicial_clase_m2 Character. Una
#'   de `names(constantes$humedad_inicial)` (p.ej. `"Hu"`), para el primer y
#'   segundo metro del suelo respectivamente, en `fecha_inicio`.
#' @param constantes Lista devuelta por [leer_constantes_yaml()].
#' @param sandwich_seco_inicial Logical. Si hay "sandwich seco" presente en
#'   la condicion inicial, el horizonte 4 (0.6-0.9 m) se fuerza a 10% de AU
#'   sin importar `humedad_inicial_clase_m1`. Default `FALSE`. Distinto de
#'   la columna `sandwich_seco` de la salida, que se recalcula dia a dia.
#'
#' @return Lista con un elemento `serie_diaria`: tibble con una fila por dia
#'   desde `fecha_inicio`, columnas escalares (`absi`, `esc`, `inf`,
#'   `drenaje_profundo`, `demt`, `deme`, `au_mm_m1`, `au_mm_m2`,
#'   `au_mm_total`, `au_pct_m1`, `au_pct_m2`, `au_pct_total`,
#'   `sandwich_seco`, `prp_incremento`, `lhpr`, `pre_m`, `at`, `trr`,
#'   `trrr`, `aef`, `aer`, `er`) mas columnas por horizonte sufijadas
#'   `_1`..`_8` para `ch`, `at`, `tr`, `chv`, `drenaje_horizonte`, `chf`,
#'   `me`.
#' @export
calcular_balance_hidrico <- function(clima_estacion,
                                      fecha_inicio,
                                      serie_profundidad_radicular,
                                      serie_kcb,
                                      suelo,
                                      rastrojo_clase,
                                      humedad_inicial_clase_m1,
                                      humedad_inicial_clase_m2,
                                      constantes,
                                      sandwich_seco_inicial = FALSE) {
  rastrojo <- obtener_factor_rastrojo(constantes, rastrojo_clase)
  au_inicial_m1 <- obtener_fraccion_humedad_inicial(constantes, humedad_inicial_clase_m1)
  au_inicial_m2 <- obtener_fraccion_humedad_inicial(constantes, humedad_inicial_clase_m2)

  fecha_inicio <- as.Date(fecha_inicio)

  horiz <- suelo$horizontes
  n_h <- nrow(horiz)
  pfh_m <- horiz$pfh_m
  espesor_m <- diff(c(0, pfh_m))
  pmp_mm <- horiz$pmp * espesor_m * 1000
  cc_mm <- horiz$cc * espesor_m * 1000
  sat_mm <- horiz$sat * espesor_m * 1000

  cn <- suelo$cn
  kl <- suelo$kl
  um <- suelo$um
  u <- suelo$u
  dr <- suelo$dr
  atm <- 254 * (100 / cn - 1)

  serie <- dplyr::filter(clima_estacion, .data$date >= fecha_inicio)
  serie <- dplyr::left_join(serie, serie_profundidad_radicular, by = "date")
  serie <- dplyr::left_join(serie, serie_kcb, by = "date")
  serie <- dplyr::arrange(serie, .data$date)
  # Si fecha_inicio es anterior al comienzo de las series de Paso 1/2 (p.ej.
  # antes de la emergencia, que es cuando arranca calcular_fenologia()), no
  # hay match en el join -- significa que todavia no hay cultivo, mismo
  # criterio que el xlsx (celda en blanco = 0) para Prof/Kcb.
  serie <- dplyr::mutate(
    serie,
    profundidad_radical_m = dplyr::if_else(is.na(.data$profundidad_radical_m), 0, .data$profundidad_radical_m),
    kcb = dplyr::if_else(is.na(.data$kcb), 0, .data$kcb)
  )
  n <- nrow(serie)

  ch <- matrix(NA_real_, n, n_h)
  at_i_mat <- matrix(NA_real_, n, n_h)
  trr_i_mat <- matrix(NA_real_, n, n_h)
  chv_mat <- matrix(NA_real_, n, n_h)
  dr_h_mat <- matrix(NA_real_, n, n_h)
  cf_mat <- matrix(NA_real_, n, n_h)
  me_mat <- matrix(NA_real_, n, n_h)

  absi <- esc <- inf <- drenaje_profundo <- demt <- deme <- numeric(n)
  au_mm_m1 <- au_mm_m2 <- au_mm_total <- numeric(n)
  au_pct_m1 <- au_pct_m2 <- au_pct_total <- numeric(n)
  sandwich_seco <- character(n)
  prp_incremento <- lhpr <- pre_m <- numeric(n)
  at_total <- trr <- trrr <- aef <- aer <- er <- numeric(n)

  suma_pmp_m1 <- sum(pmp_mm[1:4])
  suma_pmp_m2 <- sum(pmp_mm[5:8])
  suma_cc_m1 <- sum(cc_mm[1:4])
  suma_cc_m2 <- sum(cc_mm[5:8])
  suma_pmp_tot <- sum(pmp_mm)
  suma_cc_tot <- sum(cc_mm)

  prp_ayer <- 0
  pre_ayer <- 0

  for (t in seq_len(n)) {
    pp <- serie$pp[t]
    eto <- serie$eto[t]
    prp_hoy <- serie$profundidad_radical_m[t]
    kcb <- serie$kcb[t]

    if (t == 1) {
      ch[t, ] <- .contenido_hidrico_inicial(pmp_mm, cc_mm, au_inicial_m1, au_inicial_m2, sandwich_seco_inicial)
    } else {
      ch[t, ] <- pmin(sat_mm, cf_mat[t - 1, ])
    }

    ei <- .escorrentia_infiltracion(pp, ch[t, 1], pmp_mm[1], sat_mm[1], atm)
    absi[t] <- ei$absi
    esc[t] <- ei$esc
    inf[t] <- ei$inf

    lhpr[t] <- .limitacion_hidrica_pr(pre_ayer, ch[t, ], pmp_mm, cc_mm, pfh_m)
    pre <- .profundidad_radical_efectiva(prp_hoy, prp_ayer, pre_ayer, lhpr[t])
    prp_incremento[t] <- pre$prp_incremento
    pre_m[t] <- pre$pre

    dh <- .demanda_hidrica(eto, kcb, rastrojo)
    demt[t] <- dh$demt
    deme[t] <- dh$deme

    atr <- .agua_transpirable_y_transpiracion_real(
      ch[t, ], pmp_mm, cc_mm, pfh_m, kl, um, pre_m[t], demt[t], inf[t]
    )
    at_i_mat[t, ] <- atr$at_i
    at_total[t] <- atr$at_total
    trr[t] <- atr$trr
    trrr[t] <- atr$trrr
    trr_i_mat[t, ] <- atr$trr_i

    ev <- .evaporacion_real(deme[t], ch[t, 1], inf[t], trr[t], trr_i_mat[t, 1], pmp_mm[1], cc_mm[1], u, rastrojo)
    aef[t] <- ev$aef
    aer[t] <- ev$aer
    er[t] <- ev$er

    dcf <- .drenaje_y_contenido_final(
      ch[t, ], trr_i_mat[t, ], er[t], cc_mm, sat_mm, dr, inf[t], trrr[t], trr_i_mat[t, 1]
    )
    chv_mat[t, ] <- dcf$chv
    dr_h_mat[t, ] <- dcf$dr_h
    cf_mat[t, ] <- dcf$cf
    me_mat[t, ] <- dcf$me

    drenaje_profundo[t] <- dr_h_mat[t, n_h] + me_mat[t, n_h]

    au_mm_m1[t] <- sum(ch[t, 1:4]) - suma_pmp_m1
    au_mm_m2[t] <- sum(ch[t, 5:8]) - suma_pmp_m2
    au_mm_total[t] <- au_mm_m1[t] + au_mm_m2[t]
    au_pct_m1[t] <- au_mm_m1[t] / (suma_cc_m1 - suma_pmp_m1)
    au_pct_m2[t] <- au_mm_m2[t] / (suma_cc_m2 - suma_pmp_m2)
    au_pct_total[t] <- au_mm_total[t] / (suma_cc_tot - suma_pmp_tot)
    sandwich_seco[t] <- if ((ch[t, 4] - pmp_mm[4]) / (cc_mm[4] - pmp_mm[4]) < 0.3) "Si" else "No"

    prp_ayer <- prp_hoy
    pre_ayer <- pre_m[t]
  }

  colnames(ch) <- paste0("ch_", seq_len(n_h))
  colnames(at_i_mat) <- paste0("at_", seq_len(n_h))
  colnames(trr_i_mat) <- paste0("tr_", seq_len(n_h))
  colnames(chv_mat) <- paste0("chv_", seq_len(n_h))
  colnames(dr_h_mat) <- paste0("drenaje_horizonte_", seq_len(n_h))
  colnames(cf_mat) <- paste0("chf_", seq_len(n_h))
  colnames(me_mat) <- paste0("me_", seq_len(n_h))

  serie_diaria <- tibble::tibble(
    date = serie$date,
    absi = absi, esc = esc, inf = inf, drenaje_profundo = drenaje_profundo,
    demt = demt, deme = deme,
    au_mm_m1 = au_mm_m1, au_mm_m2 = au_mm_m2, au_mm_total = au_mm_total,
    au_pct_m1 = au_pct_m1, au_pct_m2 = au_pct_m2, au_pct_total = au_pct_total,
    sandwich_seco = sandwich_seco,
    prp_incremento = prp_incremento, lhpr = lhpr, pre_m = pre_m
  )
  serie_diaria <- dplyr::bind_cols(serie_diaria, tibble::as_tibble(ch))
  serie_diaria <- dplyr::bind_cols(serie_diaria, tibble::as_tibble(at_i_mat))
  serie_diaria$at <- at_total
  serie_diaria$trr <- trr
  serie_diaria$trrr <- trrr
  serie_diaria <- dplyr::bind_cols(serie_diaria, tibble::as_tibble(trr_i_mat))
  serie_diaria$aef <- aef
  serie_diaria$aer <- aer
  serie_diaria$er <- er
  serie_diaria <- dplyr::bind_cols(serie_diaria, tibble::as_tibble(chv_mat))
  serie_diaria <- dplyr::bind_cols(serie_diaria, tibble::as_tibble(dr_h_mat))
  serie_diaria <- dplyr::bind_cols(serie_diaria, tibble::as_tibble(cf_mat))
  serie_diaria <- dplyr::bind_cols(serie_diaria, tibble::as_tibble(me_mat))

  list(serie_diaria = serie_diaria)
}
