# Imagen de la API R/plumber de la plataforma de escenarios individuales
# (ver /home/santiago/.claude/plans/atomic-roaming-wadler.md). El paquete
# balancehidrico se instala formalmente (R CMD INSTALL), no
# devtools::load_all() -- decision explicita para el container de
# produccion.
#
# Build desde la RAIZ del repo (no desde api/), para poder copiar
# DESCRIPTION/R/scripts/balance_hidrico.sqlite:
#   docker build -f api/Dockerfile -t balancehidrico-api .
FROM rocker/r-ver:4.3.0

# libsodium-dev: dependencia de sistema del paquete R 'sodium', que a su
# vez es dependencia dura de 'plumber' -- sin esto, la instalacion de
# 'sodium' falla en silencio (exit 0 del RUN igual, install.packages()
# no propaga el fallo de un paquete individual como error de shell) y
# 'plumber' queda sin instalar, produciendo una imagen que arranca y
# crashea recien al levantar el container. Encontrado asi en la primera
# build.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libsqlite3-dev \
    libsodium-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Paquete balancehidrico: se instala con sus dependencias declaradas en
# DESCRIPTION (Imports), mas plumber/DBI/RSQLite (usadas solo por
# scripts/api/, no son dependencias del paquete en si -- mismo criterio
# que readxl para scripts/construir_base_datos.R, no se agregan a
# DESCRIPTION). Cada paso verifica explicitamente que package_version()
# resuelva, para que un fallo silencioso de install.packages() rompa el
# build en vez de producir una imagen que parece armada pero no arranca.
COPY DESCRIPTION NAMESPACE ./
COPY R/ R/
COPY man/ man/
COPY inst/ inst/
RUN R -e "install.packages('remotes', repos = 'https://cloud.r-project.org'); \
          stopifnot(requireNamespace('remotes', quietly = TRUE))"
# dependencies = solo Depends/Imports/LinkingTo -- en produccion no hace
# falta testthat ni el resto de Suggests (que ademas arrastran su propia
# cadena fragil, ver hallazgo de build real de esta imagen).
RUN R -e "remotes::install_deps('.', dependencies = c('Depends', 'Imports', 'LinkingTo'), repos = 'https://cloud.r-project.org')"
# R CMD INSTALL falla fuerte si algun Import declarado no esta
# instalado -- es el chequeo real de que install_deps() de arriba trajo
# todo lo necesario (mejor que comparar contra dev_package_deps(), que
# en la practica dio falsos positivos de paquetes "faltantes" que en
# realidad no hacian falta).
RUN R CMD INSTALL . \
    && R -e "stopifnot(requireNamespace('balancehidrico', quietly = TRUE))"
RUN R -e "install.packages(c('plumber', 'DBI', 'RSQLite'), repos = 'https://cloud.r-project.org'); \
          stopifnot(requireNamespace('plumber', quietly = TRUE), \
                    requireNamespace('DBI', quietly = TRUE), \
                    requireNamespace('RSQLite', quietly = TRUE))"

# scripts/lib_simular.R + api/ se copian preservando la misma estructura
# relativa que el repo (no se aplanan) para que source("scripts/lib_simular.R")/
# source("api/agregar_salidas.R") en api/run.R resuelvan igual que en local.
COPY scripts/lib_simular.R scripts/lib_simular.R
COPY api/ api/
COPY balance_hidrico.sqlite balance_hidrico.sqlite

ENV BALANCE_HIDRICO_SQLITE=/app/balance_hidrico.sqlite
ENV PORT=8000
EXPOSE 8000

CMD ["Rscript", "api/run.R"]
