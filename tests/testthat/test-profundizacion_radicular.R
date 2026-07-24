test_that("calcular_profundidad_radicular reproduce los puntos de control del xlsx v2 (trigo)", {
  clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  res <- calcular_fenologia("trigo", "intermedio-largo", clima, "1983-05-30", parametros)
  p <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")

  raices <- calcular_profundidad_radicular(
    clima, res$hitos$emergencia, res$hitos$hito2,
    tb_c = p$raiz$tb_c, pr_s_e = p$raiz$pr_s_e, pr = p$raiz$pr
  )

  prof_en <- function(fecha) raices$profundidad_radical_m[raices$date == as.Date(fecha)]
  expect_equal(prof_en("1983-05-30"), 0.2)  # dia de siembra, antes de emergencia
  expect_equal(prof_en("1983-07-07"), 0.46182, tolerance = 1e-9)
  expect_equal(prof_en("1983-07-08"), 0.47222, tolerance = 1e-9)
  expect_equal(prof_en("1983-09-05"), 1.20776, tolerance = 1e-9)
})

test_that("calcular_profundidad_radicular se congela despues del hito2 (cuaje de granos)", {
  clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  res <- calcular_fenologia("trigo", "intermedio-largo", clima, "1983-05-30", parametros)
  p <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")

  raices <- calcular_profundidad_radicular(
    clima, res$hitos$emergencia, res$hitos$hito2,
    tb_c = p$raiz$tb_c, pr_s_e = p$raiz$pr_s_e, pr = p$raiz$pr
  )

  prof_hito2 <- raices$profundidad_radical_m[raices$date == res$hitos$hito2]
  prof_10_dias_despues <- raices$profundidad_radical_m[raices$date == res$hitos$hito2 + 10]
  prof_madurez <- raices$profundidad_radical_m[raices$date == res$hitos$madurez_fisiologica]

  expect_equal(prof_10_dias_despues, prof_hito2)
  expect_equal(prof_madurez, prof_hito2)
})

test_that("calcular_profundidad_radicular respeta el tope de profundidad maxima del suelo (duda PR-1)", {
  clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  res <- calcular_fenologia("trigo", "intermedio-largo", clima, "1983-05-30", parametros)
  p <- obtener_parametros_cultivo(parametros, "trigo", "intermedio-largo")

  raices_sin_tope <- calcular_profundidad_radicular(
    clima, res$hitos$emergencia, res$hitos$hito2,
    tb_c = p$raiz$tb_c, pr_s_e = p$raiz$pr_s_e, pr = p$raiz$pr
  )
  expect_gt(max(raices_sin_tope$profundidad_radical_m), 1.0)

  raices_con_tope <- calcular_profundidad_radicular(
    clima, res$hitos$emergencia, res$hitos$hito2,
    tb_c = p$raiz$tb_c, pr_s_e = p$raiz$pr_s_e, pr = p$raiz$pr,
    profundidad_maxima_suelo = 1.0
  )
  expect_lte(max(raices_con_tope$profundidad_radical_m), 1.0)
})
