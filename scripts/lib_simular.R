# Funciones compartidas por scripts/simular.R y scripts/simular_batch.R.
# Sourced con cwd = raiz del repo. No es parte del paquete instalable (sin
# roxygen, no se toca R/NAMESPACE/man para esto).

.default_si_null <- function(x, default) if (is.null(x)) default else x

.resolver_ruta <- function(ruta, base_dir) {
  if (is.null(ruta)) return(NULL)
  if (grepl("^(/|~|[A-Za-z]:)", ruta)) ruta else file.path(base_dir, ruta)
}

# --- Escenario puntual (scripts/simular.R) ----------------------------------

leer_inputs_comunes <- function(config, config_dir) {
  ruta_clima <- .resolver_ruta(config$clima, config_dir)
  ruta_parametros <- .resolver_ruta(config$parametros, config_dir)
  ruta_constantes <- .resolver_ruta(config$constantes, config_dir)

  clima_completo <- leer_clima_csv(ruta_clima)
  parametros <- leer_parametros_yaml(ruta_parametros)
  constantes <- if (is.null(ruta_constantes)) leer_constantes_yaml() else leer_constantes_yaml(ruta_constantes)

  list(clima_completo = clima_completo, parametros = parametros, constantes = constantes)
}

# Nucleo puro: Pasos 1-5 para un escenario ya resuelto (fechas/clases ya
# concretas, no rutas ni YAML). Compartido por simular.R y simular_batch.R.
# Los rlang::abort() de los obtener_*() de R/io.R (estacion sin clima, suelo
# sin campos de Paso 4, cultivar inexistente, etc.) se propagan tal cual --
# quien llama (el batch) los envuelve en tryCatch, este nucleo no valida de mas.
simular_escenario <- function(cultivo, cultivar, estacion, suelo, siembra,
                               fecha_inicio_balance, rastrojo_clase,
                               humedad_inicial_clase_m1, humedad_inicial_clase_m2,
                               sandwich_seco_inicial = FALSE,
                               clima_completo, parametros, constantes) {
  clima <- clima_completo[clima_completo$station_id == as.character(estacion), ]
  if (nrow(clima) == 0) {
    rlang::abort(sprintf("No hay datos climaticos para la estacion '%s'", estacion))
  }

  p_cultivar <- obtener_parametros_cultivo(parametros, cultivo, cultivar)
  profundidad_maxima_suelo <- obtener_profundidad_maxima_suelo(parametros, suelo)
  suelo_balance <- obtener_suelo_balance_hidrico(parametros, suelo)

  fenologia <- calcular_fenologia(
    cultivo = cultivo,
    cultivar = cultivar,
    clima_estacion = clima,
    fecha_siembra = siembra,
    parametros = parametros
  )

  raices <- calcular_profundidad_radicular(
    clima_estacion = clima,
    fecha_emergencia = fenologia$hitos$emergencia,
    fecha_hito2 = fenologia$hitos$hito2,
    tb_c = p_cultivar$raiz$tb_c,
    pr_s_e = p_cultivar$raiz$pr_s_e,
    pr = p_cultivar$raiz$pr,
    profundidad_maxima_suelo = profundidad_maxima_suelo
  )

  kcb <- calcular_curva_kcb(
    serie_ut_simple = fenologia$serie_diaria,
    ut_fkcbini = p_cultivar$ut_e_fkcbini,
    ut_ikcbmax = p_cultivar$ut_e_ikcbmax,
    kcb_ini = p_cultivar$kcb$kcb_ini,
    kcb_max = p_cultivar$kcb$kcb_max
  )

  balance <- calcular_balance_hidrico(
    clima_estacion = clima,
    fecha_inicio = fecha_inicio_balance,
    serie_profundidad_radicular = raices,
    serie_kcb = kcb,
    suelo = suelo_balance,
    rastrojo_clase = rastrojo_clase,
    humedad_inicial_clase_m1 = humedad_inicial_clase_m1,
    humedad_inicial_clase_m2 = humedad_inicial_clase_m2,
    constantes = constantes,
    sandwich_seco_inicial = sandwich_seco_inicial
  )

  salidas <- calcular_salidas(clima, siembra, fenologia$hitos, balance$serie_diaria)
  salidas_tabla <- dplyr::bind_cols(
    tibble::tibble(eventos_lluvia_10mm_14a_7d_siembra = salidas$eventos_lluvia_10mm_14a_7d_siembra),
    salidas$estado_hidrico_siembra,
    tibble::tibble(confort_hidrico = salidas$confort_hidrico)
  )

  serie_diaria <- fenologia$serie_diaria
  serie_diaria <- dplyr::left_join(serie_diaria, raices, by = "date")
  serie_diaria <- dplyr::left_join(serie_diaria, kcb, by = "date")

  list(
    hitos = fenologia$hitos,
    serie_diaria = serie_diaria,
    balance_diario = balance$serie_diaria,
    salidas_tabla = salidas_tabla
  )
}

# --- Batch (scripts/simular_batch.R) ----------------------------------------

# Claves de `cultivares` (formato largo) que van dentro de la sub-lista
# `raiz`/`kcb` de cada cultivo, en vez de top-level -- ver
# inst/extdata/parametros_ejemplo.yml para la forma anidada de referencia.
.claves_raiz <- c("pr_s_e", "pr", "tb_c")
.claves_kcb <- c("kcb_ini", "kcb_max")

.clave_parametro_cultivo <- function(parametro) {
  dplyr::case_when(
    parametro == "KcbIni" ~ "kcb_ini",
    parametro == "KcbMax" ~ "kcb_max",
    TRUE ~ tolower(gsub("-", "_", parametro))
  )
}

# Convierte la hoja `cultivares` (cultivo, cultivar, parametro, valor, unidad)
# en la lista anidada que espera obtener_parametros_cultivo() --
# parametros$cultivos$<cultivo>[$raiz/$kcb] + $cultivares$<cultivar>.
.armar_cultivos <- function(cultivares) {
  cultivares$clave <- .clave_parametro_cultivo(cultivares$parametro)
  cultivares$valor_num <- suppressWarnings(as.numeric(cultivares$valor))

  cultivos <- list()
  for (cv in unique(cultivares$cultivo)) {
    filas_cv <- cultivares[cultivares$cultivo == cv, ]

    top <- list()
    raiz <- list()
    kcb <- list()
    filas_top <- filas_cv[is.na(filas_cv$cultivar), ]
    for (i in seq_len(nrow(filas_top))) {
      clave <- filas_top$clave[i]
      valor <- filas_top$valor_num[i]
      if (clave %in% .claves_raiz) {
        raiz[[clave]] <- valor
      } else if (clave %in% .claves_kcb) {
        kcb[[clave]] <- valor
      } else {
        top[[clave]] <- valor
      }
    }

    cultivares_lista <- list()
    filas_cultivar <- filas_cv[!is.na(filas_cv$cultivar), ]
    for (cultivar in unique(filas_cultivar$cultivar)) {
      filas_c <- filas_cultivar[filas_cultivar$cultivar == cultivar, ]
      params_c <- stats::setNames(as.list(filas_c$valor_num), filas_c$clave)
      cultivares_lista[[cultivar]] <- params_c
    }

    cultivos[[cv]] <- c(top, list(raiz = raiz, kcb = kcb, cultivares = cultivares_lista))
  }
  cultivos
}

# Deriva parametros$suelos a partir de las hojas `suelos` + `horizontes`.
# profundidad_maxima_m no viene explicita -- se deriva como el pfh_m maximo
# de cada suelo (mismo patron que ya usa IN64MARC02 en
# inst/extdata/parametros_ejemplo.yml, donde ese campo coincide exacto con
# su ultimo horizonte).
.armar_suelos <- function(suelos, horizontes) {
  suelos_lista <- list()
  for (i in seq_len(nrow(suelos))) {
    id_suelo <- suelos$suelo[i]
    horiz_suelo <- horizontes[horizontes$suelo == id_suelo, ]
    horiz_suelo <- horiz_suelo[order(horiz_suelo$pfh_m), ]

    horizontes_lista <- lapply(seq_len(nrow(horiz_suelo)), function(j) {
      list(
        nombre = horiz_suelo$horiz[j],
        pfh_m = horiz_suelo$pfh_m[j],
        pmp = horiz_suelo$pmp[j],
        cc = horiz_suelo$cc[j],
        sat = horiz_suelo$sat[j]
      )
    })

    suelos_lista[[id_suelo]] <- list(
      cn = suelos$cn[i],
      kl = suelos$kl[i],
      um = suelos$um[i],
      u = suelos$u[i],
      dr = suelos$dr[i],
      profundidad_maxima_m = max(horiz_suelo$pfh_m),
      horizontes = horizontes_lista
    )
  }
  suelos_lista
}

# Lee condiciones_iniciales.xlsx (6 hojas: estaciones, clima, suelos,
# horizontes, cultivares, escenarios) y devuelve
# list(clima_completo, parametros, constantes, escenarios) -- misma forma
# que consume simular_escenario(), analoga a leer_inputs_comunes() pero para
# el input de batch.
leer_condiciones_iniciales_xlsx <- function(path, semilla_imputacion = 1234) {
  if (!file.exists(path)) {
    rlang::abort(glue::glue("No existe el archivo de condiciones iniciales: {path}"))
  }

  estaciones <- readxl::read_excel(path, sheet = "estaciones")
  if (nrow(estaciones) != 1) {
    rlang::abort(
      "leer_condiciones_iniciales_xlsx() asume una sola estacion por batch, ",
      glue::glue("la hoja 'estaciones' tiene {nrow(estaciones)} filas")
    )
  }
  station_id <- as.character(estaciones$omm_id[1])
  latitud <- as.numeric(estaciones$latitud[1])

  suelos_raw <- readxl::read_excel(path, sheet = "suelos")
  suelos_raw <- dplyr::transmute(
    suelos_raw,
    suelo = suelo,
    u = suppressWarnings(as.numeric(U)),
    dr = suppressWarnings(as.numeric(DR)),
    cn = suppressWarnings(as.numeric(CN)),
    kl = suppressWarnings(as.numeric(kl)),
    um = suppressWarnings(as.numeric(Um))
  )
  horizontes_raw <- readxl::read_excel(path, sheet = "horizontes")
  horizontes_raw <- dplyr::transmute(
    horizontes_raw,
    suelo = suelo,
    horiz = Horiz,
    pfh_m = suppressWarnings(as.numeric(PFH)),
    pmp = suppressWarnings(as.numeric(PMP)),
    cc = suppressWarnings(as.numeric(CC)),
    sat = suppressWarnings(as.numeric(Sat))
  )

  cultivares_raw <- readxl::read_excel(path, sheet = "cultivares")

  parametros <- list(
    estaciones = stats::setNames(list(list(latitud = latitud)), station_id),
    suelos = .armar_suelos(suelos_raw, horizontes_raw),
    cultivos = .armar_cultivos(cultivares_raw)
  )

  clima_raw <- readxl::read_excel(path, sheet = "clima")
  clima_completo <- tibble::tibble(
    station_id = as.character(clima_raw$omm_id),
    date = as.Date(clima_raw$fecha),
    doy = lubridate::yday(date),
    tx = suppressWarnings(as.numeric(clima_raw$tmax)),
    tn = suppressWarnings(as.numeric(clima_raw$tmin)),
    tm = suppressWarnings(as.numeric(clima_raw$tmed)),
    pp = suppressWarnings(as.numeric(clima_raw$prcp))
  )
  clima_completo <- completar_gaps_clima(clima_completo, semilla = semilla_imputacion)
  clima_completo$eto <- calcular_eto_hargreaves(
    clima_completo$doy, latitud, clima_completo$tx, clima_completo$tn, clima_completo$tm
  )

  escenarios <- readxl::read_excel(path, sheet = "escenarios")

  constantes <- leer_constantes_yaml()

  list(
    clima_completo = clima_completo,
    parametros = parametros,
    constantes = constantes,
    escenarios = escenarios,
    estacion = station_id
  )
}

# Producto cartesiano de las filas de `escenarios` x anios
# [anio_desde, anio_hasta]. siembra = 1-ene-<anio> + (dda_S - 1) dias
# (maneja bisiestos automaticamente); fecha_inicio_balance = siembra -
# offset_dias.
construir_grid_batch <- function(escenarios, estacion, anio_desde, anio_hasta, offset_dias) {
  anios <- seq.int(anio_desde, anio_hasta)
  grid <- tidyr::crossing(escenarios, anio = anios)

  grid$siembra <- as.Date(sprintf("%d-01-01", grid$anio)) + (grid$dda_S - 1)
  grid$fecha_inicio_balance <- grid$siembra - offset_dias
  grid$id_simulacion <- sprintf("esc%02d_%d", grid$escenario, grid$anio)

  grid <- dplyr::transmute(
    grid,
    id_simulacion = id_simulacion,
    escenario = escenario,
    cultivo = cultivo,
    cultivar = cultivar,
    estacion = estacion,
    suelo = suelo,
    siembra = siembra,
    fecha_inicio_balance = fecha_inicio_balance,
    rastrojo_clase = cantidad_rastrojo,
    humedad_inicial_clase_m1 = au_m1,
    humedad_inicial_clase_m2 = au_m2,
    sandwich_seco_inicial = sandwich_seco == "Si"
  )

  if (any(duplicated(grid$id_simulacion))) {
    rlang::abort("id_simulacion duplicado al construir el grid del batch -- revisar la hoja 'escenarios'")
  }

  grid
}

# --- Escenario individual (api/plumber.R) ------------------------------------

# Determina en que anio calendario cae la fecha de monitoreo de un
# escenario individual (plataforma), dado que se especifica como
# (mes,dia) independiente de la siembra: si el monitoreo cae "despues" de
# la siembra dentro del calendario (mismo criterio que dda_M > dda_S en
# el xlsx original), el monitoreo pertenece al anio anterior al de la
# siembra; si no, al mismo anio. La comparacion se hace en un anio de
# referencia fijo NO bisiesto (2001) -- solo para decidir el cruce de
# anio, no para construir la fecha real (eso lo hace
# construir_grid_escenario_individual() directo desde (anio,mes,dia)).
.resolver_anio_monitoreo <- function(mes_siembra, dia_siembra, mes_monitoreo, dia_monitoreo, anio_siembra) {
  doy_siembra <- lubridate::yday(as.Date(sprintf("2001-%02d-%02d", mes_siembra, dia_siembra)))
  doy_monitoreo <- lubridate::yday(as.Date(sprintf("2001-%02d-%02d", mes_monitoreo, dia_monitoreo)))
  if (doy_monitoreo > doy_siembra) anio_siembra - 1L else anio_siembra
}

# Arma el grid de UN escenario individual (plataforma) -- a diferencia de
# construir_grid_batch(), no sale de la hoja `escenarios` del xlsx, lo
# arma un usuario desde el frontend -- cruzado contra todos los anios de
# clima disponibles de la estacion (`anios_disponibles`). A diferencia de
# construir_grid_batch() (que usa dda_S + un offset fijo en dias), esta
# funcion recibe mes/dia de siembra y monitoreo por separado y arma las
# fechas directo con as.Date(sprintf("%d-%02d-%02d", ...)) por anio -- asi
# "1 de junio" es siempre 1 de junio, sin el corrimiento de un dia que
# tendria hacer aritmetica de dia-del-anio en anios bisiestos.
construir_grid_escenario_individual <- function(estacion, suelo, cultivo, cultivar,
                                                  mes_siembra, dia_siembra,
                                                  mes_monitoreo, dia_monitoreo,
                                                  rastrojo_clase,
                                                  humedad_inicial_clase_m1,
                                                  humedad_inicial_clase_m2,
                                                  sandwich_seco_inicial,
                                                  anios_disponibles) {
  anios <- as.integer(sort(unique(anios_disponibles)))
  siembra <- as.Date(sprintf("%d-%02d-%02d", anios, mes_siembra, dia_siembra))
  anio_monitoreo <- vapply(anios, function(a) {
    .resolver_anio_monitoreo(mes_siembra, dia_siembra, mes_monitoreo, dia_monitoreo, a)
  }, integer(1))
  fecha_inicio_balance <- as.Date(sprintf("%d-%02d-%02d", anio_monitoreo, mes_monitoreo, dia_monitoreo))

  tibble::tibble(
    id_simulacion = sprintf("anio%d", anios),
    anio = anios,
    estacion = estacion,
    suelo = suelo,
    cultivo = cultivo,
    cultivar = cultivar,
    siembra = siembra,
    fecha_inicio_balance = fecha_inicio_balance,
    rastrojo_clase = rastrojo_clase,
    humedad_inicial_clase_m1 = humedad_inicial_clase_m1,
    humedad_inicial_clase_m2 = humedad_inicial_clase_m2,
    sandwich_seco_inicial = sandwich_seco_inicial
  )
}

# Lee la tabla `clima` de la SQLite de la plataforma (ver
# scripts/construir_base_datos.R) para una estacion y la da vuelta a la
# forma que espera simular_escenario() -- station_id/date/doy/tx/tn/tm/pp/eto.
# La SQLite ya viene con gaps rellenados y eto precalculada (ver
# construir_base_datos.R) -- no se reimputa ni se recalcula aca.
leer_clima_estacion_sqlite <- function(con, omm_id) {
  clima_raw <- DBI::dbGetQuery(
    con, "SELECT * FROM clima WHERE omm_id = ? ORDER BY fecha", params = list(omm_id)
  )
  if (nrow(clima_raw) == 0) {
    rlang::abort(sprintf("No hay datos climaticos para la estacion '%s' en la SQLite", omm_id))
  }
  tibble::tibble(
    station_id = as.character(clima_raw$omm_id),
    date = as.Date(clima_raw$fecha),
    doy = lubridate::yday(date),
    tx = clima_raw$tmax,
    tn = clima_raw$tmin,
    tm = clima_raw$tmed,
    pp = clima_raw$prcp,
    eto = clima_raw$eto
  )
}

# Recorta el clima de una estacion a la ventana [fecha_inicio_balance,
# madurez_fisiologica + margen] de un escenario puntual. Solo lo usa
# scripts/simular_batch.R -- simular_escenario()/scripts/simular.R siguen
# recibiendo el clima tal cual (ya viene pre-recortado a mano en los
# fixtures/ejemplos empaquetados, sin cambios de comportamiento ahi).
#
# Necesario porque simular_escenario() -> calcular_balance_hidrico() recorre
# TODAS las filas del clima que se le pasa (no se detiene sola en la
# madurez fisiologica) -- pasarle los ~35 anios completos de clima real del
# batch haria que cada simulacion procese decadas de mas (lento) y,
# ademas, cualquier escenario terminaria topandose con las filas
# placeholder NA del futuro (p.ej. el resto de 2026 sin datos reales
# todavia) sin importar el anio de siembra que se este simulando.
.recortar_clima_escenario <- function(clima_estacion, cultivo, cultivar, siembra,
                                       fecha_inicio_balance, parametros, margen_dias = 0) {
  fenologia_preliminar <- calcular_fenologia(
    cultivo = cultivo, cultivar = cultivar, clima_estacion = clima_estacion,
    fecha_siembra = siembra, parametros = parametros
  )
  siembra <- as.Date(siembra)
  fecha_inicio_balance <- as.Date(fecha_inicio_balance)

  # calcular_salidas() (Paso 5) necesita clima desde siembra-14
  # (calcular_eventos_lluvia_10mm_14a_7d_siembra()) sin importar donde
  # arranca el balance -- calcular_balance_hidrico()/calcular_fenologia()
  # filtran internamente por su propia fecha de inicio (>= fecha_inicio /
  # >= fecha_siembra), asi que incluir filas de mas antes no cambia su
  # resultado. En el batch original fecha_inicio_balance (offset fijo de
  # 90 dias) siempre esta muy por delante de siembra-14, pero en la
  # plataforma el usuario elige "fecha de monitoreo" libremente y puede
  # quedar a menos de 14 dias de la siembra -- sin este min(), el conteo
  # de eventos de lluvia pre-siembra quedaria incompleto sin ningun error.
  fecha_inicio <- min(fecha_inicio_balance, siembra - 14)

  # margen_dias = 0: no hace falta clima despues de la madurez fisiologica
  # para las salidas de Paso 5. Un margen positivo puede empujar la
  # ventana mas alla del limite real de datos para escenarios cuya madurez
  # cae cerca del borde (encontrado con el batch real: escenarios de soja
  # 2025 con madurez 2026-07-31, margen de 15 dias los empujaba a
  # 2026-08-15, mas alla del corte real de 2026-08-11).
  fecha_fin <- fenologia_preliminar$hitos$madurez_fisiologica + margen_dias

  # Si la ventana pedida excede el rango de clima realmente disponible,
  # fallar explicito en vez de devolver una ventana truncada en silencio
  # (encontrado con la plataforma: un anio de siembra en el borde del
  # rango de la estacion, combinado con un monitoreo que cruza al anio
  # anterior -- ver .resolver_anio_monitoreo() -- puede pedir una fecha de
  # inicio anterior al primer dato real de la estacion; sin este chequeo
  # la simulacion corria igual, con menos dias de "spin-up" de los
  # pedidos, sin ningun aviso).
  if (fecha_inicio < min(clima_estacion$date) || fecha_fin > max(clima_estacion$date)) {
    rlang::abort(sprintf(
      "La ventana de simulacion [%s, %s] excede el rango de clima disponible [%s, %s]",
      fecha_inicio, fecha_fin, min(clima_estacion$date), max(clima_estacion$date)
    ))
  }

  clima_estacion[clima_estacion$date >= fecha_inicio & clima_estacion$date <= fecha_fin, ]
}
