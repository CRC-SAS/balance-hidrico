# -----------------------------------------------------------------------------
# No hay celdas del xlsx de referencia para las 3 salidas de Paso 5 (el
# experto las respondio por chat, no estan en ninguna hoja) -- fixtures
# sinteticos, calculados a mano.
# -----------------------------------------------------------------------------

test_that("calcular_eventos_lluvia_10mm_14a_7d_siembra cuenta dias con pp>=10mm en [-14,+7], limites inclusive", {
  fecha_siembra <- as.Date("2020-06-15")
  dias <- seq(fecha_siembra - 20, fecha_siembra + 12, by = "day")
  pp <- rep(0, length(dias))
  # exactamente en el limite inferior (-14): cuenta
  pp[dias == fecha_siembra - 14] <- 10
  # exactamente en el limite superior (+7): cuenta
  pp[dias == fecha_siembra + 7] <- 10
  # un dia antes del limite inferior: NO cuenta
  pp[dias == fecha_siembra - 15] <- 10
  # un dia despues del limite superior: NO cuenta
  pp[dias == fecha_siembra + 8] <- 10
  # exactamente en el umbral (10): cuenta
  pp[dias == fecha_siembra - 5] <- 10
  # justo debajo del umbral: NO cuenta
  pp[dias == fecha_siembra - 3] <- 9.99
  # bien por encima: cuenta
  pp[dias == fecha_siembra] <- 25

  clima_estacion <- tibble::tibble(date = dias, pp = pp)

  expect_equal(calcular_eventos_lluvia_10mm_14a_7d_siembra(clima_estacion, fecha_siembra), 4)
})

test_that("calcular_estado_hidrico_siembra selecciona la fila de fecha_siembra", {
  fechas <- as.Date("2020-01-01") + 0:4
  serie_diaria_balance <- tibble::tibble(
    date = fechas,
    au_pct_m1 = c(0.5, 0.6, 0.7, 0.8, 0.9),
    au_pct_m2 = c(0.4, 0.5, 0.6, 0.7, 0.8),
    au_pct_total = c(0.45, 0.55, 0.65, 0.75, 0.85),
    sandwich_seco = c("No", "No", "Si", "No", "No")
  )

  res <- calcular_estado_hidrico_siembra(serie_diaria_balance, "2020-01-03")

  expect_equal(nrow(res), 1)
  expect_equal(res$au_pct_m1, 70)
  expect_equal(res$au_pct_m2, 60)
  expect_equal(res$au_pct_total, 65)
  expect_equal(res$sandwich_seco, "Si")
})

test_that("calcular_estado_hidrico_siembra aborta si no hay exactamente una fila para esa fecha", {
  serie_diaria_balance <- tibble::tibble(
    date = as.Date("2020-01-02") + 0:1,
    au_pct_m1 = c(0.5, 0.6), au_pct_m2 = c(0.4, 0.5), au_pct_total = c(0.45, 0.55),
    sandwich_seco = c("No", "No")
  )
  expect_error(calcular_estado_hidrico_siembra(serie_diaria_balance, "2020-01-01"))
})

test_that("calcular_confort_hidrico calcula sum(TrR)/sum(DemT) solo dentro de la ventana (limites inclusive)", {
  hitos <- tibble::tibble(
    inicio_periodo_critico = as.Date("2020-02-10"),
    fin_periodo_critico = as.Date("2020-02-14")
  )
  fechas <- as.Date("2020-02-08") + 0:9
  serie_diaria_balance <- tibble::tibble(
    date = fechas,
    trr = c(100, 100, 5, 4, 3, 2, 1, 100, 100, 100),
    demt = c(100, 100, 10, 10, 10, 10, 10, 100, 100, 100)
  )
  # ventana: 2020-02-10 a 2020-02-14 -> trr=5,4,3,2,1 (sum=15); demt=10*5=50
  expect_equal(calcular_confort_hidrico(serie_diaria_balance, hitos), 100 * 15 / 50)
})

test_that("calcular_confort_hidrico devuelve NA si sum(DemT) es 0 en la ventana", {
  hitos <- tibble::tibble(
    inicio_periodo_critico = as.Date("2020-02-10"),
    fin_periodo_critico = as.Date("2020-02-11")
  )
  serie_diaria_balance <- tibble::tibble(
    date = as.Date("2020-02-10") + 0:1,
    trr = c(0, 0), demt = c(0, 0)
  )
  expect_true(is.na(calcular_confort_hidrico(serie_diaria_balance, hitos)))
})

test_that("calcular_salidas combina las 3 salidas con la forma esperada", {
  fecha_siembra <- as.Date("2020-06-15")
  dias <- seq(fecha_siembra - 20, fecha_siembra + 20, by = "day")
  clima_estacion <- tibble::tibble(date = dias, pp = ifelse(dias == fecha_siembra - 1, 15, 0))

  hitos <- tibble::tibble(
    inicio_periodo_critico = fecha_siembra + 5,
    fin_periodo_critico = fecha_siembra + 7
  )
  serie_diaria_balance <- tibble::tibble(
    date = dias,
    au_pct_m1 = 0.5, au_pct_m2 = 0.5, au_pct_total = 0.5, sandwich_seco = "No",
    trr = 5, demt = 10
  )

  res <- calcular_salidas(clima_estacion, fecha_siembra, hitos, serie_diaria_balance)

  expect_named(res, c("eventos_lluvia_10mm_14a_7d_siembra", "estado_hidrico_siembra", "confort_hidrico"))
  expect_equal(res$eventos_lluvia_10mm_14a_7d_siembra, 1)
  expect_equal(nrow(res$estado_hidrico_siembra), 1)
  expect_equal(res$confort_hidrico, 50)
})
