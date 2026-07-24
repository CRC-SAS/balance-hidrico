test_that("calcular_curva_kcb reproduce los puntos de control del xlsx v2 (trigo)", {
  clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  res <- calcular_fenologia("trigo", "intermedio-largo", clima, "1983-05-30", parametros)
  p <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")

  kcb <- calcular_curva_kcb(res$serie_diaria, p$ut_e_fkcbini, p$ut_e_ikcbmax, p$kcb$kcb_ini, p$kcb$kcb_max)

  kcb_en <- function(fecha) kcb$kcb[kcb$date == as.Date(fecha)]
  expect_equal(kcb_en("1983-07-07"), 0.15)
  expect_equal(kcb_en("1983-09-05"), 0.7949142857142857, tolerance = 1e-9)
})

test_that("calcular_curva_kcb se mantiene en kcb_max hasta el final, sin declinar (duda KC-1)", {
  serie <- tibble::tibble(
    date = as.Date("2020-01-01") + 0:9,
    ut_simple_acum = c(0, 50, 100, 150, 200, 250, 300, 350, 1000, 5000)
  )
  kcb <- calcular_curva_kcb(serie, ut_fkcbini = 100, ut_ikcbmax = 300, kcb_ini = 0.15, kcb_max = 1.10)

  expect_equal(kcb$kcb[serie$ut_simple_acum == 0], 0.15)
  expect_equal(kcb$kcb[serie$ut_simple_acum == 100], 0.15)
  expect_equal(kcb$kcb[serie$ut_simple_acum == 300], 1.10)
  expect_equal(kcb$kcb[serie$ut_simple_acum == 1000], 1.10)
  # Aunque la UT siga acumulando mucho mas alla del umbral, Kcb no declina:
  # es una decision de diseno deliberada, confirmada por el experto (KC-1).
  expect_equal(kcb$kcb[serie$ut_simple_acum == 5000], 1.10)
})

test_that("calcular_curva_kcb interpola linealmente entre kcb_ini y kcb_max", {
  serie <- tibble::tibble(date = as.Date("2020-01-01"), ut_simple_acum = 200)
  kcb <- calcular_curva_kcb(serie, ut_fkcbini = 100, ut_ikcbmax = 300, kcb_ini = 0.15, kcb_max = 1.10)
  # a mitad de camino entre 100 y 300 (200) -> a mitad de camino entre 0.15 y 1.10
  esperado <- 0.15 + (1.10 - 0.15) * 0.5
  expect_equal(kcb$kcb[1], esperado, tolerance = 1e-9)
})
