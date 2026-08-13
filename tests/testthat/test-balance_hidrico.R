# -----------------------------------------------------------------------------
# Fixture real, extraida celda por celda de documentacion/referencias/v3/
# Calculos fenologia y balance hidrico.xlsx, hoja `balance hídrico` (filas
# 64-491: fecha_inicio 1983-03-01 hasta 1984-05-01, suelo IN64MARC02,
# rastrojo "Moderada" (0.8), humedad inicial "Hu" (0.9) en ambos metros, sin
# sandwich seco inicial). `Prof`/`Kcb` (columnas O/P) se usan como input
# literal (no calculado via calcular_fenologia()/calcular_profundidad_
# radicular()), para desacoplar este test de la correccion de Pasos 1-2 --
# ver tests/testthat/fixtures/balance_hidrico_entrada.csv (428 dias de
# entrada) y balance_hidrico_esperado.csv (17 fechas de control, todas las
# columnas de salida).
# -----------------------------------------------------------------------------

test_that("calcular_balance_hidrico reproduce el fixture del xlsx v3 en 17 fechas de control", {
  entrada <- readr::read_csv(
    testthat::test_path("fixtures", "balance_hidrico_entrada.csv"),
    col_types = readr::cols(date = readr::col_date(), pp = readr::col_double(),
                             eto = readr::col_double(), prof = readr::col_double(),
                             kcb = readr::col_double())
  )
  esperado <- readr::read_csv(
    testthat::test_path("fixtures", "balance_hidrico_esperado.csv"),
    col_types = readr::cols(date = readr::col_date(), .default = readr::col_double(),
                             sandwich_seco = readr::col_character())
  )

  clima_estacion <- dplyr::select(entrada, "date", "pp", "eto")
  serie_profundidad_radicular <- tibble::tibble(date = entrada$date, profundidad_radical_m = entrada$prof)
  serie_kcb <- tibble::tibble(date = entrada$date, kcb = entrada$kcb)

  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  suelo <- obtener_suelo_balance_hidrico(parametros, "IN64MARC02")
  constantes <- leer_constantes_yaml()

  res <- calcular_balance_hidrico(
    clima_estacion = clima_estacion,
    fecha_inicio = "1983-03-01",
    serie_profundidad_radicular = serie_profundidad_radicular,
    serie_kcb = serie_kcb,
    suelo = suelo,
    rastrojo_clase = "Moderada",
    humedad_inicial_clase_m1 = "Hu",
    humedad_inicial_clase_m2 = "Hu",
    constantes = constantes,
    sandwich_seco_inicial = FALSE
  )
  sd <- res$serie_diaria

  expect_equal(nrow(sd), nrow(entrada))

  columnas_numericas <- setdiff(names(esperado), c("date", "sandwich_seco"))

  for (i in seq_len(nrow(esperado))) {
    fila_esperada <- esperado[i, ]
    fila_obtenida <- sd[sd$date == fila_esperada$date, ]
    contexto <- as.character(fila_esperada$date)

    expect_equal(nrow(fila_obtenida), 1, info = contexto)

    for (col in columnas_numericas) {
      expect_equal(
        fila_obtenida[[col]], fila_esperada[[col]],
        tolerance = 1e-9,
        info = paste(contexto, col, sep = " / ")
      )
    }
    expect_equal(fila_obtenida$sandwich_seco, fila_esperada$sandwich_seco, info = contexto)
  }
})

test_that("calcular_balance_hidrico lanza error con clase de rastrojo o humedad invalida", {
  entrada <- readr::read_csv(
    testthat::test_path("fixtures", "balance_hidrico_entrada.csv"),
    col_types = readr::cols(date = readr::col_date(), pp = readr::col_double(),
                             eto = readr::col_double(), prof = readr::col_double(),
                             kcb = readr::col_double())
  )
  clima_estacion <- dplyr::select(entrada, "date", "pp", "eto")
  serie_profundidad_radicular <- tibble::tibble(date = entrada$date, profundidad_radical_m = entrada$prof)
  serie_kcb <- tibble::tibble(date = entrada$date, kcb = entrada$kcb)

  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  suelo <- obtener_suelo_balance_hidrico(parametros, "IN64MARC02")
  constantes <- leer_constantes_yaml()

  expect_error(calcular_balance_hidrico(
    clima_estacion, "1983-03-01", serie_profundidad_radicular, serie_kcb, suelo,
    rastrojo_clase = "Alta", humedad_inicial_clase_m1 = "Hu", humedad_inicial_clase_m2 = "Hu",
    constantes = constantes
  ))

  expect_error(calcular_balance_hidrico(
    clima_estacion, "1983-03-01", serie_profundidad_radicular, serie_kcb, suelo,
    rastrojo_clase = "Moderada", humedad_inicial_clase_m1 = "Humedo", humedad_inicial_clase_m2 = "Hu",
    constantes = constantes
  ))
})

test_that("calcular_balance_hidrico: sandwich seco inicial fuerza 10% AU en horizonte 4 (dia 1)", {
  entrada <- readr::read_csv(
    testthat::test_path("fixtures", "balance_hidrico_entrada.csv"),
    col_types = readr::cols(date = readr::col_date(), pp = readr::col_double(),
                             eto = readr::col_double(), prof = readr::col_double(),
                             kcb = readr::col_double())
  )
  clima_estacion <- dplyr::select(entrada, "date", "pp", "eto")
  serie_profundidad_radicular <- tibble::tibble(date = entrada$date, profundidad_radical_m = entrada$prof)
  serie_kcb <- tibble::tibble(date = entrada$date, kcb = entrada$kcb)

  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  suelo <- obtener_suelo_balance_hidrico(parametros, "IN64MARC02")
  constantes <- leer_constantes_yaml()

  res_normal <- calcular_balance_hidrico(
    clima_estacion, "1983-03-01", serie_profundidad_radicular, serie_kcb, suelo,
    rastrojo_clase = "Moderada", humedad_inicial_clase_m1 = "Hu", humedad_inicial_clase_m2 = "Hu",
    constantes = constantes, sandwich_seco_inicial = FALSE
  )
  res_sandwich <- calcular_balance_hidrico(
    clima_estacion, "1983-03-01", serie_profundidad_radicular, serie_kcb, suelo,
    rastrojo_clase = "Moderada", humedad_inicial_clase_m1 = "Hu", humedad_inicial_clase_m2 = "Hu",
    constantes = constantes, sandwich_seco_inicial = TRUE
  )

  horiz <- suelo$horizontes
  espesor_4 <- horiz$pfh_m[4] - horiz$pfh_m[3]
  pmp4_mm <- horiz$pmp[4] * espesor_4 * 1000
  cc4_mm <- horiz$cc[4] * espesor_4 * 1000
  ch4_esperado_sandwich <- (cc4_mm - pmp4_mm) * 0.10 + pmp4_mm

  expect_equal(res_sandwich$serie_diaria$ch_4[1], ch4_esperado_sandwich, tolerance = 1e-9)
  expect_true(res_sandwich$serie_diaria$ch_4[1] < res_normal$serie_diaria$ch_4[1])
  expect_equal(res_sandwich$serie_diaria$sandwich_seco[1], "Si")

  # Los demas horizontes del primer metro no se ven afectados por el override
  expect_equal(res_sandwich$serie_diaria$ch_1[1], res_normal$serie_diaria$ch_1[1])
  expect_equal(res_sandwich$serie_diaria$ch_2[1], res_normal$serie_diaria$ch_2[1])
  expect_equal(res_sandwich$serie_diaria$ch_3[1], res_normal$serie_diaria$ch_3[1])
})

test_that("calcular_balance_hidrico soporta suelos con menos de 8 horizontes (segundo metro = horizonte 5 en adelante, hasta 4 -- confirmado por CRC-SAS 2026-08-13, batch Junin/IN65JUNI03)", {
  entrada <- readr::read_csv(
    testthat::test_path("fixtures", "balance_hidrico_entrada.csv"),
    col_types = readr::cols(date = readr::col_date(), pp = readr::col_double(),
                             eto = readr::col_double(), prof = readr::col_double(),
                             kcb = readr::col_double())
  )
  clima_estacion <- dplyr::select(entrada, "date", "pp", "eto")
  serie_profundidad_radicular <- tibble::tibble(date = entrada$date, profundidad_radical_m = entrada$prof)
  serie_kcb <- tibble::tibble(date = entrada$date, kcb = entrada$kcb)

  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  suelo_8h <- obtener_suelo_balance_hidrico(parametros, "IN64MARC02")
  constantes <- leer_constantes_yaml()

  # Suelo sintetico de 5 horizontes (mismos valores fisicos que IN64MARC02
  # para los horizontes 1-5, sin los horizontes 6-8) -- imita la forma real
  # de IN65JUNI03 (5 horizontes, hasta 1.2m) sin depender del xlsx externo
  # de condiciones iniciales del batch de Junin.
  suelo_5h <- suelo_8h
  suelo_5h$horizontes <- suelo_8h$horizontes[1:5, ]

  res_8h <- calcular_balance_hidrico(
    clima_estacion, "1983-03-01", serie_profundidad_radicular, serie_kcb, suelo_8h,
    rastrojo_clase = "Moderada", humedad_inicial_clase_m1 = "Hu", humedad_inicial_clase_m2 = "Hu",
    constantes = constantes
  )
  res_5h <- calcular_balance_hidrico(
    clima_estacion, "1983-03-01", serie_profundidad_radicular, serie_kcb, suelo_5h,
    rastrojo_clase = "Moderada", humedad_inicial_clase_m1 = "Hu", humedad_inicial_clase_m2 = "Hu",
    constantes = constantes
  )

  # Primer metro (horizontes 1-4): identico en ambos casos, mismo split de
  # condicion inicial y mismos horizontes fisicos -- no deberia cambiar por
  # tener menos horizontes en el segundo metro.
  expect_equal(res_5h$serie_diaria$ch_1[1], res_8h$serie_diaria$ch_1[1])
  expect_equal(res_5h$serie_diaria$ch_4[1], res_8h$serie_diaria$ch_4[1])
  expect_equal(res_5h$serie_diaria$au_pct_m1[1], res_8h$serie_diaria$au_pct_m1[1])

  # Segundo metro: en el suelo de 5 horizontes solo cuenta el horizonte 5
  # (no 5-8 como en el de 8). El dia 1 es un caso particular: como
  # .contenido_hidrico_inicial() aplica la MISMA fraccion au_inicial_m2 a
  # todos los horizontes del segundo metro, el *porcentaje* au_pct_m2 da
  # exactamente au_inicial_m2 sin importar cuantos horizontes se sumen (por
  # eso no sirve para distinguir 5 vs 8 horizontes) -- lo que si difiere es
  # au_mm_m2 (agua util en mm, absoluta), que suma menos horizontes.
  horiz <- suelo_5h$horizontes
  espesor_5 <- horiz$pfh_m[5] - horiz$pfh_m[4]
  pmp5_mm <- horiz$pmp[5] * espesor_5 * 1000
  cc5_mm <- horiz$cc[5] * espesor_5 * 1000
  ch5_dia1 <- res_5h$serie_diaria$ch_5[1]
  au_mm_m2_esperado <- ch5_dia1 - pmp5_mm

  expect_equal(res_5h$serie_diaria$au_mm_m2[1], au_mm_m2_esperado, tolerance = 1e-9)
  expect_false(isTRUE(all.equal(res_5h$serie_diaria$au_mm_m2[1], res_8h$serie_diaria$au_mm_m2[1])))
  expect_equal(res_5h$serie_diaria$au_pct_m2[1], 0.90, tolerance = 1e-9)

  # No debe haber columnas de horizontes que no existen en este suelo.
  expect_false(any(c("ch_6", "ch_7", "ch_8") %in% names(res_5h$serie_diaria)))
})
