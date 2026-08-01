test_that("leer_clima_csv agrega eto cuando esta presente en el CSV", {
  clima <- leer_clima_csv(system.file("extdata", "clima_ejemplo.csv", package = "balancehidrico"))
  expect_true("eto" %in% names(clima))
  expect_false(anyNA(clima$eto))
  expect_equal(clima$eto[clima$date == as.Date("1983-01-01")], 6.5)
})

test_that("leer_clima_csv deja eto en NA si la columna no esta en el CSV", {
  archivo <- tempfile(fileext = ".csv")
  readr::write_csv(
    tibble::tibble(station_id = "1", date = as.Date("2020-01-01") + 0:2, tx = 30, tn = 15),
    archivo
  )
  # readr avisa (no falla) que tm/pp/eto no estan en el CSV -- comportamiento
  # esperado y ya presente antes de agregar eto (col_types declara columnas
  # opcionales que el archivo no tiene).
  clima <- suppressWarnings(leer_clima_csv(archivo))
  expect_true("eto" %in% names(clima))
  expect_true(all(is.na(clima$eto)))
})

test_that("leer_constantes_yaml devuelve rastrojo y humedad_inicial con los valores del xlsx v3", {
  constantes <- leer_constantes_yaml()
  expect_equal(constantes$rastrojo$Baja, 1)
  expect_equal(constantes$rastrojo$Moderada, 0.8)
  expect_equal(constantes$rastrojo$Muy_Alta, 0.5)
  expect_equal(constantes$humedad_inicial$Se, 0.10)
  expect_equal(constantes$humedad_inicial$mS, 0.35)
  expect_equal(constantes$humedad_inicial$mH, 0.65)
  expect_equal(constantes$humedad_inicial$Hu, 0.90)
})

test_that("leer_constantes_yaml lanza error si el archivo no existe", {
  expect_error(leer_constantes_yaml("/no/existe/constantes.yml"))
})

test_that("obtener_factor_rastrojo valida la clase y aborta listando las disponibles", {
  constantes <- leer_constantes_yaml()
  expect_equal(obtener_factor_rastrojo(constantes, "Moderada"), 0.8)
  expect_error(obtener_factor_rastrojo(constantes, "Alta"), "Disponibles")
})

test_that("obtener_fraccion_humedad_inicial valida la clase y aborta listando las disponibles", {
  constantes <- leer_constantes_yaml()
  expect_equal(obtener_fraccion_humedad_inicial(constantes, "Se"), 0.10)
  expect_error(obtener_fraccion_humedad_inicial(constantes, "Humedo"), "Disponibles")
})

test_that("obtener_suelo_balance_hidrico arma la estructura completa para IN64MARC02", {
  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  suelo <- obtener_suelo_balance_hidrico(parametros, "IN64MARC02")

  expect_equal(suelo$cn, 77)
  expect_equal(suelo$kl, 0.1)
  expect_equal(suelo$um, 0.5)
  expect_equal(suelo$u, 8)
  expect_equal(suelo$dr, 0.6)
  expect_equal(nrow(suelo$horizontes), 8)
  expect_equal(suelo$horizontes$nombre[1], "Ap")
  expect_equal(suelo$horizontes$pfh_m, c(0.2, 0.4, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1))
})

test_that("obtener_suelo_balance_hidrico aborta si el suelo no tiene los campos de Paso 4", {
  parametros <- leer_parametros_yaml(system.file("extdata", "parametros_ejemplo.yml", package = "balancehidrico"))
  # RC00000001 solo tiene profundidad_maxima_m (Paso 2), no horizontes/CN/kl/etc (Paso 4)
  expect_error(obtener_suelo_balance_hidrico(parametros, "RC00000001"), "Paso 4")
  expect_error(obtener_suelo_balance_hidrico(parametros, "NO_EXISTE"))
})
