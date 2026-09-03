# Agregacion de las salidas de Paso 5 de multiples anios (un escenario
# individual de la plataforma corrido contra todos los anios disponibles
# de una estacion) en las estadisticas que pide "UI Salida" del xlsx de
# diseno -- Media/P20/P50/P80/Desvio/IQR por variable, con
# quantile(type=7) (default de R, confirmado con el usuario). No agrega
# `sandwich_seco` (categorica -- se omite de la respuesta, pendiente de
# definir el criterio de agregacion con CRC-SAS).

.agregar_variable <- function(x) {
  x <- x[!is.na(x)]
  qs <- stats::quantile(x, probs = c(0.2, 0.5, 0.8), type = 7, names = FALSE)
  list(
    media = mean(x), p20 = qs[1], p50 = qs[2], p80 = qs[3],
    desvio = stats::sd(x), iqr = stats::IQR(x, type = 7)
  )
}

# `salidas_tabla`: bind_rows() de los `salidas_tabla` (1 fila c/u) que
# devuelve simular_escenario() para cada anio OK del escenario. Devuelve
# la forma agrupada "siembra"/"cultivo" de UI Salida.
agregar_salidas_multianio <- function(salidas_tabla) {
  variables_siembra <- c("eventos_lluvia_10mm_14a_7d_siembra", "au_pct_m1", "au_pct_m2", "au_pct_total")
  variables_cultivo <- c("confort_hidrico")

  armar_grupo <- function(variables) {
    lapply(variables, function(v) {
      c(list(variable = v), .agregar_variable(salidas_tabla[[v]]))
    })
  }

  list(
    siembra = armar_grupo(variables_siembra),
    cultivo = armar_grupo(variables_cultivo)
  )
}
