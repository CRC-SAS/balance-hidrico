test_that("calcular_temperatura_media usa tm si esta disponible", {
  expect_equal(calcular_temperatura_media(30, 20, 27.8), 27.8)
})

test_that("calcular_temperatura_media recalcula (tx+tn)/2 si tm es NA (duda F-7)", {
  expect_equal(calcular_temperatura_media(30, 20, NA), 25)
  expect_equal(calcular_temperatura_media(35.2, 21.1), (35.2 + 21.1) / 2)
})

test_that("calcular_declinacion_solar coincide con la hoja clima del xlsx v2 (estacion 87480)", {
  # doc/v2/Calculos fenologia y balance hidrico.xlsx, hoja `clima`, filas 2 y 100
  expect_equal(calcular_declinacion_solar(1), -23.011636727869238, tolerance = 1e-6)
  expect_equal(calcular_declinacion_solar(99), 7.150402718189978, tolerance = 1e-6)
})

test_that("calcular_fotoperiodo coincide con la hoja clima del xlsx v2 (estacion 87480, lat -32.9036)", {
  expect_equal(calcular_fotoperiodo(1, -32.9036), 14.12666361055725, tolerance = 1e-6)
  expect_equal(calcular_fotoperiodo(99, -32.9036), 11.379235874068705, tolerance = 1e-6)
})

test_that("calcular_fotoperiodo devuelve 0h en noche polar y 24h en dia polar", {
  # Latitud extrema (-89.9): dia ~172 (invierno austral, declinacion positiva) -> sol no sale
  expect_equal(calcular_fotoperiodo(172, -89.9), 0)
  # dia ~355 (verano austral, declinacion muy negativa) -> sol no se pone
  expect_equal(calcular_fotoperiodo(355, -89.9), 24)
})

test_that("calcular_fotoperiodo es simetrica en el ecuador (~12h todo el anio)", {
  expect_equal(calcular_fotoperiodo(1, 0), 12, tolerance = 0.05)
  expect_equal(calcular_fotoperiodo(172, 0), 12, tolerance = 0.05)
})
