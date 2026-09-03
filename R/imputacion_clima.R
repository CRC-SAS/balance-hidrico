# Relleno estocastico de huecos puntuales en una base climatica diaria
# (dias sin dato, acotados por observaciones reales de ambos lados -- no
# es parte del metodo CRC-SAS, es un paso de preprocesamiento de calidad
# de dato para cuando la fuente de clima real tiene huecos). Ver
# `completar_gaps_clima()` mas abajo para el detalle metodologico (STL +
# AR(1) con innovacion estacional para temperaturas, cadena de Markov +
# gamma para precipitacion, Richardson 1981/WGEN).

# Corridas de NA internas a un vector: excluye las que tocan el primer o
# el ultimo dato (esas son "todavia no paso" / "no hay dato antes del
# inicio de la serie", no un hueco a rellenar).
.identificar_corridas_na <- function(x) {
  n <- length(x)
  r <- rle(is.na(x))
  fin <- cumsum(r$lengths)
  inicio <- fin - r$lengths + 1
  internas <- r$values & inicio > 1 & fin < n
  data.frame(inicio = inicio[internas], fin = fin[internas])
}

# Muestra de la distribucion condicional de un AR(1) estacionario
# (r_t = phi*r_(t-1) + eps_t, eps_t ~ N(0, sigma2_innovacion)) en las
# posiciones internas de un hueco, dados los valores reales inmediatamente
# antes (r_antes) y despues (r_despues). Muestreo secuencial: en cada paso
# se combina (a) la prediccion desde el valor anterior (ya muestreado) con
# (b) la "verosimilitud" de terminar en r_despues luego de los pasos que
# quedan -- formula cerrada de Bayes lineal-gaussiano, equivalente a un
# suavizado tipo Kalman/RTS para esta cadena escalar. Da una MUESTRA (no
# el promedio condicional), para que el resultado tenga ruido, no sea un
# valor "aplanado".
.ar1_bridge_muestra <- function(phi, sigma2_innovacion, r_antes, r_despues, n_huecos) {
  phi <- max(min(phi, 0.98), -0.98)
  k <- n_huecos
  muestra <- numeric(k)
  r_prev <- r_antes
  for (t in seq_len(k)) {
    m <- k + 1L - t
    mu_prior <- phi * r_prev
    v_futuro <- sigma2_innovacion * (1 - phi^(2 * m)) / (1 - phi^2)
    prec_prior <- 1 / sigma2_innovacion
    prec_lik <- phi^(2 * m) / v_futuro
    var_post <- 1 / (prec_prior + prec_lik)
    media_post <- var_post * (mu_prior / sigma2_innovacion + phi^m * r_despues / v_futuro)
    r_t <- stats::rnorm(1, media_post, sqrt(var_post))
    muestra[t] <- r_t
    r_prev <- r_t
  }
  muestra
}

# Rellena los huecos de una serie continua (tx, o log del rango termico
# tx-tn) via stlplus (tendencia + estacionalidad, tolera NA) + bridge
# AR(1) sobre el residuo, con la varianza de innovacion escalada por
# trimestre del anio (no una sola varianza global -- la variabilidad dia
# a dia no es constante en el anio). n.p = 365 (aproximacion; no corrige
# el corrimiento de fase de ~1 dia cada 4 anios por bisiestos --
# irrelevante para huecos de pocos dias).
.rellenar_serie_continua <- function(valor, quarter, corridas) {
  fit <- stlplus::stlplus(valor, n.p = 365, s.window = "periodic")
  estacional <- fit$data$seasonal
  tendencia <- fit$data$trend
  residuo <- fit$data$remainder

  obs <- !is.na(residuo)
  sd_trimestre <- tapply(residuo[obs], quarter[obs], stats::sd)

  ar_fit <- stats::arima(residuo, order = c(1, 0, 0), include.mean = FALSE)
  phi <- unname(ar_fit$coef[["ar1"]])

  for (i in seq_len(nrow(corridas))) {
    ini <- corridas$inicio[i]
    fin <- corridas$fin[i]
    k <- fin - ini + 1L
    trimestre_hueco <- as.character(quarter[ini])
    sigma2_innovacion <- sd_trimestre[[trimestre_hueco]]^2 * (1 - phi^2)
    residuo_generado <- .ar1_bridge_muestra(
      phi, sigma2_innovacion, residuo[ini - 1L], residuo[fin + 1L], k
    )
    valor[ini:fin] <- estacional[ini:fin] + tendencia[ini:fin] + residuo_generado
  }
  valor
}

# Rellena tx, tn y tm de forma conjunta y fisicamente consistente (no
# como 3 series independientes -- ver nota de diseno en
# completar_gaps_clima()):
#  1) tx es la serie "primaria": sus huecos se rellenan con su propio
#     modelo (stlplus + bridge AR(1)), sin mirar tn ese dia.
#  2) tn se DERIVA de tx: se modela el rango termico (tx-tn) en escala
#     log (siempre positivo) sobre los dias con ambos datos reales, y se
#     usa ese rango generado + el tx ya completo (paso 1) para resolver
#     tn en sus huecos -- garantiza tn < tx por construccion, incluso el
#     dia en que faltaban los dos (tx ya esta completo del paso 1).
#  3) Salvaguarda fisica tx >= tn (pmax/pmin) para el caso en que el paso
#     2 no alcanza por si solo: falta SOLO tx con tn real presente ese dia
#     (tx se genero sin conocer ese tn real). Se aplica UNICAMENTE donde
#     tx y tn quedaron los dos con valor (real o generado) -- si alguno
#     sigue en NA (hueco de borde de serie, ver completar_gaps_clima()),
#     se preserva tal cual en vez de contaminarlo con pmax()/pmin() (que
#     sin na.rm devuelven NA apenas un lado es NA, borrando un dato real
#     del otro lado). Encontrado con datos reales multi-estacion: una
#     estacion puede tener tx real pero tn recien empieza a registrarse
#     mas adelante (huecos de tx/tn no simetricos en el borde inicial).
#  4) tm nunca se modela por separado -- siempre se deriva al final con
#     calcular_temperatura_media(tx, tn, tm), la formula exacta que ya
#     usa el resto del paquete. Resuelve de paso el caso "faltan los
#     tres" sin tratamiento especial.
.rellenar_temperaturas <- function(tx, tn, tm, quarter) {
  tx_original <- tx
  tn_original <- tn

  corridas_tx <- .identificar_corridas_na(tx)
  if (nrow(corridas_tx) > 0) {
    tx <- .rellenar_serie_continua(tx, quarter, corridas_tx)
  }

  log_rango <- log(tx_original - tn_original)
  corridas_rango <- .identificar_corridas_na(log_rango)
  if (nrow(corridas_rango) > 0) {
    log_rango_relleno <- .rellenar_serie_continua(log_rango, quarter, corridas_rango)
    for (i in seq_len(nrow(corridas_rango))) {
      idx <- corridas_rango$inicio[i]:corridas_rango$fin[i]
      falta_tn <- is.na(tn_original[idx])
      tn[idx[falta_tn]] <- tx[idx[falta_tn]] - exp(log_rango_relleno[idx[falta_tn]])
    }
  }

  ambos <- !is.na(tx) & !is.na(tn)
  tx_final <- tx
  tn_final <- tn
  tx_final[ambos] <- pmax(tx[ambos], tn[ambos])
  tn_final[ambos] <- pmin(tx[ambos], tn[ambos])
  tm_final <- calcular_temperatura_media(tx_final, tn_final, tm)

  list(tx = tx_final, tn = tn_final, tm = tm_final)
}

# Rellena los huecos de precipitacion con un modelo de dos partes
# (Richardson, 1981 -- WGEN): ocurrencia via cadena de Markov de 2 estados
# estimada de toda la serie (P(llueve hoy | ayer llovio) vs P(llueve hoy |
# ayer seco)), monto condicional a que llueva via una gamma ajustada por
# maxima verosimilitud sobre los dias de lluvia historicos. Los huecos se
# recorren dia a dia (no de una vez) porque el estado "llovio ayer" de
# cada dia depende del dia anterior, que puede ser parte del mismo hueco.
.rellenar_precipitacion <- function(pp, corridas, umbral_lluvia = 0.1) {
  llovio <- pp > umbral_lluvia
  n <- length(pp)

  pares <- which(!is.na(pp[-n]) & !is.na(pp[-1]))
  ayer <- llovio[pares]
  hoy <- llovio[pares + 1L]
  p_si_ayer_llovio <- mean(hoy[ayer], na.rm = TRUE)
  p_si_ayer_seco <- mean(hoy[!ayer], na.rm = TRUE)

  dias_lluvia <- pp[!is.na(pp) & pp > umbral_lluvia]
  gamma_fit <- MASS::fitdistr(dias_lluvia, "gamma")
  shape <- gamma_fit$estimate[["shape"]]
  rate <- gamma_fit$estimate[["rate"]]

  for (i in seq_len(nrow(corridas))) {
    ini <- corridas$inicio[i]
    fin <- corridas$fin[i]
    estado_ayer <- llovio[ini - 1L]
    for (d in ini:fin) {
      p <- if (isTRUE(estado_ayer)) p_si_ayer_llovio else p_si_ayer_seco
      llovio_hoy <- stats::runif(1) < p
      pp[d] <- if (llovio_hoy) stats::rgamma(1, shape = shape, rate = rate) else 0
      llovio[d] <- llovio_hoy
      estado_ayer <- llovio_hoy
    }
  }
  pp
}

#' Completar huecos puntuales en una base climatica diaria (una estacion)
#'
#' Rellena dias sin dato en `tx`/`tn`/`tm`/`pp`, **solo** cuando estan
#' acotados por observaciones reales de ambos lados -- las corridas de
#' `NA` que llegan hasta el primer o el ultimo dia de la serie (p.ej. el
#' resto de un anio en curso, todavia no observado) se dejan intactas, no
#' son "huecos" sino datos que todavia no existen.
#'
#' **Temperaturas**: `tx`, `tn` y `tm` se rellenan de forma conjunta, no
#' como 3 series independientes -- generarlas por separado podria dar
#' `tn > tx` (fisicamente imposible, y rompe `sqrt(tx-tn)` de
#' [calcular_eto_hargreaves()]) o un `tm` inconsistente con `(tx+tn)/2`.
#' `tx` es la serie "primaria" (descomposicion STL, `stlplus`, mas un
#' "bridge" AR(1) sobre el residuo con la varianza de innovacion escalada
#' por trimestre del anio, condicionado a los valores reales inmediatos
#' antes/despues del hueco -- una muestra, no el promedio); `tn` se
#' deriva de `tx` y de un modelo aparte para el rango termico (`tx-tn`,
#' en escala log para que de positivo), lo que garantiza `tn < tx` por
#' construccion; `tm` nunca se modela por separado, siempre se deriva al
#' final con [calcular_temperatura_media()] (formula exacta ya usada en
#' el resto del paquete). Detalle completo en `.rellenar_temperaturas()`.
#'
#' **Precipitacion** (`pp`): modelo de dos partes tipo Richardson (1981,
#' WGEN) -- ocurrencia via cadena de Markov de 2 estados, monto
#' condicional a que llueva via una distribucion gamma.
#'
#' Esta funcion siembra el generador aleatorio (`set.seed(semilla)`) al
#' principio para que el resultado sea reproducible -- efecto de lado
#' sobre el estado global de `.Random.seed`, documentado aca a proposito.
#'
#' @param clima Tibble de una sola estacion, misma forma que devuelve
#'   [leer_clima_csv()] (`station_id`, `date`, `doy`, `tx`, `tn`, `tm`,
#'   `pp`, `eto`). `date` debe ser una secuencia diaria completa y
#'   ordenada. La columna `eto` no se toca (recalcularla despues si
#'   corresponde).
#' @param semilla Integer. Semilla para `set.seed()`. Default `1234`.
#'
#' @return El mismo tibble `clima`, con los huecos internos de
#'   `tx`/`tn`/`tm`/`pp` completados.
#' @export
completar_gaps_clima <- function(clima, semilla = 1234) {
  if (length(unique(clima$station_id)) > 1) {
    rlang::abort("completar_gaps_clima() asume una sola estacion; el tibble tiene multiples station_id")
  }
  clima <- clima[order(clima$date), ]
  fechas_esperadas <- seq(min(clima$date), max(clima$date), by = "day")
  if (!identical(clima$date, fechas_esperadas)) {
    rlang::abort("completar_gaps_clima() necesita una secuencia diaria completa y ordenada (sin dias faltantes en 'date')")
  }

  set.seed(semilla)

  quarter <- lubridate::quarter(clima$date)

  temperaturas <- .rellenar_temperaturas(clima$tx, clima$tn, clima$tm, quarter)
  clima$tx <- temperaturas$tx
  clima$tn <- temperaturas$tn
  clima$tm <- temperaturas$tm

  corridas_pp <- .identificar_corridas_na(clima$pp)
  if (nrow(corridas_pp) > 0) {
    clima$pp <- .rellenar_precipitacion(clima$pp, corridas_pp)
  }

  clima
}
