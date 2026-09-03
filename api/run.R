#!/usr/bin/env Rscript
# Entrypoint de la API de la plataforma. Se corre con cwd = raiz del
# repo (local: `Rscript api/run.R` desde la raiz; Docker: WORKDIR /app,
# ver api/Dockerfile) -- carga las dependencias con rutas relativas a la
# raiz ANTES de que plumber::pr() cambie el working directory al
# directorio de api/plumber.R para parsearlo.
suppressPackageStartupMessages({
  library(balancehidrico)
  library(plumber)
  library(DBI)
  library(RSQLite)
})

source("scripts/lib_simular.R")
source("api/agregar_salidas.R")

# Resuelto a ruta absoluta ACA (cwd todavia = raiz del repo, garantizado)
# -- plumber::pr() cambia el working directory al parsear api/plumber.R,
# asi que una ruta relativa leida desde ahi puede resolver distinto.
Sys.setenv(BALANCE_HIDRICO_SQLITE = normalizePath(Sys.getenv("BALANCE_HIDRICO_SQLITE", unset = "balance_hidrico.sqlite")))

pr <- plumber::pr("api/plumber.R")
pr$run(host = "0.0.0.0", port = as.integer(Sys.getenv("PORT", "8000")))
