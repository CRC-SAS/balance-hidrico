# Balance hídrico de cultivos — CRC-SAS

Herramienta de **balance hídrico de cultivos** de CRC-SAS (Centro Regional de
Cambio Climático y Ayuda a la Toma de Decisiones). Implementa el método propio
de CRC-SAS para **trigo, maíz y soja** y está disponible de dos formas: una
plataforma web para uso cotidiano y un paquete de R para uso avanzado.

## 1. Overview

### Para qué sirve

Ayuda a gestionar el riesgo climático en decisiones agrícolas: dada una
localidad, un suelo, un cultivo y una fecha de siembra, estima **cuánta agua
habrá en el suelo a la siembra** y **cuánta agua tendrá disponible el cultivo
durante su período crítico**, comparando contra todos los años de clima
histórico disponibles.

### Qué se calcula

El método simula, día a día y para cada año del clima histórico, cinco pasos
encadenados:

| Paso | Qué calcula |
|---|---|
| 1. **Fenología** | Fechas de los hitos del cultivo (emergencia, período crítico, madurez…) por acumulación de unidades térmicas y fotoperíodo |
| 2. **Profundización radicular** | Hasta qué profundidad llegan las raíces, día a día |
| 3. **Curva de Kcb** | Coeficiente basal de cultivo (FAO-56) a lo largo del ciclo |
| 4. **Balance hídrico diario** | Agua en cada horizonte del suelo: escorrentía, infiltración, transpiración, evaporación y drenaje |
| 5. **Salidas** | Las tres variables de decisión (ver abajo) |

Las **salidas** del método son:

1. **Eventos de lluvia** de 10 mm o más entre 14 días antes y 7 días después de
   la siembra.
2. **Estado hídrico a la siembra:** porcentaje de agua útil en el primer metro,
   el segundo metro y todo el perfil, y presencia de "sándwich seco" (capa seca
   intermedia).
3. **Confort hídrico:** porcentaje de la demanda de agua del cultivo cubierta
   durante su período crítico.

El clima de entrada es el de una estación meteorológica; cuando la serie tiene
huecos puntuales, se rellenan con un procedimiento estadístico reproducible.

### Documentación

| Documento | Para qué |
|---|---|
| [`documentacion/MANUAL_TECNICO.md`](documentacion/MANUAL_TECNICO.md) | **Teoría:** todas las ecuaciones y procedimientos del método, incluida la imputación de clima |
| [`documentacion/ARQUITECTURA.md`](documentacion/ARQUITECTURA.md) | **Ingeniería de software:** estructura del código, contratos de datos, API, frontend, Docker y CI/CD, pruebas |
| [`documentacion/GUIA_PLATAFORMA_WEB.md`](documentacion/GUIA_PLATAFORMA_WEB.md) | **Caso de uso sencillo:** instalar Docker y usar la plataforma web |
| [`documentacion/GUIA_USO_R.md`](documentacion/GUIA_USO_R.md) | **Caso de uso avanzado:** instalar el paquete y correr escenarios y lotes desde R |

## 2. Casos de uso

### Caso sencillo: plataforma web

**Para quién:** cualquier persona que quiera simular un escenario y ver los
resultados en el navegador, sin programar.

Se elige localidad, suelo, cultivo, cultivar, fechas y condiciones iniciales en
un formulario; la plataforma corre el escenario contra todos los años de clima
disponibles y muestra las estadísticas (media, P20, P50, P80, desvío e IQR) y
el detalle de cada año.

Se instala con **Docker** y un archivo `docker-compose.yml` que levanta los dos
servicios de la plataforma (API de cálculo y página web):

```bash
docker compose up
# luego abrir http://localhost:3000
```

La guía explica paso a paso, para quien nunca usó Docker, cómo instalarlo en
**Windows** y en **Mac**, cómo iniciar y detener la plataforma, cómo usar cada
campo del formulario, cómo interpretar los resultados y cómo resolver los
problemas más comunes.

➡️ **[Guía de instalación y uso de la plataforma web](documentacion/GUIA_PLATAFORMA_WEB.md)**

### Caso avanzado: corridas desde R con el paquete

**Para quién:** usuarios con conocimientos básicos de R que quieren simular un
escenario puntual con sus propios datos, procesar un **lote** de escenarios ×
años, explorar resultados intermedios o integrar el método en su propio código.

```bash
git clone https://github.com/CRC-SAS/balance-hidrico.git
cd balance-hidrico

# un escenario (ejemplo incluido)
Rscript scripts/simular.R scripts/escenario_ejemplo.yml

# un lote de escenarios x años
Rscript scripts/simular_batch.R scripts/batch_ejemplo.yml
```

La guía cubre la descarga del repositorio, la instalación del paquete y sus
dependencias, el formato de cada archivo de entrada (CSV de clima, YAML de
parámetros, de constantes, de escenario y de lote, y xlsx de condiciones
iniciales), cómo correr **un escenario** (con el script y paso a paso en R),
cómo correr **un lote**, cómo leer los resultados y cómo resolver los errores
frecuentes.

➡️ **[Guía de uso avanzado desde R](documentacion/GUIA_USO_R.md)**

## 3. Estructura del repositorio

```
balance-hidrico/
├── README.md                 este archivo
├── DESCRIPTION, NAMESPACE    metadatos del paquete R
├── R/                        código del paquete: los 5 pasos, utilidades de clima, E/S
├── man/                      documentación de funciones (generada)
├── tests/testthat/           pruebas automáticas
├── inst/extdata/             datos de ejemplo: clima, parámetros y constantes
├── scripts/                  scripts de corrida (escenario, lote) y YAML de ejemplo
├── api/                      API de cálculo (R/plumber) de la plataforma web
├── frontend/                 página web (Next.js) de la plataforma web
├── balance_hidrico.sqlite    catálogo y clima de la plataforma web
├── docker-compose.yml        levanta la plataforma web con las imágenes publicadas
├── docker-compose.dev.yml    variante para construir las imágenes desde el código
├── .github/workflows/        publicación automática de las imágenes Docker
└── documentacion/            manual técnico, arquitectura y guías de uso
```

Una descripción detallada de cada componente está en
[`ARQUITECTURA.md`](documentacion/ARQUITECTURA.md#3-estructura-del-repositorio).

## Autores y licencia

Guillermo García, Jorge Luis Mercau y Santiago Rovere. Licencia MIT (ver
[`LICENSE`](LICENSE)).
