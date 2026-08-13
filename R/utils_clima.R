#' Temperatura media diaria
#'
#' Si la temperatura media (`tm`) esta disponible en la base climatica se usa
#' directamente (ver duda F-7 del documento maestro). Si no, se calcula como
#' el promedio aritmetico entre la temperatura maxima y minima.
#'
#' @param tx Numeric. Temperatura maxima diaria (°C).
#' @param tn Numeric. Temperatura minima diaria (°C).
#' @param tm Numeric. Temperatura media diaria (°C), si esta disponible.
#'   `NA` (el default) indica que no esta disponible y debe recomputarse.
#'
#' @return Numeric. Temperatura media diaria (°C).
#' @export
calcular_temperatura_media <- function(tx, tn, tm = NA_real_) {
  dplyr::if_else(is.na(tm), (tx + tn) / 2, tm)
}

#' Declinacion solar
#'
#' Formula "vigente" confirmada por CRC-SAS (2026-08-01, reemplaza la formula
#' anterior en grados por esta, que ya incorpora la correccion por crepusculo
#' civil usada en `calcular_fotoperiodo()`): `0.4093 * sin(0.0172 * (dia_anio
#' - 82.2))`, usada en la hoja `clima` del xlsx de referencia v3 (columna
#' "declinacion solar").
#'
#' @param dia_anio Integer. Dia del anio (1-366).
#'
#' @return Numeric. Declinacion solar en RADIANES (cambio de unidad respecto
#'   de la version anterior de esta funcion, que devolvia grados).
#' @export
calcular_declinacion_solar <- function(dia_anio) {
  0.4093 * sin(0.0172 * (dia_anio - 82.2))
}

#' Fotoperiodo (Fp)
#'
#' Horas de luz solar en funcion del dia del anio y la latitud, siguiendo la
#' formula "vigente" confirmada por CRC-SAS (2026-08-01) de la hoja `clima`
#' del xlsx de referencia v3 (celda `J2`), con correccion por crepusculo
#' civil (`0.1047 = sin(6°)`). La conversion de latitud a radianes usa la
#' constante `0.01745` tal como esta escrita en la formula original de la
#' planilla (una aproximacion de `pi/180`, no el valor exacto) -- reproducir
#' esta constante literal es necesario para igualar los valores cacheados del
#' xlsx dentro de la tolerancia de los tests.
#'
#' A diferencia de la formula anterior, esta NO tiene manejo simetrico de
#' dia/noche polar: solo recorta el argumento del arco-coseno por abajo en
#' `-0.87` (tal cual el `IF` de la celda `J2`), sin ninguna rama para el caso
#' opuesto. Para las latitudes reales de Argentina que cubre esta
#' herramienta (hasta ~-55°, Tierra del Fuego) el argumento nunca llega a
#' superar 1, así que ese caso no está contemplado ni en la planilla ni acá:
#' con una latitud fuera de ese rango la funcion puede devolver `NaN`
#' (mismo comportamiento que un `#NUM!` en Excel).
#'
#' @param dia_anio Integer. Dia del anio (1-366).
#' @param latitud Numeric. Latitud en grados decimales (negativa = hemisferio
#'   sur).
#'
#' @return Numeric. Fotoperiodo en horas.
#' @export
calcular_fotoperiodo <- function(dia_anio, latitud) {
  declinacion <- calcular_declinacion_solar(dia_anio)
  lat_rad <- latitud * 0.01745
  x <- (-sin(lat_rad) * sin(declinacion) - 0.1047) / (cos(lat_rad) * cos(declinacion))
  x <- pmax(x, -0.87)

  7.639 * acos(x)
}

#' Evapotranspiracion de referencia (ETo), metodo Hargreaves-Samani
#'
#' Estima `ETo` (mm/dia) a partir de temperaturas diarias, para cuando la
#' base climatica no trae `ETo` ya calculada (ver seccion 8.10 del manual
#' tecnico). Es una utilidad **opcional**: `leer_clima_csv()` sigue leyendo
#' `eto` como columna de entrada tal cual, sin invocar esta funcion; queda a
#' criterio de quien arma la base climatica (p.ej. un script de
#' preprocesamiento) llamarla para completar `eto` cuando no este
#' disponible.
#'
#' Implementa Hargreaves & Samani (1985) segun las ecuaciones 21-25 y 52 de
#' Allen et al. (1998, FAO-56), portada literal de
#' `evapotranspiracion.hargreaves()` en
#' `balance_agua_suelo/lib/funciones_evapotranspiracion.R` (repo hermano de
#' CRC-SAS). La declinacion solar que usa esta formula (ecuacion 24) es
#' **distinta a proposito** de [calcular_declinacion_solar()]: esta ultima
#' esta calibrada para el fotoperiodo (con correccion de crepusculo civil,
#' confirmada por CRC-SAS para esa formula puntual), no para ETo -- no
#' unificar ambas.
#'
#' @param dia_anio Integer. Dia del anio (1-366).
#' @param latitud Numeric. Latitud en grados decimales (negativa = hemisferio
#'   sur).
#' @param tx Numeric. Temperatura maxima diaria (°C).
#' @param tn Numeric. Temperatura minima diaria (°C).
#' @param tm Numeric. Temperatura media diaria (°C), si esta disponible.
#'   `NA` (el default) indica que no esta disponible y debe recomputarse
#'   (ver [calcular_temperatura_media()]).
#'
#' @return Numeric. `ETo` en mm/dia.
#' @export
calcular_eto_hargreaves <- function(dia_anio, latitud, tx, tn, tm = NA_real_) {
  tm <- calcular_temperatura_media(tx, tn, tm)

  lat_rad <- latitud * pi / 180
  declinacion <- 0.409 * sin(2 * pi * dia_anio / 365 - 1.39)      # Eq. 24
  dr <- 1 + 0.033 * cos(2 * pi * dia_anio / 365)                   # Eq. 23
  ws <- acos(-tan(lat_rad) * tan(declinacion))                     # Eq. 25

  gsc <- 0.0820
  rad_extraterrestre <- (24 * 60 / pi) * gsc * dr *
    (ws * sin(lat_rad) * sin(declinacion) + cos(lat_rad) * cos(declinacion) * sin(ws))  # Eq. 21

  lambda <- 2.45
  0.0023 * (tm + 17.8) * sqrt(tx - tn) * rad_extraterrestre / lambda  # Eq. 52
}
