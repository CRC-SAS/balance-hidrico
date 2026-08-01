test_that("calcular_temperatura_media usa tm si esta disponible", {
  expect_equal(calcular_temperatura_media(30, 20, 27.8), 27.8)
})

test_that("calcular_temperatura_media recalcula (tx+tn)/2 si tm es NA (duda F-7)", {
  expect_equal(calcular_temperatura_media(30, 20, NA), 25)
  expect_equal(calcular_temperatura_media(35.2, 21.1), (35.2 + 21.1) / 2)
})

test_that("calcular_declinacion_solar coincide con la hoja clima del xlsx v3 (estacion 87480)", {
  # documentacion/referencias/v3/Calculos fenologia y balance hidrico.xlsx,
  # hoja `clima`, filas 2 y 100. Formula "vigente" confirmada por CRC-SAS
  # 2026-08-01 (con correccion por crepusculo civil); reemplaza a la version
  # anterior (xlsx original/v2), que devolvia grados en vez de radianes.
  expect_equal(calcular_declinacion_solar(1), -0.4031085511534435, tolerance = 1e-9)
  expect_equal(calcular_declinacion_solar(99), 0.11663228492660306, tolerance = 1e-9)
})

test_that("calcular_fotoperiodo coincide con la hoja clima del xlsx v3 (estacion 87480, lat -32.9036)", {
  expect_equal(calcular_fotoperiodo(1, -32.9036), 15.238376167796428, tolerance = 1e-6)
  expect_equal(calcular_fotoperiodo(99, -32.9036), 12.379581666296556, tolerance = 1e-6)
})

test_that("calcular_fotoperiodo recorta el argumento del arco-coseno en -0.87 (IF de la celda J2)", {
  # Formula vigente (v3) solo tiene clamp inferior, no simetrico como la
  # version anterior -- verificar que el tope se aplica igual que en Excel:
  # 7.639*acos(-0.87), no un valor "fisico" de 24h de dia polar. Latitud
  # -58 en verano austral (doy 355) empuja el argumento por debajo de -0.87
  # sin acercarse a la singularidad de cos(lat)~0 (evitar lat extremas tipo
  # -89.9, donde el argumento se dispara y deja de ser un test util del
  # clamp en si).
  tope_esperado <- 7.639 * acos(-0.87)
  expect_equal(calcular_fotoperiodo(355, -58), tope_esperado, tolerance = 1e-9)
})

test_that("calcular_fotoperiodo no tiene clamp superior (NaN fuera del rango real de Argentina)", {
  # A diferencia de la formula anterior, esta no maneja el caso opuesto
  # (dia/noche polar por el otro extremo) -- documentado como comportamiento
  # esperado (paridad con el #NUM! de Excel), no un bug. No ocurre para
  # ninguna estacion real de Argentina (ver roxygen de calcular_fotoperiodo).
  expect_true(is.nan(suppressWarnings(calcular_fotoperiodo(172, -89.9))))
})

test_that("calcular_fotoperiodo es aprox. constante en el ecuador todo el anio", {
  # Con la correccion de crepusculo civil el valor en el ecuador no es ~12h
  # sino ~12.87h (12h + el margen de crepusculo) -- lo que se mantiene
  # estable es la falta de variacion estacional, no el valor absoluto de 12h.
  expect_equal(calcular_fotoperiodo(1, 0), 12.870698612719234, tolerance = 1e-6)
  expect_equal(calcular_fotoperiodo(172, 0), 12.872978863950838, tolerance = 1e-6)
})
