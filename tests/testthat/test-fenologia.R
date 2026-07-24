# -----------------------------------------------------------------------------
# TRIGO: fixtures reales, extraidas de docs/v2/Calculos fenologia y balance
# hidrico.xlsx (hoja `fenologia`, cultivo=trigo, cultivar=intermedio-largo,
# estacion 87480, siembra dda_S=150 -> 1983-05-30). Valores cacheados en el
# xlsx, verificados en la sesion de analisis previa a esta implementacion.
# -----------------------------------------------------------------------------

test_that("calcular_fenologia_trigo reproduce los 8 hitos del xlsx v2", {
  clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))

  res <- calcular_fenologia("trigo", "intermedio-largo", clima, "1983-05-30", parametros)
  h <- res$hitos

  expect_equal(h$siembra, as.Date("1983-05-30"))
  expect_equal(h$emergencia, as.Date("1983-06-18"))
  expect_equal(h$fin_kcb_inicial, as.Date("1983-07-22"))
  expect_equal(h$inicio_kcb_maximo, as.Date("1983-09-24"))
  expect_equal(h$hito1, as.Date("1983-10-08"))
  expect_equal(h$nombre_hito1, "ET")
  expect_equal(h$hito2, as.Date("1983-11-13"))
  expect_equal(h$nombre_hito2, "Z71")
  expect_equal(h$inicio_periodo_critico, as.Date("1983-10-13"))
  expect_equal(h$fin_periodo_critico, as.Date("1983-11-18"))
  expect_equal(h$madurez_fisiologica, as.Date("1983-12-06"))
})

test_that("calcular_fenologia_trigo reproduce la serie diaria de UT del xlsx v2 en puntos de control", {
  clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  res <- calcular_fenologia("trigo", "intermedio-largo", clima, "1983-05-30", parametros)
  sd <- res$serie_diaria

  ut_en <- function(fecha) sd$ut_simple_acum[sd$date == as.Date(fecha)]
  expect_equal(ut_en("1983-07-07"), 201.4, tolerance = 1e-9)
  expect_equal(ut_en("1983-07-08"), 209.4, tolerance = 1e-9)
  expect_equal(ut_en("1983-09-05"), 775.2, tolerance = 1e-9)
})

# -----------------------------------------------------------------------------
# MAIZ y SOJA: el xlsx v2 solo tiene cacheado el escenario trigo (no hay
# LibreOffice/Excel disponible para recalcular con otro cultivo activo -- ver
# limitacion documentada en el plan de implementacion). Estos tests validan
# fidelidad a la formula documentada con climas sinteticos donde el
# resultado esperado se puede calcular a mano.
# -----------------------------------------------------------------------------

test_that("calcular_fenologia_maiz calcula la emergencia con Tb_a (sin efecto de Fp, duda F-6)", {
  dias <- seq(as.Date("2020-01-01"), by = "day", length.out = 400)
  clima_prep <- tibble::tibble(date = dias, doy = lubridate::yday(dias), tm = 30, fp = NA_real_)
  params <- list(tb_a = 10, tb_b = 8, ut_s_e = 80, ut_e_fkcbini = 120, ut_e_ikcbmax = 560,
                 ut_e_r2 = 950, ut_e_ipc = 500, ut_e_fpc = 1050, ut_r2_mf = 550)

  res <- calcular_fenologia_maiz(clima_prep, as.Date("2020-01-01"), params)

  # incremento S->E = 30 - 10 = 20/dia; 20*4 = 80 = ut_s_e exacto -> emergencia el dia 4
  expect_equal(res$hitos$emergencia, as.Date("2020-01-04"))
})

test_that("calcular_fenologia_maiz resuelve todos los hitos posteriores sobre una unica serie de UT", {
  dias <- seq(as.Date("2020-01-01"), by = "day", length.out = 400)
  clima_prep <- tibble::tibble(date = dias, doy = lubridate::yday(dias), tm = 30, fp = NA_real_)
  params <- list(tb_a = 10, tb_b = 8, ut_s_e = 80, ut_e_fkcbini = 120, ut_e_ikcbmax = 560,
                 ut_e_r2 = 950, ut_e_ipc = 500, ut_e_fpc = 1050, ut_r2_mf = 550)

  res <- calcular_fenologia_maiz(clima_prep, as.Date("2020-01-01"), params)
  sd <- res$serie_diaria

  # Cada hito debe ser exactamente el primer dia en que la serie de UT simple
  # alcanza su umbral (chequeo independiente de cual campo de parametros se
  # haya usado para cada etapa: fkcbini/ikcbmax/ipc/r2/fpc/mf).
  expect_primer_dia_en_umbral <- function(fecha, umbral) {
    acum <- sd$ut_simple_acum[sd$date == fecha]
    acum_prev <- sd$ut_simple_acum[sd$date == fecha - 1]
    expect_gte(acum, umbral)
    if (length(acum_prev) == 1) expect_lt(acum_prev, umbral)
  }

  expect_primer_dia_en_umbral(res$hitos$fin_kcb_inicial, params$ut_e_fkcbini)
  expect_primer_dia_en_umbral(res$hitos$inicio_kcb_maximo, params$ut_e_ikcbmax)
  expect_primer_dia_en_umbral(res$hitos$inicio_periodo_critico, params$ut_e_ipc)
  expect_primer_dia_en_umbral(res$hitos$hito2, params$ut_e_r2)
  expect_primer_dia_en_umbral(res$hitos$fin_periodo_critico, params$ut_e_fpc)
  expect_primer_dia_en_umbral(res$hitos$madurez_fisiologica, params$ut_e_r2 + params$ut_r2_mf)

  expect_equal(res$hitos$hito1, res$hitos$hito2)
  expect_equal(res$hitos$nombre_hito1, "R2")
  expect_equal(res$hitos$nombre_hito2, "R2")
})

test_that("calcular_fenologia_soja aplica el tope de temperatura optima (to_a) en Siembra->Emergencia", {
  dias <- seq(as.Date("2020-01-01"), by = "day", length.out = 60)
  clima_prep <- tibble::tibble(date = dias, doy = lubridate::yday(dias), tm = 35, fp = 10)
  # tm=35 > to_a=27: el incremento debe usar min(tm, to_a) - tb_a = 27-10 = 17/dia,
  # NO 35-10 = 25/dia (que daria una emergencia mas temprana)
  params <- list(tb_a = 10, tb_b = 7, to_a = 27, ut_s_e = 170,
                 ut_e_fkcbini = 20, ut_e_ikcbmax = 20,
                 ut_e_r1 = 20, fpu_e_r1 = 30, fpu_r1_mf = 30,
                 ut_r1_ipc = 20, ut_r1_r5 = 20, ut_r5_fpc = 20, ut_r5_mf = 20)

  res <- calcular_fenologia_soja(clima_prep, as.Date("2020-01-01"), params)

  expect_equal(res$hitos$emergencia, as.Date("2020-01-10"))
})

test_that("calcular_fenologia_soja penaliza la acumulacion de UT cuando Fp supera fpu_e_r1", {
  dias <- seq(as.Date("2020-01-01"), by = "day", length.out = 5)
  clima_prep <- tibble::tibble(date = dias, doy = lubridate::yday(dias), tm = 20, fp = 15)
  params <- list(tb_a = 0, tb_b = 7, to_a = 100, ut_s_e = 0,
                 ut_e_fkcbini = 9999, ut_e_ikcbmax = 9999,
                 ut_e_r1 = 21.45, fpu_e_r1 = 13.5, fpu_r1_mf = 13.5,
                 ut_r1_ipc = 9999, ut_r1_r5 = 9999, ut_r5_fpc = 9999, ut_r5_mf = 9999)

  res <- calcular_fenologia_soja(clima_prep, as.Date("2020-01-01"), params)

  # ut_s_e = 0 -> emergencia = dia de siembra
  expect_equal(res$hitos$emergencia, as.Date("2020-01-01"))

  # incremento base = min(20,100) - 7 = 13/dia
  # factor Fp = min(1, max(0, 1 - max(0, 15-13.5)*0.3)) = 1 - 1.5*0.3 = 0.55
  # incremento penalizado = 13 * 0.55 = 7.15/dia
  # acumulado: 7.15, 14.30, 21.45 (>= 21.45 recien el dia 3)
  expect_equal(res$hitos$hito1, as.Date("2020-01-03"))
  expect_equal(res$hitos$nombre_hito1, "R1")
})

test_that("calcular_fenologia_soja: UT_R1-R5 fijo en 300 y resto de hitos sobre la serie post-R1 (duda F-3)", {
  dias <- seq(as.Date("2020-01-01"), by = "day", length.out = 200)
  clima_prep <- tibble::tibble(date = dias, doy = lubridate::yday(dias), tm = 20, fp = 10)
  # fp=10 esta por debajo de ambos umbrales de fotoperiodo (13.5 y 13) -> sin
  # penalizacion (factor = 1) en ninguna de las dos fases
  params <- list(tb_a = 10, tb_b = 7, to_a = 27, ut_s_e = 10,
                 ut_e_fkcbini = 9999, ut_e_ikcbmax = 9999,
                 ut_e_r1 = 400, fpu_e_r1 = 13.5, fpu_r1_mf = 13,
                 ut_r1_ipc = 120, ut_r1_r5 = 300, ut_r5_fpc = 200, ut_r5_mf = 800)

  res <- calcular_fenologia_soja(clima_prep, as.Date("2020-01-01"), params)

  incremento <- 13  # min(20,27) - 7, sin penalizacion
  fecha_r1 <- res$hitos$hito1
  fecha_esperada <- function(umbral) fecha_r1 + (ceiling(umbral / incremento) - 1)

  expect_equal(res$hitos$inicio_periodo_critico, fecha_esperada(120))
  expect_equal(res$hitos$hito2, fecha_esperada(300))
  expect_equal(res$hitos$nombre_hito2, "R5")
  expect_equal(res$hitos$fin_periodo_critico, fecha_esperada(300 + 200))
  expect_equal(res$hitos$madurez_fisiologica, fecha_esperada(300 + 800))
})

test_that("calcular_fenologia lanza error si el cultivo no existe", {
  clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  expect_error(calcular_fenologia("arroz", "x", clima, "1983-05-30", parametros))
})
