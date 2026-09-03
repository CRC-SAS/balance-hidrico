# -----------------------------------------------------------------------------
# Fixture sintetico: 6 anios de clima diario con estacionalidad senoidal
# conocida + ruido AR(1) conocido (para tx y para el rango termico
# tx-tn), y precipitacion Markov+gamma conocida -- no son datos reales,
# son series generadas a mano con parametros elegidos para poder verificar
# que completar_gaps_clima() hace lo esperado (mismo criterio que los
# climas sinteticos de maiz/soja en Pasos 1 y 3, ver FUTURE_WORK.md).
# -----------------------------------------------------------------------------

.clima_sintetico <- function(semilla_datos = 42) {
  set.seed(semilla_datos)
  n <- 365 * 6
  fecha <- seq(as.Date("2000-01-01"), by = "day", length.out = n)
  doy <- as.numeric(format(fecha, "%j"))

  # tx: estacionalidad senoidal (verano calido, invierno frio) + AR(1)
  # con phi=0.5 conocido.
  estacional_tx <- 22 + 8 * sin(2 * pi * (doy - 80) / 365)
  ruido_tx <- numeric(n)
  for (t in 2:n) ruido_tx[t] <- 0.5 * ruido_tx[t - 1] + rnorm(1, 0, 1.2)
  tx <- estacional_tx + ruido_tx

  # rango termico (tx - tn): siempre positivo, con su propia estacionalidad
  # y AR(1) en escala log.
  estacional_log_rango <- log(9) + 0.3 * sin(2 * pi * (doy - 200) / 365)
  ruido_log_rango <- numeric(n)
  for (t in 2:n) ruido_log_rango[t] <- 0.4 * ruido_log_rango[t - 1] + rnorm(1, 0, 0.15)
  rango <- exp(estacional_log_rango + ruido_log_rango)
  tn <- tx - rango

  tm <- (tx + tn) / 2

  # precipitacion: Markov de 2 estados + gamma.
  llovio <- logical(n)
  pp <- numeric(n)
  for (t in 2:n) {
    p <- if (llovio[t - 1]) 0.4 else 0.15
    llovio[t] <- runif(1) < p
    pp[t] <- if (llovio[t]) rgamma(1, shape = 2, rate = 0.3) else 0
  }

  tibble::tibble(
    station_id = "99999", date = fecha, doy = doy,
    tx = tx, tn = tn, tm = tm, pp = pp, eto = NA_real_
  )
}

test_that("completar_gaps_clima rellena huecos internos y deja intactos los que tocan el borde", {
  clima <- .clima_sintetico()
  n <- nrow(clima)

  # Huecos internos: 1 dia en tn (i=500), 2 dias consecutivos en tx
  # (i=1000:1001, fuerza el caso 'faltan tx y tn el mismo dia' si tn
  # tambien tuviera NA ahi -- acá solo tx, para probar el caso "falta
  # solo tx con tn real" y la salvaguarda fisica), 1 dia en pp (i=1500).
  clima$tn[500] <- NA
  clima$tx[1000:1001] <- NA
  clima$pp[1500] <- NA

  # Corrida que toca el final de la serie: no es un hueco, es "todavia
  # no observado" -- tiene que quedar intacta (NA).
  clima$tx[(n - 4):n] <- NA

  relleno <- completar_gaps_clima(clima, semilla = 123)

  expect_false(is.na(relleno$tn[500]))
  expect_false(any(is.na(relleno$tx[1000:1001])))
  expect_false(is.na(relleno$pp[1500]))

  # La corrida que toca el borde queda intacta -- y el tn REAL de esos
  # mismos dias no se pierde (regresion: pmax()/pmin() sin condicionar a
  # "ambos no-NA" devolvia NA en tn ahi tambien, ver mas abajo).
  expect_true(all(is.na(relleno$tx[(n - 4):n])))
  expect_equal(relleno$tn[(n - 4):n], clima$tn[(n - 4):n])

  # No quedan NA en los huecos internos de ninguna columna.
  huecos_internos <- setdiff(seq_len(n), (n - 4):n)
  expect_false(anyNA(relleno$tx[huecos_internos]))
  expect_false(anyNA(relleno$tn[huecos_internos]))
  expect_false(anyNA(relleno$tm[huecos_internos]))
  expect_false(anyNA(relleno$pp))
})

test_that("completar_gaps_clima no toca los dias sin hueco (passthrough exacto)", {
  clima <- .clima_sintetico()
  clima$tn[500] <- NA

  relleno <- completar_gaps_clima(clima, semilla = 123)

  idx_sin_tocar <- setdiff(seq_len(nrow(clima)), 500)
  expect_equal(relleno$tx[idx_sin_tocar], clima$tx[idx_sin_tocar])
  expect_equal(relleno$tn[idx_sin_tocar], clima$tn[idx_sin_tocar])
  expect_equal(relleno$pp, clima$pp)
})

test_that("completar_gaps_clima garantiza consistencia fisica (tx >= tn, pp >= 0) y tm derivado", {
  clima <- .clima_sintetico()
  # Fuerza el caso "faltan tx, tn Y tm el mismo dia" (bloque de 3 dias).
  clima$tx[800:802] <- NA
  clima$tn[800:802] <- NA
  clima$tm[800:802] <- NA
  # Caso "falta solo tx, tn real presente" (para ejercitar la salvaguarda).
  clima$tx[900] <- NA

  relleno <- completar_gaps_clima(clima, semilla = 123)

  expect_true(all(relleno$tx >= relleno$tn))
  expect_true(all(relleno$pp >= 0, na.rm = TRUE))

  # tm en los dias donde faltaba junto con tx/tn tiene que coincidir con
  # (tx+tn)/2 del resultado final (formula de calcular_temperatura_media()).
  expect_equal(
    relleno$tm[800:802],
    (relleno$tx[800:802] + relleno$tn[800:802]) / 2,
    tolerance = 1e-9
  )
})

test_that("completar_gaps_clima no borra un lado real cuando el otro tiene un hueco de borde largo", {
  # Encontrado con datos reales multi-estacion (base_datos_balance_hidrico.xlsx,
  # estacion 87688): tn no se empezo a registrar hasta 59 dias despues que
  # tx, en el arranque de la serie. La salvaguarda fisica pmax()/pmin() sin
  # condicionar a "ambos no-NA" devolvia NA para tx en TODO ese tramo,
  # borrando 59 dias de tx real que no tenian nada de malo.
  clima <- .clima_sintetico()
  n_hueco <- 59
  clima$tn[1:n_hueco] <- NA

  relleno <- completar_gaps_clima(clima, semilla = 123)

  # tn queda intacto (hueco de borde, no se inventa) y tx -- que SI tenia
  # dato real esos dias -- no se pierde.
  expect_true(all(is.na(relleno$tn[1:n_hueco])))
  expect_equal(relleno$tx[1:n_hueco], clima$tx[1:n_hueco])
})

test_that("completar_gaps_clima es reproducible con la misma semilla y distinto con otra", {
  clima <- .clima_sintetico()
  clima$tn[500] <- NA
  clima$tx[1000:1001] <- NA
  clima$pp[1500] <- NA

  r1 <- completar_gaps_clima(clima, semilla = 7)
  r2 <- completar_gaps_clima(clima, semilla = 7)
  r3 <- completar_gaps_clima(clima, semilla = 8)

  expect_identical(r1$tn[500], r2$tn[500])
  expect_identical(r1$tx[1000:1001], r2$tx[1000:1001])
  expect_identical(r1$pp[1500], r2$pp[1500])

  expect_false(isTRUE(all.equal(r1$tn[500], r3$tn[500])))
})

test_that("completar_gaps_clima da valores fisicamente plausibles (dentro de un rango amplio de la estacionalidad)", {
  clima <- .clima_sintetico()
  clima$tn[500] <- NA
  relleno <- completar_gaps_clima(clima, semilla = 123)

  # tx en la fecha del hueco de tn no cambio -- referencia de escala
  # razonable para el dia (estacionalidad ~22 +/- 8, ruido AR(1) sd~1.2).
  expect_true(relleno$tn[500] > -20 && relleno$tn[500] < 40)
})

test_that("completar_gaps_clima rechaza series con mas de una estacion o con dias faltantes en 'date'", {
  clima <- .clima_sintetico()
  clima$tn[500] <- NA

  clima_multi <- clima
  clima_multi$station_id[1] <- "88888"
  expect_error(completar_gaps_clima(clima_multi))

  clima_con_hueco_fecha <- clima[-500, ]
  expect_error(completar_gaps_clima(clima_con_hueco_fecha))
})

# -----------------------------------------------------------------------------
# Chequeo numerico independiente del bridge AR(1) (.ar1_bridge_muestra()):
# compara media/varianza empirica (muchas muestras) contra la formula
# cerrada de un AR(1) condicionado en ambos extremos, derivada de forma
# INDEPENDIENTE del codigo de produccion (algebra de normal multivariada
# via matriz de covarianza + formula de condicionamiento de Schur), no
# solo releyendo la misma formula secuencial que usa .ar1_bridge_muestra().
# -----------------------------------------------------------------------------

test_that(".ar1_bridge_muestra coincide con la formula cerrada de un solo hueco (k=1, textbook)", {
  phi <- 0.6
  sigma2 <- 2
  a <- 3
  b <- -1

  media_esperada <- phi * (a + b) / (1 + phi^2)
  var_esperada <- sigma2 / (1 + phi^2)

  set.seed(1)
  muestras <- replicate(20000, .ar1_bridge_muestra(phi, sigma2, a, b, 1))

  expect_equal(mean(muestras), media_esperada, tolerance = 0.05)
  expect_equal(stats::var(as.numeric(muestras)), var_esperada, tolerance = 0.1)
})

test_that(".ar1_bridge_muestra coincide con la normal multivariada condicionada (k=3, derivacion independiente)", {
  phi <- 0.5
  sigma2 <- 1.5
  a <- 2
  b <- -0.5
  k <- 3

  # Covarianza conjunta NO condicionada de (r_1,...,r_{k+1}) dado r_0=a,
  # via la formula estandar de un AR(1): Cov(r_s,r_t) = phi^|t-s| * Var(r_min(s,t)),
  # Var(r_t) = sigma2 * (1-phi^(2t))/(1-phi^2).
  var_r <- function(t) sigma2 * (1 - phi^(2 * t)) / (1 - phi^2)
  idx <- 1:(k + 1)
  Sigma <- outer(idx, idx, function(s, t) phi^abs(t - s) * var_r(pmin(s, t)))
  media_incond <- phi^idx * a

  # Condicionar sobre r_{k+1}=b (formula de Schur para normal multivariada).
  Sigma_11 <- Sigma[1:k, 1:k]
  Sigma_12 <- Sigma[1:k, k + 1]
  Sigma_22 <- Sigma[k + 1, k + 1]
  media_cond <- media_incond[1:k] + Sigma_12 / Sigma_22 * (b - media_incond[k + 1])
  Sigma_cond <- Sigma_11 - outer(Sigma_12, Sigma_12) / Sigma_22

  set.seed(2)
  n_rep <- 20000
  muestras <- t(replicate(n_rep, .ar1_bridge_muestra(phi, sigma2, a, b, k)))

  expect_equal(colMeans(muestras), media_cond, tolerance = 0.05)
  expect_equal(stats::cov(muestras), Sigma_cond, tolerance = 0.15)
})
