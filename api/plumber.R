# API de la plataforma de escenarios individuales (balancehidrico). Un
# unico endpoint que corre un escenario ad-hoc (no sale de la hoja
# `escenarios` del xlsx de diseno, lo arma un usuario desde el frontend)
# contra todos los anios de clima disponibles de la estacion elegida, y
# devuelve las salidas del metodo agregadas (Media/P20/P50/P80/Desvio/IQR).
#
# El paquete balancehidrico se instala formalmente en la imagen (ver
# api/Dockerfile) -- no se usa devtools::load_all(). Los library()/source()
# de las dependencias (scripts/lib_simular.R, api/agregar_salidas.R) NO
# van aca -- plumber::pr() cambia el working directory al directorio de
# este archivo mientras lo parsea, lo que rompe rutas relativas a la raiz
# del repo. Van en api/run.R, el entrypoint real (local y Docker), que se
# ejecuta ANTES de pr("api/plumber.R") con cwd = raiz del repo.

RUTA_SQLITE <- Sys.getenv("BALANCE_HIDRICO_SQLITE", unset = "balance_hidrico.sqlite")

#* @apiTitle balancehidrico -- API de escenarios individuales
#* @apiDescription Corre un escenario contra todos los anios de clima
#*   disponibles de una estacion y devuelve las salidas del metodo
#*   agregadas por variable.

#* Corre un escenario individual contra todos los anios disponibles de
#* la estacion y devuelve las salidas agregadas.
#* @param req:object Body JSON: estacion (omm_id), suelo, cultivo,
#*   cultivar, siembra: {dia, mes}, monitoreo: {dia, mes},
#*   cantidad_rastrojo, au_m1, au_m2 (codigos internos de
#*   inst/extdata/constantes.yml, no la etiqueta mostrada al usuario),
#*   sandwich_seco ("Si"/"No").
#* @serializer unboxedJSON
#* @post /simular
function(req, res) {
  body <- req$body

  campos_requeridos <- c(
    "estacion", "suelo", "cultivo", "cultivar", "siembra", "monitoreo",
    "cantidad_rastrojo", "au_m1", "au_m2", "sandwich_seco"
  )
  faltantes <- setdiff(campos_requeridos, names(body))
  if (length(faltantes) > 0) {
    res$status <- 400
    return(list(error = sprintf("Faltan campos: %s", paste(faltantes, collapse = ", "))))
  }

  con <- DBI::dbConnect(RSQLite::SQLite(), RUTA_SQLITE, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  resultado <- tryCatch(
    {
      clima_estacion <- leer_clima_estacion_sqlite(con, body$estacion)

      estacion_raw <- DBI::dbGetQuery(con, "SELECT latitud FROM estaciones WHERE omm_id = ?", params = list(body$estacion))
      if (nrow(estacion_raw) == 0) rlang::abort(sprintf("Estacion '%s' no encontrada", body$estacion))

      suelos_raw <- DBI::dbGetQuery(con, "SELECT * FROM suelos WHERE suelo = ?", params = list(body$suelo))
      if (nrow(suelos_raw) == 0) rlang::abort(sprintf("Suelo '%s' no encontrado", body$suelo))
      horizontes_raw <- DBI::dbGetQuery(
        con, "SELECT * FROM horizontes WHERE suelo = ? ORDER BY pfh_m", params = list(body$suelo)
      )
      cultivares_raw <- DBI::dbGetQuery(con, "SELECT * FROM cultivares WHERE cultivo = ?", params = list(body$cultivo))
      if (nrow(cultivares_raw) == 0) rlang::abort(sprintf("Cultivo '%s' no encontrado", body$cultivo))

      parametros <- list(
        estaciones = stats::setNames(
          list(list(latitud = estacion_raw$latitud[1])), as.character(body$estacion)
        ),
        suelos = .armar_suelos(suelos_raw, horizontes_raw),
        cultivos = .armar_cultivos(cultivares_raw)
      )
      constantes <- leer_constantes_yaml()

      anios_disponibles <- unique(lubridate::year(clima_estacion$date))
      grid <- construir_grid_escenario_individual(
        estacion = as.character(body$estacion), suelo = body$suelo,
        cultivo = body$cultivo, cultivar = body$cultivar,
        mes_siembra = body$siembra$mes, dia_siembra = body$siembra$dia,
        mes_monitoreo = body$monitoreo$mes, dia_monitoreo = body$monitoreo$dia,
        rastrojo_clase = body$cantidad_rastrojo,
        humedad_inicial_clase_m1 = body$au_m1,
        humedad_inicial_clase_m2 = body$au_m2,
        sandwich_seco_inicial = identical(body$sandwich_seco, "Si"),
        anios_disponibles = anios_disponibles
      )

      salidas_lista <- list()
      errores <- 0L
      for (i in seq_len(nrow(grid))) {
        fila <- grid[i, ]
        sim <- tryCatch(
          {
            clima_recortada <- .recortar_clima_escenario(
              clima_estacion = clima_estacion, cultivo = fila$cultivo, cultivar = fila$cultivar,
              siembra = fila$siembra, fecha_inicio_balance = fila$fecha_inicio_balance,
              parametros = parametros
            )
            simular_escenario(
              cultivo = fila$cultivo, cultivar = fila$cultivar, estacion = fila$estacion,
              suelo = fila$suelo, siembra = fila$siembra, fecha_inicio_balance = fila$fecha_inicio_balance,
              rastrojo_clase = fila$rastrojo_clase,
              humedad_inicial_clase_m1 = fila$humedad_inicial_clase_m1,
              humedad_inicial_clase_m2 = fila$humedad_inicial_clase_m2,
              sandwich_seco_inicial = fila$sandwich_seco_inicial,
              clima_completo = clima_recortada, parametros = parametros, constantes = constantes
            )
          },
          error = function(e) e
        )

        if (inherits(sim, "error")) {
          errores <- errores + 1L
        } else {
          salidas_lista[[length(salidas_lista) + 1L]] <- dplyr::bind_cols(
            tibble::tibble(anio = fila$anio), sim$salidas_tabla
          )
        }
      }

      if (length(salidas_lista) == 0) {
        rlang::abort("Ningun anio pudo simularse para este escenario")
      }

      salidas_tabla <- dplyr::bind_rows(salidas_lista)
      list(
        anios_simulados = length(salidas_lista),
        anios_con_error = errores,
        salidas = agregar_salidas_multianio(salidas_tabla),
        # Detalle por anio (sin agregar) para mostrar debajo de la tabla
        # principal en la UI -- mismas columnas que salidas_tabla, mas `anio`.
        anios = salidas_tabla[order(salidas_tabla$anio), ]
      )
    },
    error = function(e) e
  )

  if (inherits(resultado, "error")) {
    res$status <- 422
    return(list(error = conditionMessage(resultado)))
  }
  resultado
}
