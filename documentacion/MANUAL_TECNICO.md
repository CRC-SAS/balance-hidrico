# Manual técnico — balancehidrico

Este documento explica **todo** lo necesario para entender e implementar el
método CRC-SAS de balance hídrico de cultivos: qué hace la herramienta, de
dónde sale cada fórmula, qué decisiones de diseño se tomaron y por qué, y
cómo se mapea todo al código de este paquete R. Reemplaza y absorbe el
contenido de los documentos de trabajo originales de CRC-SAS (nunca
commiteados a este repo) — **este documento es ahora la fuente de
verdad**, no hace falta consultar esas fuentes.

Para el historial del proyecto y las decisiones de arquitectura no
estrictamente técnicas, ver las secciones 1 y 2 más abajo. Para lo que
sigue pendiente, ver `FUTURE_WORK.md`. Para cómo usar el paquete, ver el
`README.md` de la raíz del repo.

## Índice

1. [Historia del proyecto](#1-historia-del-proyecto)
2. [Decisiones de arquitectura](#2-decisiones-de-arquitectura)
3. [Qué hace la herramienta (dominio, entradas, salidas)](#3-qué-hace-la-herramienta-dominio-entradas-salidas)
4. [Arquitectura del paquete y contrato de datos](#4-arquitectura-del-paquete-y-contrato-de-datos)
5. [Paso 1 — Fenología](#5-paso-1--fenología-rfenologiar)
6. [Paso 2 — Profundización radicular potencial](#6-paso-2--profundización-radicular-potencial-rprofundizacion_radicularr)
7. [Paso 3 — Curva de Kcb](#7-paso-3--curva-de-kcb-rcurva_kcbr)
8. [Paso 4 — Balance hídrico diario](#8-paso-4--balance-hídrico-diario-rbalance_hidricor)
9. [Paso 5 — Salidas](#9-paso-5--salidas-rsalidasr)
10. [Utilidades climáticas](#10-utilidades-climáticas-rutils_climar)
11. [Entrada/salida y validación](#11-entradasalida-y-validación-rior)
12. [Testing](#12-testing)
12bis. [Relleno de gaps climáticos](#12bis-relleno-de-gaps-climáticos-rimputacion_climar-2026-08-13)
13. [Mapa del repo](#13-mapa-del-repo)

---

## 1. Historia del proyecto

`balance-hidrico` nace el 2026-07-24 como migración desde un repo más viejo
(`balance_agua_suelo`), que tenía dos líneas de trabajo paralelas para
extender un pipeline que originalmente solo soportaba trigo vía DSSAT:

- **Thread A (DSSAT):** extender `lib/fenologia.R` del repo viejo (funciones
  basadas en el motor CERES de DSSAT, con archivos `.CUL`/`.ECO`/`.SOL`)
  para soportar maíz y soja. Quedó en pausa, fuera del alcance de este repo.
- **Thread B (método propio CRC-SAS):** CRC-SAS definió un método propio,
  más simple, de acumulación de unidades térmicas (sin usar DSSAT como
  motor de cálculo, aunque el propio documento de trabajo de CRC-SAS aclara
  que la fenología "se simula en base a los procesos de DSSAT" — ver
  sección 5). Se decidió priorizar esta línea (decisión del 2026-07-23, en
  el repo viejo) porque es la que CRC-SAS quiere usar en producción. Este
  repo es exclusivamente Thread B.

### Proceso de validación con el experto de dominio

El método partió de documentos de trabajo fuente de CRC-SAS (una
descripción narrativa del método y una planilla de cálculo de referencia
con las fórmulas y un escenario validado). Un análisis inicial
(2026-07-24) detectó ~20 dudas/divergencias/vacíos, agrupadas en dos
secciones:

- **Sección 2a** — dudas puntuales sobre los Pasos 1-3, que sí estaban
  desarrollados en las fuentes: F-1 a F-7 (fenología), PR-1/PR-2
  (profundización radicular), KC-1/KC-2 (curva Kcb).
- **Sección 2b** — todo lo que el método no llegó a desarrollar en la
  primera versión de las fuentes (esa versión quedaba cortada a mitad
  del Paso 4): BH-1 a BH-7 (balance hídrico diario), DS-1 a DS-3 (datos de
  soporte), G-1 a G-3 (generales).

**Ronda 1 (2026-07-24):** el experto respondió toda la Sección 2a (F-1 a
F-7, PR-1, PR-2, KC-1, KC-2). Todas las respuestas fueron verificadas contra
las fórmulas reales de la planilla de referencia (valores cacheados, no
solo texto) antes de implementar — resumen de cada una en las secciones
5-7 más abajo, integrado en la descripción de cada paso en vez de
mantenerse como una lista aparte.

**Ronda 2 (2026-07-29):** llegó una versión nueva de las fuentes con el
Paso 4 (balance hídrico diario) **completamente especificado** — resuelve
BH-1 a BH-7 y DS-1. Durante la extracción del fixture correspondiente se
encontró, de pura casualidad (no se estaba buscando eso), que la fórmula de
fotoperíodo de esa versión era **distinta** a la que ya estaba implementada
y validada — un cambio que nadie había detectado porque el foco estaba
puesto solo en la sección nueva (Paso 4). Esto motivó una lección de
proceso: **al recibir una versión nueva de las fuentes, no alcanza con
revisar la sección que motivó el envío — conviene comparar también las
fórmulas que alimentan pasos ya implementados** (en este caso, las que
alimentan el Paso 1, que ya estaba shippeado con 67 tests en verde). Un
checklist consolidado con este hallazgo (crítico) más 7
preguntas/inconsistencias adicionales (nomenclatura de categorías, suelo
de ejemplo sin match en el catálogo, 4 discrepancias formales
fórmula-vs-texto, y las preguntas DS-2/G-1 que seguían abiertas) se le
mandó a CRC-SAS el 2026-07-29.

**Ronda 3 (2026-08-01):** CRC-SAS respondió el checklist completo (14
puntos) por escrito. Confirmó que la fórmula de fotoperíodo nueva
(con corrección de crepúsculo civil) es la vigente — fue un cambio
deliberado, no un arrastre de otra planilla — lo cual obligó a actualizar
`calcular_fotoperiodo()` (Paso 1, ya shippeado) y re-validar 5 de los 8
hitos fenológicos de trigo. Con esta ronda, **ya no quedaron preguntas
bloqueantes** y se implementaron los Pasos 4 y 5 (ver secciones 8 y 9).
Detalle completo de las 14 respuestas, integrado en cada sección técnica
correspondiente en vez de mantenerse aparte.

**Ninguno de los documentos de trabajo originales se commiteó nunca a este
repo** — se trataron siempre como documentos temporales del experto de
CRC-SAS, y este manual existe específicamente para que esa decisión no
implique pérdida de información.

## 2. Decisiones de arquitectura

Decisiones tomadas explícitamente por el usuario durante el diseño (no son
solo elecciones técnicas del desarrollador, son requerimientos):

- **Código completamente nuevo**, sin tocar el pipeline DSSAT (Thread A).
- **Paquete R formal** (`DESCRIPTION`/`NAMESPACE`/`R/`/`tests/testthat/`/`man/`
  con roxygen2), no scripts sueltos — porque en algún momento va a haber
  además un script de orquestación de simulaciones que haga
  `library(balancehidrico)`/`devtools::load_all()` sobre el paquete (ver
  `FUTURE_WORK.md`, "script de orquestación batch").
- **Un archivo por paso del método**, alta cohesión/bajo acoplamiento
  (`R/fenologia.R`, `R/profundizacion_radicular.R`, `R/curva_kcb.R`,
  `R/balance_hidrico.R`, `R/salidas.R`), para que cada paso sea testeable de
  forma aislada. Cada paso es una función pura: recibe datos ya parseados
  (tibbles/listas), no hace I/O, y no depende del estado interno de los
  otros pasos — se comunican pasándose tibbles/fechas explícitas (ver
  contrato de datos, sección 4). Esto permitió, por ejemplo, testear el
  Paso 4 con un fixture de `Prof`/`Kcb` **literal** de la planilla de
  referencia, totalmente desacoplado de si el Paso 1/2 en sí estaban
  validados en ese momento.
- **Clima en CSV**, parámetros de cultivo/cultivar/estación/suelo en
  **YAML bien documentado** (con ejemplo comentado campo por campo). Una
  excepción deliberada: las constantes categóricas de rastrojo/humedad
  inicial (que no varían entre escenarios, a diferencia del resto) viven en
  un YAML **separado** (`inst/extdata/constantes.yml`), no en el YAML de
  escenario — ver sección 8.
- **Tests automatizados con testthat**, obligatorio — el repo original
  (`balance_agua_suelo`) no tenía ninguna convención de testing, esta es
  una convención nueva. Fixtures con valores **reales cacheados** de la
  planilla de referencia de CRC-SAS siempre que sea posible, no solo
  fixtures sintéticos.
- **Verificar la fórmula real de la fuente, no solo su descripción en
  prosa**, antes de dar una duda por resuelta — tanto el hallazgo de la
  fórmula de fotoperíodo (sección 1) como dos detalles no documentados en
  el texto descriptivo (la constante `0.01745` en vez de `pi/180`, y el
  clamp asimétrico de esa misma fórmula — ver sección 10) solo aparecieron
  al leer la fórmula real de la planilla de cálculo, no al leer la
  descripción en prosa ni un resumen de una sesión anterior.

## 3. Qué hace la herramienta (dominio, entradas, salidas)

Esta sección resume el objetivo funcional completo de la herramienta CRC-SAS,
según el documento de trabajo original del método. **El paquete R implementa
el motor de cálculo (Pasos 1-5); no implementa
una interfaz de usuario ni la selección de estación/suelo/campaña** — eso
queda para la capa de aplicación que consuma este paquete.

**Para qué / cómo:** gestionar mejor el riesgo climático en decisiones
agrícolas, prediciendo la disponibilidad de agua en el suelo a la siembra y
el confort hídrico durante el período crítico de trigo, maíz y soja.

**Dominio:** la herramienta permite consultas desde el 1 de marzo hasta la
fecha de siembra planeada, para trigo, maíz o soja. Se asume un barbecho
libre de malezas entre la fecha de consulta y la siembra, siendo el cultivo
simulado siempre el primero de la campaña. La simulación corre desde la
fecha de consulta hasta la madurez fisiológica del cultivo.

**Datos de entrada (conceptuales, mapeados a los contratos de datos exactos
en las secciones 4-10):**
- **Clima:** estación meteorológica (climatología >30 años). Variables:
  fecha; temperaturas máxima/mínima/media diaria (`Tx`, `Tn`, `Tm`, °C);
  precipitación diaria (`Pp`, mm); fotoperíodo (`Fp`, h — calculado a
  partir de latitud y declinación solar, no es un dato de entrada de la
  base climática); evapotranspiración de referencia diaria (`Eto`, mm —
  dato de entrada, no calculado por el paquete); ENSO (categorización
  Niño/Niña/Neutro por campaña vía ONI — **dato descripto pero todavía sin
  uso en ningún cálculo**, ver `FUTURE_WORK.md`).
- **Suelo:** 2-3 opciones por localidad, cada una con 8 horizontes
  (0-0.2/0.2-0.4/0.4-0.6/0.6-0.9/0.9-1.2/1.2-1.5/1.5-1.8/1.8-2.1 m; un suelo
  somero puede tener menos horizontes) con contenido volumétrico de agua en
  PMP/CC/Sat, más los escalares de suelo: Curva Número (`CN`, escorrentía),
  agua evaporable en fase 1 (`U`), factor de drenaje (`DR`), y facilidad de
  extracción (`kl`: 0.1 general, 0.08 argiudol vértico/thapto nátrico, 0.05
  vertisol) con su umbral de reducción por textura (`Um`: 30% en suelos
  arenosos, 50% en francos, 70% en vérticos).
- **Cultivo y cultivar:** trigo (intermedio-corto, intermedio-largo), maíz
  (templado-corto, templado-intermedio, tropical-intermedio), soja (GM 3C,
  4L, 6C). Determina Kcb inicial/máximo y los estadios fenológicos.
- **Fecha de inicio** (medición de agua en el suelo, entre 1° de marzo y la
  siembra) y **fecha planeada de siembra**.
- **Agua inicial:** AU% en el primer metro (0-1 m, basado en el horizonte
  0-0.9), segundo metro (1-2 m, basado en 0.9-2.1) y todo el perfil
  (0-2.1 m); más presencia o no de "sándwich seco" (ver sección 8) y una
  de 4 clases de humedad de referencia: Seco (10% AU), Moderadamente Seco
  (35%), Moderadamente Húmedo (65%), Húmedo (90%).
- **Rastrojo:** una de 3 clases (Baja 0-20%, Moderada 30-50%, Muy Alta
  80-100% de cobertura), fija durante toda la simulación.

**Datos de salida (las 3 salidas de Paso 5, sección 9):**
1. Número de eventos de lluvia ≥10 mm/día en los 14 días previos y 7
   posteriores a la siembra.
2. Contenido hídrico del suelo a la siembra: AU% en 0-1/1-2/0-2 m, y
   presencia de sándwich seco.
3. Confort hídrico (0-1) del cultivo durante el período crítico.

**Secuencia de cálculos** (mapeo 1:1 con los 5 pasos de este paquete):
Fenología (fechas de cada evento, según siembra/cultivar/clima) →
Profundización radical (potencial, luego limitada por agua en Paso 4) →
Curva Kcb (según requerimientos térmicos de cada etapa) → Balance hídrico
(cálculo de pase diario: agua en cada horizonte el día previo → profundiza
raíz → llueve → escurre → infiltra → transpira → evapora → drena → agua al
final del día) → Salidas.

## 4. Arquitectura del paquete y contrato de datos

El paquete separa **lectura de datos** (`R/io.R`), **utilidades climáticas
compartidas** (`R/utils_clima.R`) y **un archivo por paso del método**
(`R/fenologia.R`, `R/profundizacion_radicular.R`, `R/curva_kcb.R`,
`R/balance_hidrico.R`, `R/salidas.R`). Cada paso es una función pura (ver
sección 2). Contrato de datos entre pasos:

```
calcular_fenologia(cultivo, cultivar, clima_estacion, fecha_siembra, parametros)
  -> list(
       hitos = tibble de 1 fila: siembra, emergencia, fin_kcb_inicial,
               inicio_kcb_maximo, hito1, nombre_hito1, hito2, nombre_hito2,
               inicio_periodo_critico, fin_periodo_critico, madurez_fisiologica
       serie_diaria = tibble: date, doy, tm, fp, ut_simple_acum
     )
```

`hito1`/`hito2` son un alias genérico: el nombre real depende del cultivo
(`nombre_hito1`/`nombre_hito2`: "ET"/"Z71" en trigo, "R2"/"R2" en maíz,
"R1"/"R5" en soja). Esto permite que `calcular_profundidad_radicular()` sea
**crop-agnostic**: solo necesita `fecha_emergencia` y `fecha_hito2`.
`ut_simple_acum` es la serie de UT acumuladas **sin** ajuste de
fotoperíodo desde emergencia — la consume `calcular_curva_kcb()`.

```
calcular_profundidad_radicular(clima_estacion, fecha_emergencia, fecha_hito2,
                                tb_c, pr_s_e, pr, profundidad_maxima_suelo)
  -> tibble: date, profundidad_radical_m

calcular_curva_kcb(serie_ut_simple, ut_fkcbini, ut_ikcbmax, kcb_ini, kcb_max)
  -> tibble: date, kcb

calcular_balance_hidrico(clima_estacion, fecha_inicio,
                          serie_profundidad_radicular, serie_kcb, suelo,
                          rastrojo_clase, humedad_inicial_clase_m1,
                          humedad_inicial_clase_m2, constantes,
                          sandwich_seco_inicial = FALSE)
  -> list(serie_diaria = tibble de ~78 columnas, ver seccion 8)

calcular_salidas(clima_estacion, fecha_siembra, hitos, serie_diaria_balance)
  -> list(eventos_lluvia_10mm_14a_7d_siembra, estado_hidrico_siembra, confort_hidrico)
```

`calcular_balance_hidrico()` recibe `serie_profundidad_radicular`/`serie_kcb`
tal como las devuelven los Pasos 2/3 (fechas antes de que arranquen esas
series, p. ej. antes de emergencia, se tratan como `profundidad_radical_m=0`/
`kcb=0` — no hay cultivo todavía, mismo criterio que usa la planilla de
referencia para las celdas sin dato ("en blanco = 0"). El parámetro `suelo` es lo que devuelve
`obtener_suelo_balance_hidrico()` (sección 11); `constantes` es lo que
devuelve `leer_constantes_yaml()`.

## 5. Paso 1 — Fenología (`R/fenologia.R`)

### Marco general

Cada etapa fenológica se define por una cantidad de **unidades térmicas**
(UT, °C-día) que deben acumularse desde un hito anterior. El incremento
diario de UT es `max(0, Tm - Tb)`, con `Tb` (temperatura base) específica
de cada cultivo/etapa. La fenología de trigo, maíz y soja **se simula en
base a los procesos de DSSAT** (fuente CRC-SAS): en particular, el enfoque
de trigo/maíz sigue el esquema de CERES-Wheat/CERES-Maize (temperatura base
por etapa, umbrales térmicos, sensibilidad al fotoperíodo entre
emergencia y una etapa reproductiva temprana) y el de soja sigue el
esquema de CROPGRO-Soybean (umbral de fotoperíodo con penalización lineal,
temperatura óptima) — ver Ritchie & Otter (1985) y Boote et al. (1998) en
`PAPER.md` para las referencias completas; el marco general de acumulación
térmica multi-cultivo es el de Jones et al. (2003), DSSAT Cropping System
Model.

La temperatura media (`Tm`) se toma de la base climática si está
disponible; si no, se calcula como `(Tx+Tn)/2`
(`calcular_temperatura_media()`, duda **F-7**, resuelta ronda 1).

`calcular_fenologia()` es el dispatcher público: resuelve la latitud de la
estación y los parámetros del cultivar (`obtener_latitud_estacion()`,
`obtener_parametros_cultivo()`), calcula `tm` y `fp`
(`calcular_fotoperiodo()`, sección 10) para toda la serie climática desde
la siembra, y delega en la función específica del cultivo.

Internamente, encontrar la fecha en que una etapa termina es: acumular UT
día a día (`cumsum()`) y tomar la primera fecha en que el acumulado
alcanza el umbral (`.fecha_en_umbral()`, función interna no exportada).
Como los incrementos diarios nunca son negativos, la serie acumulada es
monótona no decreciente, así que esa primera fecha es única y bien
definida — equivalente en R al mismo criterio de búsqueda por umbral que
usa la planilla de referencia.

### Trigo (`calcular_fenologia_trigo()`)

El trigo responde al fotoperíodo (día largo) **solo entre Emergencia (E) y
Espiguilla Terminal (ET)**; después es insensible (duda **F-6**). El factor
fotoperiódico es una función cuadrática centrada en 20 h, modulada por la
respuesta del cultivar al fotoperíodo (`RCF`):

```
factor_fp = max(0, 1 - ((20 - min(20, Fp))^2 * 0.01 * RCF))
```

El `min(20, Fp)` es clave (duda **F-5**): sin él, el factor también
penalizaría fotoperíodos **mayores** a 20 h (la fórmula es cuadrática y
simétrica), lo cual no es lo que pide el método — por encima de 20 h el
efecto del fotoperíodo debe ser nulo (factor = 1). Con el `min`, para
`Fp >= 20` el término `(20 - min(20,Fp))` es 0 y el factor queda en 1.

Secuencia de hitos (temperatura base = 0°C todo el ciclo S→MF):

| Hito | Fórmula (UT desde el hito anterior) | Con ajuste de Fp |
|---|---|---|
| Emergencia (E) | Siembra + `ut_s_e` (150°C) | No |
| Fin Kcb inicial | E + `ut_e_fkcbini` (300°C, ~3 hojas, filocrono 100°C/hoja) | No |
| Inicio Kcb máximo | E + `ut_e_ikcbmax` (1000°C, ~10 hojas) | No |
| Espiguilla Terminal (ET, **hito1**) | E + `ut_e_et` (400°C) | **Sí** (factor_fp con RCF) |
| Inicio período crítico | ET + `ut_et_ipc` (100°C) | No |
| Z71 (cuaje de granos, **hito2**) | ET + `ut_et_z71` (700°C) | No |
| Fin período crítico | ET + `ut_et_fpc` (800°C) | No |
| Madurez fisiológica | Fin período crítico + `ut_fpc_mf` (400°C) | No |

`RCF` por cultivar: intermedio-corto 0.7, intermedio-largo 0.85 (a mayor
RCF, menor acumulación diaria de UT en la etapa sensible, mayor duración).

**Duda F-1 (bloqueante, resuelta ronda 1):** Z71 y fin de período crítico
(fPC) son **dos hitos distintos**, ambos relativos a ET: `Z71 = ET + 700`,
`fPC = ET + 800`. Una versión anterior del documento los trataba como el
mismo hito, generando una discrepancia de 100°C-día en fPC y en madurez
fisiológica (`MF = fPC + 400`).

Fin de período crítico, inicio de período crítico y Z71 se resuelven todos
sobre la **misma** serie acumulada iniciada en ET (no se reinicia en cada
hito): el código construye un único `acum_post_et` y busca los tres
umbrales sobre él, y madurez fisiológica es el umbral `ut_et_fpc + ut_fpc_mf`
sobre esa misma serie (duda **F-2**: todo se define relativo a ET, no a Z71).

### Maíz (`calcular_fenologia_maiz()`)

El maíz **no responde al fotoperíodo** (duda F-6). La temperatura base
cambia de `tb_a` (10°C, Siembra→Emergencia) a `tb_b` (8°C,
Emergencia en adelante). R2 (cuaje de granos) es **a la vez hito1 y
hito2** (no hay una etapa intermedia como el ET del trigo).

Todos los hitos posteriores a la emergencia (fin Kcb inicial, inicio Kcb
máximo, inicio de período crítico, R2, fin de período crítico, madurez
fisiológica) se resuelven sobre una **única** serie acumulada de UT (base
`tb_b`, sin ajuste de fotoperíodo), cada uno en su propio umbral absoluto
tomado directamente del cultivar (`ut_e_fkcbini=120`, `ut_e_ikcbmax=560`,
`ut_e_ipc`, `ut_e_r2`, `ut_e_fpc`, `ut_r2_mf`). Los umbrales de período
crítico (`R2-450` y `R2+100` según el documento) **ya vienen precalculados
como valores absolutos** en la tabla de parámetros (p. ej. templado-corto:
`ut_e_r2=950`, `ut_e_ipc=500=950-450`, `ut_e_fpc=1050=950+100`) — el código
no resta/suma esas constantes, usa los valores de la tabla directamente,
para no duplicar la aritmética en dos lugares.

`UTE-R2` por cultivar: templado-corto 950°C, templado-intermedio 1050°C,
tropical-intermedio 1150°C. `UTR2-MF` por cultivar: 550/650/700°C
respectivamente.

### Soja (`calcular_fenologia_soja()`)

La soja responde al fotoperíodo (día corto) **durante todo el ciclo**,
desde Emergencia hasta Madurez Fisiológica, con dos mecanismos que la
distinguen del trigo:

1. **Temperatura óptima (`to_a`, 27°C):** el incremento diario usa
   `min(Tm, to_a) - Tb`, no `Tm - Tb`. Por encima de `to_a` las UT diarias
   no siguen aumentando. Aplica en **todas** las fases, incluida
   Siembra→Emergencia (trigo/maíz no tienen `to_a`).
2. **Umbral de fotoperíodo (`FpU`), penalización lineal:** a diferencia del
   factor cuadrático continuo del trigo, la soja usa un umbral discreto por
   etapa y cultivar (`fpu_e_r1` para Emergencia→R1, `fpu_r1_mf` para
   R1→Madurez Fisiológica). Por debajo del umbral no hay penalización; por
   encima, la acumulación diaria se reduce linealmente a razón de 0.3 por
   hora de exceso:

   ```
   factor_fpu = min(1, max(0, 1 - max(0, Fp - FpU) * 0.3))
   ```

   Nota de diseño (duda **F-6**): aunque el documento describe el efecto
   del fotoperíodo con una frase genérica para los tres cultivos, el
   **mecanismo** es distinto en cada uno: trigo usa una función cuadrática
   continua centrada en 20h; soja usa un umbral discreto con penalización
   lineal. No son la misma fórmula con distintos parámetros.

Secuencia de hitos (`tb_a=10°C` S→E, `tb_b=7°C` E→MF, `to_a=27°C`):

| Hito | Fórmula | Umbral Fp usado |
|---|---|---|
| Emergencia (E) | Siembra + `ut_s_e` (100°C) | — |
| Fin Kcb inicial | E + `ut_e_fkcbini` (180°C, ~3 nudos) | — (sin penalización) |
| Inicio Kcb máximo | E + `ut_e_ikcbmax` (840°C, ~14 nudos) | — (sin penalización) |
| R1 (**hito1**) | E + `ut_e_r1` (400°C) | `fpu_e_r1` |
| Inicio período crítico | R1 + `ut_r1_ipc` (120°C) | `fpu_r1_mf` |
| R5 (cuaje de granos, **hito2**) | R1 + `ut_r1_r5` (300°C) | `fpu_r1_mf` |
| Fin período crítico | R1 + `ut_r1_r5` + `ut_r5_fpc` (200°C) | `fpu_r1_mf` |
| Madurez fisiológica | R1 + `ut_r1_r5` + `ut_r5_mf` (800°C) | `fpu_r1_mf` |

`FpU` Emergencia→R1 por cultivar: GM3C 13.5h, GM4L 13h, GM6C 12.5h. `FpU`
R1→MF por cultivar: GM3C 13h, GM4L 12.5h, GM6C 12h (a mayor duración de
ciclo, menor umbral).

**Duda F-3 (resuelta ronda 1):** `UT_R1-R5` (`ut_r1_r5`) es una constante
fija de **300** (no varía por cultivar ni condiciones) — esto hace que
`iPC = R1+120` y `iPC = R5-180` sean equivalentes numéricamente
(300-180=120); el código usa `R1+120` como definición canónica.

Nota: "fin Kcb inicial" e "inicio Kcb máximo" se calculan sobre la serie
**sin** penalización de fotoperíodo (`incr_simple`, misma serie que
consume Curva Kcb), mientras que desde R1 en adelante se usa la serie
penalizada por `fpu_r1_mf` de forma continua (no se reinicia en cada
hito, igual que en trigo desde ET).

**Duda F-4 (resuelta ronda 1, no bloqueante):** el formato de fecha de
salida (absoluta, día del año, o días desde siembra) queda a criterio de
implementación — no es visible al usuario final de la herramienta. Este
paquete usa siempre `Date` absoluto.

## 6. Paso 2 — Profundización radicular potencial (`R/profundizacion_radicular.R`)

`calcular_profundidad_radicular()` implementa:

1. Profundidad constante de 20 cm entre siembra y emergencia, para los 3
   cultivos.
2. Desde emergencia, crecimiento a tasa `pr` (cm/°C, base `tb_c`): trigo
   `pr=0.13`, `tb_c=0°C`; maíz y soja `pr=0.20`, `tb_c=8°C`. Fórmula:
   `profundidad = pr_s_e + (pr * UT_acumulada_raiz) / 100`.
3. Congelamiento en `fecha_hito2` (cuaje de granos: Z71 en trigo, R2 en
   maíz, R5 en soja) — la profundidad no sigue creciendo después.

La acumulación de UT de raíz es **independiente** de las series de
fenología: usa su propia temperatura base `tb_c`, y solo depende de
`fecha_emergencia`/`fecha_hito2` como límites — de ahí que esta función no
necesite saber qué cultivo es.

**Duda PR-1 (resuelta ronda 1, con nota de implementación):** el documento
especifica que la raíz crece "hasta la profundidad máxima del suelo **o**
el cuaje de granos, lo que ocurra primero". La parte de la planilla de
referencia dedicada a fenología solo implementa el congelamiento por
cuaje — esa parte no tiene contexto de suelo, así que no puede aplicar el
segundo tope. **No es un vacío de especificación**, es una limitación de
esa planilla en particular. El
código de este paquete sí aplica ambos topes: `profundidad_maxima_suelo`
(por defecto `Inf`, sin tope) se aplica con un `pmin()` final sobre toda la
serie, consultando `obtener_profundidad_maxima_suelo()` sobre la tabla
`suelos` del YAML de parámetros.

**Duda PR-2 (resuelta ronda 2):** la limitación por sequía ("si hay un
horizonte con menos de 30% de AU, la tasa de profundización se reduce
gradualmente hasta 0% de AU") pertenecía al Paso 4 — ver `LHPR` en la
sección 8. `calcular_profundidad_radicular()` (Paso 2) solo calcula la
curva **potencial**, sin esta limitación; `calcular_balance_hidrico()`
(Paso 4) la aplica día a día sobre esa curva potencial.

**Unidades de profundidad (aclarado ronda 3):** CRC-SAS corrigió la
columna `PFH` del catálogo de suelos de referencia — estaba en cm, ahora
está en metros. Este paquete usa metros consistentemente en todo el código
(`profundidad_maxima_m` en el YAML, `pfh_m` en los horizontes de Paso 4)
desde el principio, así que no hizo falta ningún cambio de unidades acá;
la corrección solo afectó la fuente de CRC-SAS.

## 7. Paso 3 — Curva de Kcb (`R/curva_kcb.R`)

`calcular_curva_kcb()` implementa una rampa lineal simple en tres tramos,
en función de `ut_simple_acum` (serie de UT **sin** ajuste de fotoperíodo
que devuelve `calcular_fenologia()` en `serie_diaria`):

```
Kcb = kcb_ini                                              si UT <= ut_fkcbini
Kcb = kcb_max                                               si UT >= ut_ikcbmax
Kcb = kcb_ini + (kcb_max - kcb_ini) * (UT - ut_fkcbini) / (ut_ikcbmax - ut_fkcbini)   en el medio
```

`kcb_ini = 0.15` y `kcb_max = 1.10` para los 3 cultivos (el Kcb puede
superar 1 con cobertura del canopeo entre 80-85%, IAF ~3.0-3.5 — dual crop
coefficient de FAO-56, Allen et al. 1998, ver `PAPER.md`).

**Duda KC-2 (resuelta ronda 1):** la serie usada para la rampa es
explícitamente la que **no** tiene ajuste de fotoperíodo (la serie
"E→simple" de la planilla de referencia), no la serie fenológica ajustada
por Fp/RCF/FpU.
Deliberado: la velocidad de desarrollo del canopeo (lo que mide Kcb) no
depende del fotoperíodo de la misma forma que la fenología reproductiva.

**Duda KC-1 (resuelta ronda 1):** `kcb_max` se mantiene **constante** desde
`ut_ikcbmax` hasta madurez fisiológica — no hay rampa descendente de
senescencia, aunque agronómicamente el Kcb real debería bajar hacia el
final del ciclo (así es en FAO-56 dual estándar). **Decisión de diseño
deliberada** de CRC-SAS, no un vacío: el único output relevante de la
herramienta que depende de Kcb (confort hídrico) se calcula solo hasta el
**fin del período crítico**, que ocurre antes de que la caída de Kcb en
senescencia importe. Confirmado además en la ronda 3: el balance hídrico
(Paso 4) sigue transpirando a `Kcb=kcb_max` durante todo el resto de la
serie climática después de la cosecha — coherente con esta decisión, no es
un bug del Paso 4.

## 8. Paso 4 — Balance hídrico diario (`R/balance_hidrico.R`)

Simula día a día el contenido hídrico del suelo en 8 horizontes, a partir
de la oferta (agua inicial, lluvia diaria, capacidad de extracción de
raíces) y la demanda (evapotranspiración potencial ponderada por Kcb). Es
la sección que resuelve **BH-1 a BH-7 y DS-1** (Sección 2b, ver historia)
más las precisiones de la ronda 3. Cálculo secuencial (el estado de cada
día depende del día anterior, no vectorizable entre días).

### 8.1 Suelo: horizontes y capacidades en mm

Cada suelo trae 8 horizontes con profundidad acumulada `PFH_i` (m, límite
inferior del horizonte `i` desde la superficie) y contenido volumétrico
fraccional de PMP/CC/Sat. Las fórmulas diarias del balance usan estas
capacidades convertidas a **mm por horizonte** (no la fracción cruda):

```
espesor_i = PFH_i - PFH_(i-1)                    (PFH_0 = 0)
PMP_i (mm) = pmp_frac_i * espesor_i * 1000
CC_i  (mm) = cc_frac_i  * espesor_i * 1000
Sat_i (mm) = sat_frac_i * espesor_i * 1000
```

El paquete deriva esto al vuelo dentro de `calcular_balance_hidrico()` a
partir de `pfh_m`/`pmp`/`cc`/`sat` (no se guarda en el YAML). Escalares de
suelo, sin conversión: `CN` (Curva Número), `kl` (facilidad de extracción),
`Um` (umbral de reducción de `kl` por textura), `U` (agua evaporable en
fase 1, mm), `DR` (factor de drenaje).

**Suelo de ejemplo del paquete:** `IN64MARC02` (Marcos Juárez, Haplustol
údico), único suelo con datos completos de Paso 4 en
`inst/extdata/parametros_ejemplo.yml` — confirmado real por CRC-SAS ronda 3
(antes no tenía match exacto contra el catálogo de suelos de referencia;
resultó ser que la columna `PFH` de ese catálogo estaba en cm en vez de m).
Nota: el catálogo de suelos de referencia para este suelo solo tiene 7
horizontes (0.2/0.4/0.6/0.9/1.2/1.8/2.1m, sin 1.5m); el fixture del
escenario de balance hídrico usa 8, duplicando la última fila del catálogo
(C2, PMP=0.11/CC=0.25/Sat=0.47) en el horizonte de 1.5m. Se preservó tal
cual aparece en el fixture (discrepancia de la fuente, no error de
transcripción) para reproducir los valores cacheados exactamente.

### 8.2 Contenido hídrico inicial (día 1)

```
CH_i = (CC_i - PMP_i) * AU_i + PMP_i
```

`AU_i` (fracción 0-1) es `humedad_inicial_clase_m1` para los horizontes 1-4
(0-0.9m) y `humedad_inicial_clase_m2` para los horizontes 5-8 (0.9-2.1m).

**Sándwich seco (duda DS-1, resuelta ronda 2, precisada ronda 3):** si
`sandwich_seco_inicial=TRUE`, el horizonte 4 (0.6-0.9m) se fuerza a 10% de
AU fijo, **independientemente** del AU% reportado para el primer metro —
los demás horizontes del primer metro (1-3) siguen usando el AU% general
normalmente. Esto **no es un caso especial en las fórmulas de la planilla
de referencia**: el usuario de la herramienta CRC-SAS simplemente carga
0.10 a mano en el campo de humedad inicial del horizonte 4 en vez del
valor general — el paquete lo modela como un parámetro booleano explícito
porque no hay "carga manual" equivalente en una función R.

### 8.3 Categorías de rastrojo y humedad inicial (`inst/extdata/constantes.yml`)

Confirmado por CRC-SAS ronda 3 (antes solo se conocían los factores, no los
nombres oficiales de clase):

| Rastrojo (cobertura) | Factor |
|---|---|
| `Baja` (0-20%) | 1 |
| `Moderada` (30-50%) | 0.8 |
| `Muy_Alta` (80-100%) | 0.5 |

| Humedad inicial | Fracción AU |
|---|---|
| `Se` (Seco) | 0.10 |
| `mS` (Moderado Seco) | 0.35 |
| `mH` (Moderado Húmedo) | 0.65 |
| `Hu` (Húmedo) | 0.90 |

Estas constantes **no varían entre escenarios** (a diferencia de
estaciones/suelos/cultivos, que sí son datos de catálogo) — por eso viven
en un YAML separado del de parámetros de escenario (ver sección 2), leído
con `leer_constantes_yaml()` (único caso del paquete con default de ruta,
apuntando al archivo empaquetado). `calcular_balance_hidrico()` recibe el
**nombre de clase** (`rastrojo_clase`, `humedad_inicial_clase_m1/m2`) y
resuelve el factor internamente vía `obtener_factor_rastrojo()`/
`obtener_fraccion_humedad_inicial()`, mismo patrón que
`obtener_parametros_cultivo()` del Paso 1 (recibir el nombre crudo +
lista de lookup, resolver y validar adentro, no requerir que el caller
pre-resuelva a números).

### 8.4 Escorrentía e infiltración (duda BH-2, resuelta ronda 2)

```
Absi = 0.15 * (Sat_1 - max(CH_1, PMP_1)) / (Sat_1 - PMP_1)
AtM  = 254 * (100/CN - 1)
Esc  = max(0, Pp - Absi*AtM)^2 / (Pp + AtM*(1 - Absi))
Inf  = Pp - Esc
```

`AtM` es la retención potencial máxima según Curva Número — el método SCS
clásico (USDA-SCS, 1972). `Absi` es una **abstracción inicial dinámica**
(0 con el horizonte superficial saturado, hasta 0.15 con el horizonte en
PMP) que reemplaza al coeficiente fijo `λ=0.2` del método clásico de la
Curva Número — ver discusión de `λ` variable en Hawkins et al. (2009),
citado en `PAPER.md`.

### 8.5 Profundización radical efectiva — PRE y LHPR (duda BH-5, resuelta ronda 2, fórmula exacta ronda 3)

La curva potencial del Paso 2 (`PRP`) se ajusta día a día según la
disponibilidad hídrica del horizonte hacia el cual avanza el frente
radicular:

```
ΔPRP = PRP(t) - PRP(t-1)                          si PRP(t) > 0.2, si no 0

LHPR = 1                                          si PRE(t-1) < PFH_1 (raíz en horizonte 1)
LHPR = min(1, (CH_j - PMP_j) / (0.3*(CC_j - PMP_j)))  si PFH_(j-1) <= PRE(t-1) < PFH_j (avanzando al horizonte j, 2<=j<=8)
LHPR = 0                                          si PRE(t-1) >= PFH_8 (ya no hay mas horizontes)

PRE(t) = 0             si PRP(t) < 0.2
PRE(t) = 0.2           si PRP(t) = 0.2
PRE(t) = PRE(t-1) + ΔPRP * LHPR     en cualquier otro caso
```

`j` es el horizonte específico hacia el que avanza la raíz según
`PRE(t-1)` (no un promedio de todos los horizontes); `LHPR` usa el `CH_j`
de **hoy** (ya actualizado en el paso anterior del día), no el de ayer.

**Duda: "PRE nunca supera la curva potencial" (discrepancia formal,
resuelta ronda 3):** el texto del documento dice que PRE nunca supera a
PRP, pero la fórmula real no aplica ningún `MIN()` explícito contra ella.
Confirmado por CRC-SAS: no importa en la práctica, porque `LHPR` siempre es
`<=1`, así que `PRE` matemáticamente nunca puede crecer más rápido que
`PRP`. El código no aplica el `MIN()`, siguiendo la fórmula real.

### 8.6 Demanda hídrica diaria

```
DemT = Eto * Kcb                                   (transpirativa)
DemE = max(0, Eto * max(0, 1-Kcb) * Rastrojo)       (evaporativa)
```

El `max(0, 1-Kcb)` interno (no explícito en el texto del documento, sí en
la fórmula real de la celda) protege contra `Kcb > 1` — que ocurre en la
práctica, ya que `kcb_max=1.10`.

### 8.7 Agua transpirable y transpiración real (duda BH-7, resuelta ronda 2)

Por horizonte `i`, fracción del horizonte explorada por la raíz:

```
frac_explorada_1 = min(1, PRE/PFH_1)
frac_explorada_i = min(1, max(0, PRE - PFH_(i-1)) / (PFH_i - PFH_(i-1)))   (i = 2..8)

AT_i = max(0, CH_i - PMP_i) * kl * min(1, (CH_i - PMP_i)/(Um*(CC_i - PMP_i))) * frac_explorada_i
AT   = Σ AT_i

TrR   = min(DemT, AT + Inf)              (transpiracion real, topada por demanda o agua disponible)
TrRR  = max(0, TrR - Inf)                (remanente a extraer de reservas, tras usar la infiltracion del dia)
TrR_i = TrRR * (AT_i / AT)   si AT > 0, si no 0     (reparto proporcional entre horizontes)
```

El factor `kl` pondera el agua por encima de PMP por la facilidad de
extracción del suelo, reducida linealmente por debajo del umbral `Um`
(según textura — ver sección 3).

### 8.8 Evaporación real del suelo, dos etapas (duda BH-7, resuelta ronda 2)

Modelo clásico de evaporación en dos etapas (Ritchie, 1972, ver
`PAPER.md`): agua evaporable fácilmente (`AEF`, etapa 1, limitada por
energía) y remanente (`AER`, etapa 2, con tasa decreciente):

```
AEF = min(DemE, max(0, CH_1 - (CC_1 - U*Rastrojo)) + max(0, Inf - TrR))
AER = DemE - AEF
base = (Inf + CH_1 - TrR_1 - AEF - 0.5*PMP_1) / (CC_1 - U*Rastrojo - 0.5*PMP_1)
ER  = AEF + min(AER, AER * clamp01(base)^4)
```

`U*Rastrojo` reduce el espesor de la capa de "fácil evaporación" según la
cobertura de rastrojo. La segunda etapa cae con la 4ª potencia a medida
que el horizonte superficial se acerca al punto de marchitez.

**Discrepancia formal, resuelta ronda 3 — acotar la base a [0,1]:** la
fórmula real de la planilla de referencia **no** acota `base` antes de
elevarlo a la 4ª potencia. CRC-SAS: *"Con parámetros bien ingresados, no
debiera arrojar valores fuera de 0 y 1 [...] pero parece prudente que
acotes el valor al rango 0-1 antes de exponerlo"* — el código de este
paquete sí aplica `clamp01()` (`pmin(pmax(base,0),1)`) explícitamente como
salvaguarda, aunque la fuente de CRC-SAS todavía no lo haga (van a
alinearlo de su lado más adelante).

### 8.9 Drenaje interno y contenido hídrico final (cascada por horizonte)

Con el agua ya extraída por transpiración/evaporación, el excedente sobre
capacidad de campo de cada horizonte drena a tasa `DR` hacia el horizonte
inmediato inferior, junto con el excedente por sobre-saturación. Se
resuelve en cascada, horizonte 1 → 8, cada uno dependiendo del resultado
del horizonte anterior **el mismo día**:

```
CHv_1 = CH_1 - TrR_1 - ER            CHv_i = CH_i - TrR_i    (i = 2..8)
Dr_i  = max(0, (CHv_i - CC_i) * DR)

Cf_1 = CHv_1 - Dr_1 + max(0, Inf - TrRR - ER)
Me_1 = max(0, Cf_1 - Sat_1)
Cf_i = CHv_i - Dr_i + Dr_(i-1) + Me_(i-1)     (i = 2..8)
Me_i = max(0, Cf_i - Sat_i)

drenaje_profundo = Dr_8 + Me_8         (sale del sistema)
CH_i(mañana) = min(Sat_i, Cf_i)        (cierra el ciclo diario)
```

**Discrepancia formal, resuelta ronda 3 — `Cf_1` no resta `Me_1` el mismo
día:** el horizonte 1 recibe el excedente de infiltración directo
(`Inf - TrRR - ER`) sin pasar por la lógica de "recibe `Dr`+`Me` del
horizonte de arriba" que usan los horizontes 2-8, y tampoco resta su
propio `Me_1` de `Cf_1` el mismo día (se trunca recién al día siguiente,
vía `min(Sat_1, Cf_1)`). Confirmado correcto por CRC-SAS: *"el horizonte 1
NO tiene un horizonte por sobre el mismo, como todos los otros. La fórmula
está bien."* No es un bug, es correcto por construcción.

**Sándwich seco, salida diaria:** `sandwich_seco = "Si"` si
`(CH_4 - PMP_4)/(CC_4 - PMP_4) < 30%` (horizonte 4, estricto). El texto
original decía `<=30%`; CRC-SAS confirmó que era una errata del texto y
que la fórmula real (`<30%`) es la correcta.

### 8.10 ETo — dato de entrada, con utilidad opcional para completarla (duda BH-3, resuelta ronda 2; ampliada 2026-08-13)

`Eto` sigue siendo **dato de entrada** de la base climática (columna `eto`
del CSV, ver sección 11) — `leer_clima_csv()` no cambió, la lee tal cual y
la deja `NA` si no está en el CSV. El paquete no la calcula como parte del
método en sí.

Lo que se agregó (2026-08-13) es una utilidad **opcional**,
`calcular_eto_hargreaves()` (`R/utils_clima.R`), para los casos en que la
base climática de origen no trae `Eto` ya calculada (p.ej. series de
estación con solo temperaturas, sin la ETo que CRC-SAS produce
habitualmente por otros medios). Implementa Hargreaves-Samani (Hargreaves &
Samani, 1985, ver `PAPER.md`) según las ecuaciones 21-25 y 52 de Allen et
al. (1998, FAO-56), portada literal de
`evapotranspiracion.hargreaves()` en
`balance_agua_suelo/lib/funciones_evapotranspiracion.R` (repo hermano de
CRC-SAS) — verificado con match exacto (diff 0) contra esa implementación
para los casos de prueba. Queda a criterio de quien arma la base climática
(p.ej. un futuro script de preprocesamiento del batch) invocarla para
completar `eto` antes de pasarle el CSV a `leer_clima_csv()`; no se llama
automáticamente desde ningún punto del método.

Importante: la declinación solar que usa esta fórmula (ecuación 24 de
Allen et al. 1998) es **distinta a propósito** de
[`calcular_declinacion_solar()`] (sección 8, usada para `Fp`) — esa otra
está calibrada específicamente para el fotoperiodo, con corrección de
crepúsculo civil confirmada por CRC-SAS para esa fórmula puntual. Son dos
aproximaciones empíricas válidas de la misma cantidad física pero no
intercambiables; no unificarlas.

### 8.11 Discretización de horizontes (duda BH-6, resuelta ronda 2)

El balance usa directamente los horizontes propios de cada suelo (columna
`PFH`), no una grilla fija aparte — resuelve la duda original de si había
que mapear/interpolar entre una discretización del balance y los horizontes
del suelo. El número de horizontes no está fijo en 8: todos los fixtures
originales de CRC-SAS tienen 8, pero `R/balance_hidrico.R` no lo asume así
(ver el punto siguiente, "primer/segundo metro" con menos de 8
horizontes).

### 8.11bis "Primer metro"/"segundo metro" con menos de 8 horizontes (resuelto 2026-08-13, batch Junín)

Al correr el batch de Junín contra `IN65JUNI03` (5 horizontes, hasta
1.2 m — a diferencia de los 8 horizontes/2.1 m de `IN64MARC02` y del resto
de los suelos de este catálogo) el código rompía: `au_pct_m1`/`au_pct_m2`
y la condición inicial (`.contenido_hidrico_inicial()`, `R/balance_hidrico.R`)
asumían siempre exactamente 4 horizontes para el primer metro y 4 para el
segundo (índices `1:4` y `5:8` hardcodeados). CRC-SAS confirmó la regla
general: **primer metro = horizontes 1 a `min(4, n_h)`; segundo metro =
el resto, hasta un máximo de 4 horizontes más (`min(4,n_h)+1` a
`min(8, n_h)`)**. Para `IN65JUNI03` eso da primer metro = horizontes 1-4
(igual que siempre) y segundo metro = solo el horizonte 5 (en vez de 4
horizontes). Horizontes más allá del 8° (si los hubiera) no cuentan para
ninguno de los dos metros, aunque sí participan del resto del balance día
a día (drenaje, agua transpirable, etc., que ya eran genéricos en `n_h`).
`R/balance_hidrico.R` se generalizó para calcular estos índices a partir
de `n_h = nrow(suelo$horizontes)` en vez de asumirlos fijos —
verificado sin regresión contra el fixture de 8 horizontes (tolerancia
`1e-9` sin cambios) y contra el batch real de Junín (las 4 combinaciones
de `IN65JUNI03` que antes fallaban ahora corren igual que el resto).

### 8.12 `DS-3` (forward-fill de escalares de suelo) — no aplica a este esquema

El catálogo de suelos original de CRC-SAS solo tiene los escalares
de serie (`U`, `DR`, `CN`, `kl`, `Um`) en la primera fila de cada suelo
(el resto de los horizontes los dejan en blanco, para no repetir). Este
paquete no reproduce esa convención: `obtener_suelo_balance_hidrico()`
espera un único juego de escalares por suelo en el YAML (no por
horizonte), así que no hace falta ningún forward-fill — es una decisión de
esquema de datos, no una duda pendiente de responder.

## 9. Paso 5 — Salidas (`R/salidas.R`)

Las 3 salidas de la herramienta (ver sección 3), confirmadas definitivas
por CRC-SAS en la ronda 3 (con un agregado futuro fuera de alcance, ver
`FUTURE_WORK.md`). Son agregaciones puras sobre los Pasos 1 y 4, sin
fórmulas nuevas — no hay celdas de referencia cacheadas para ninguna de
las 3 (CRC-SAS las especificó por escrito, no en una planilla de cálculo).

```
calcular_eventos_lluvia_10mm_14a_7d_siembra(clima_estacion, fecha_siembra)
  -> Integer: dias con pp >= 10mm en [fecha_siembra-14, fecha_siembra+7] (ambos extremos incluidos)

calcular_estado_hidrico_siembra(serie_diaria_balance, fecha_siembra)
  -> Tibble 1 fila: au_pct_m1, au_pct_m2, au_pct_total (porcentaje, 0-100),
     sandwich_seco (columnas que YA calcula Paso 4 dia a dia como fraccion
     0-1 -- esta funcion filtra por fecha y multiplica por 100)

calcular_confort_hidrico(serie_diaria_balance, hitos)
  -> Numeric: 100 * sum(TrR)/sum(DemT) entre hitos$inicio_periodo_critico y
     hitos$fin_periodo_critico (ambos extremos incluidos), porcentaje (0-100
     en el caso tipico). NA si sum(DemT)=0 en la ventana (cociente indefinido).

calcular_salidas(clima_estacion, fecha_siembra, hitos, serie_diaria_balance)
  -> list(eventos_lluvia_10mm_14a_7d_siembra, estado_hidrico_siembra, confort_hidrico)
```

## 10. Utilidades climáticas (`R/utils_clima.R`)

- `calcular_temperatura_media(tx, tn, tm)`: usa `tm` si no es `NA`; si no,
  `(tx+tn)/2` (duda F-7).
- `calcular_declinacion_solar(dia_anio)`: `0.4093 * sin(0.0172 * (dia_anio - 82.2))`,
  en **radianes**.
- `calcular_fotoperiodo(dia_anio, latitud)`:

  ```
  lat_rad = latitud * 0.01745
  x = (-sin(lat_rad)*sin(declinacion) - 0.1047) / (cos(lat_rad)*cos(declinacion))
  x = max(x, -0.87)
  Fp = 7.639 * acos(x)
  ```

**Historia de esta fórmula (hallazgo crítico, ronda 2-3):** la versión
original de esta función (validada contra la planilla de referencia
inicial de CRC-SAS, con `23.45 * sin(radianes(360/365*(dia-81)))` para
declinación y `24/π * acos(-tan(lat)*tan(decl))` para Fp) quedó
**desactualizada** sin que nadie lo supiera hasta que, revisando la parte
climática de una versión nueva de las fuentes "de paso" (no se estaba
buscando eso), apareció una fórmula distinta. CRC-SAS confirmó en la
ronda 3 que la fórmula nueva (arriba) es
la vigente — un cambio deliberado para incorporar la corrección por
crepúsculo civil (`0.1047 = sin(6°)`), no un arrastre de otra planilla.
Sigue el enfoque general de modelos de duración del día con corrección de
crepúsculo (ver Forsythe et al., 1995, en `PAPER.md`). El cambio movió 5 de
los 8 hitos fenológicos de trigo hasta 16 días más temprano (ver sección
5) — obligó a re-validar `test-fenologia.R` además de `test-utils_clima.R`.

**Dos detalles que solo aparecieron leyendo la fórmula real de la fuente
(no el texto descriptivo del documento):**
1. La conversión de latitud a radianes usa la constante literal `0.01745`
   (no `pi/180 = 0.017453...`) — la diferencia importa a la tolerancia
   `1e-9` de los tests de este paquete.
2. El recorte del argumento del arco-coseno es **asimétrico**: solo hay un
   `IF` que lo topa por abajo en `-0.87` (a diferencia de la fórmula
   anterior, que manejaba simétricamente día/noche polar con 0h/24h). Para
   las latitudes reales de Argentina (hasta ~-55°, Tierra del Fuego) el
   argumento nunca supera 1 por el otro lado, así que ese caso no está
   contemplado ni en la planilla ni en el código: con una latitud fuera de
   ese rango, `calcular_fotoperiodo()` puede devolver `NaN` (paridad con un
   `#NUM!` de Excel) — comportamiento esperado y testeado como tal, no un
   bug (ver `tests/testthat/test-utils_clima.R`).

Estas fórmulas se verificaron contra los valores **cacheados** de la
planilla de referencia más reciente (estación 87480, día 1 y día 99 del
año) con tolerancia `1e-9`.

## 11. Entrada/salida y validación (`R/io.R`)

- `leer_clima_csv(path)`: valida que existan las columnas requeridas
  (`station_id`, `date`, `tx`, `tn`); columnas opcionales `tm`, `pp`, `eto`
  (`NA_real_` si faltan); agrega `doy`. Si `eto` falta en la fuente,
  `calcular_eto_hargreaves()` (sección 8.10, `R/utils_clima.R`) puede
  usarse para completarla antes de leer el CSV con esta función — no está
  integrada automáticamente acá.
- `leer_parametros_yaml(path)`: valida que exista la sección `cultivos`.
- `leer_constantes_yaml(path = <empaquetado>)`: valida que existan las
  secciones `rastrojo` y `humedad_inicial` — único caso del paquete con
  default de ruta (ver sección 8.3).
- `obtener_parametros_cultivo(parametros, cultivo, cultivar)`: falla con un
  mensaje explícito (`rlang::abort()`) si el cultivo o cultivar no existen,
  listando las opciones disponibles. Deliberado: el desarrollo de Thread A
  tuvo un antecedente de bugs por parámetros faltantes que se propagaban
  silenciosamente como `NULL` hasta romper mucho más abajo. Acá se prefiere
  fallar rápido y cerca del origen del problema. Este patrón
  ("validar membership en una lista con nombre, abortar listando las
  opciones válidas") es la plantilla que reusan todos los `obtener_*()`
  del paquete.
- `obtener_latitud_estacion()` / `obtener_profundidad_maxima_suelo()`:
  mismo patrón, para `estaciones` y `suelos` (solo `profundidad_maxima_m`,
  lo que necesita Paso 2).
- `obtener_suelo_balance_hidrico(parametros, soil_id)`: mismo patrón,
  arma la estructura completa que necesita Paso 4
  (`list(cn, kl, um, u, dr, horizontes)`) a partir de `suelos` en el YAML,
  validando que estén los 6 campos requeridos.
- `obtener_factor_rastrojo()` / `obtener_fraccion_humedad_inicial()`: mismo
  patrón, sobre `constantes` (sección 8.3).

## 12. Testing

- **Pasos 1-4, trigo:** validado contra valores **reales cacheados** de la
  planilla de referencia (estación 87480, cultivar intermedio-largo, siembra
  1983-05-30), tolerancia `1e-9`. Paso 4 en particular: 428 días de fixture
  (1983-03-01 a 1984-05-01, suelo `IN64MARC02`) con comparación completa de
  las ~78 columnas de salida en 17 fechas de control
  (`tests/testthat/fixtures/`), usando `Prof`/`Kcb` **literales** de la
  fuente de referencia como input (no la salida real de Pasos 1-2), para
  desacoplar la validación de fórmulas de Paso 4 de la corrección de
  Pasos 1-2.
- **Maíz y soja (Pasos 1 y 3):** sin fixture cruzado contra la planilla de
  referencia (solo tuvo cacheado el escenario de trigo en todas las rondas
  recibidas). Se
  usan climas sintéticos con resultado calculable a mano, dirigidos
  específicamente a los mecanismos nuevos de cada cultivo — ver
  `FUTURE_WORK.md`.
- **Paso 5:** fixtures sintéticos a mano (no hay valores de referencia
  cacheados para estas 3 salidas).
- Estado al 2026-08-01: **1459 tests en verde**, `devtools::check()` limpio
  (0 errores, 0 warnings; 3 NOTEs preexistentes sin relación al código:
  directorios no estándar `.claude/`/`scripts/`/`salidas/`, y "unable to
  verify current time" del entorno sandbox).

## 12bis. Relleno de gaps climáticos (`R/imputacion_clima.R`, 2026-08-13)

No es parte del método CRC-SAS — es un paso de preprocesamiento de
calidad de dato, agregado para el batch de Junín (`condiciones_iniciales.xlsx`
de Guillermo), cuya estación real tiene días puntuales sin dato en 35
años de serie. El balance hídrico es secuencial (cada día depende del
anterior), así que un solo día `NA` invalida el resto del ciclo que lo
contiene — de ahí la necesidad de completarlos antes de correr el batch,
en vez de dejarlos fallar.

`completar_gaps_clima(clima, semilla = 1234)` (exportada) solo rellena
corridas de `NA` **acotadas por dato real de ambos lados** — las que
llegan hasta el primer o el último día de la serie (p.ej. el resto de un
año en curso, todavía no observado) quedan intactas a propósito, no son
huecos.

**Temperaturas (`tx`, `tn`, `tm`) — tratadas de forma conjunta, no como 3
series independientes** (generarlas por separado podría dar `tn > tx`,
físicamente imposible y roto para `sqrt(tx-tn)` de
`calcular_eto_hargreaves()`, ver sección 8.10):
1. `tx` es la serie "primaria": descomposición STL (`stlplus`, tolera
   `NA`, a diferencia de `stats::stl()`) → tendencia + estacionalidad;
   sobre el residuo se ajusta un AR(1) y se genera el valor faltante como
   una **muestra** (no el promedio) de la distribución condicional a los
   valores reales inmediatos antes/después del hueco — un suavizado tipo
   Kalman/RTS con fórmula cerrada (`.ar1_bridge_muestra()`), sin
   depender de un paquete de Kalman aparte. La varianza de la innovación
   se escala por trimestre del año (la variabilidad día a día no es
   constante en el año).
2. `tn` se **deriva** de `tx`: se modela el rango térmico (`tx-tn`) en
   escala logarítmica (siempre positivo) con el mismo método, y se
   calcula `tn = tx_completo - rango_generado` — garantiza `tn < tx` por
   construcción, incluso el día en que faltan los dos juntos (`tx` ya
   está completo del paso 1).
3. Salvaguarda física final (`pmax`/`pmin`) para el único caso que el
   paso 2 no cubre solo: falta *sólo* `tx` con `tn` real presente ese
   día. No se dispara con los datos reales de hoy.
4. `tm` nunca se modela por separado — siempre se deriva al final con
   `calcular_temperatura_media()` (fórmula exacta ya usada en el resto
   del paquete, ver sección 10), reutilizando código ya testeado en vez
   de reinventar algo.

**Precipitación (`pp`)**: modelo de dos partes tipo Richardson (1981,
WGEN) — ocurrencia vía cadena de Markov de 2 estados (`P(llueve hoy |
ayer llovió)` vs `P(llueve hoy | ayer seco)`, estimada de toda la serie
histórica), monto condicional a que llueva vía una distribución gamma
ajustada por máxima verosimilitud (`MASS::fitdistr`) sobre los días de
lluvia históricos.

Reproducible (`set.seed(semilla)` al principio, documentado como efecto
de lado sobre el RNG global). Verificado contra los datos reales de
Junín: deja 0 `NA` en el registro real, nunca genera `tn > tx` ni
`pp < 0`, corre en ~0.25s. Tests en `tests/testthat/test-imputacion_clima.R`,
incluyendo un chequeo numérico independiente del bridge AR(1) (derivación
analítica vía normal multivariada condicionada, no solo releer la misma
fórmula secuencial del código de producción).

**Hallazgo relacionado (mismo batch, no es parte de esta función)**:
`scripts/lib_simular.R::.recortar_clima_escenario()` tenía un margen de
15 días después de la madurez fisiológica "por las dudas", sin
justificación real (`calcular_salidas()`, sección 9, solo necesita
`[siembra-14, siembra+7]` y el período crítico, bien antes de la
madurez) — para escenarios cuya madurez cae cerca del borde de los datos
reales (soja 2025, madurez 2026-07-31, corte real 2026-08-11) ese margen
empujaba la ventana más allá del dato real. Corregido a `margen_dias = 0`.

## 13. Mapa del repo

```
balance-hidrico/
  README.md                          — overview, instalacion, uso
  DESCRIPTION, NAMESPACE, LICENSE     — metadata del paquete R
  R/                                  — codigo fuente (ver secciones 5-11 y 12bis)
  man/                                — documentacion generada (roxygen2)
  tests/testthat/                     — tests automatizados (ver seccion 12)
  inst/extdata/                       — CSV de clima, YAML de parametros y de constantes de ejemplo
  scripts/simular.R                   — corrida de un escenario puntual (Pasos 1-5) -> 4 CSV
  scripts/escenario_ejemplo.yml       — YAML de configuracion de ejemplo para simular.R
  scripts/simular_batch.R             — corrida batch (multiples escenarios x anios) -> 4 CSV + errores
  scripts/batch_ejemplo.yml           — YAML de configuracion de ejemplo para simular_batch.R
  scripts/lib_simular.R               — logica compartida entre simular.R y simular_batch.R
  documentacion/
    MANUAL_TECNICO.md                 — este documento
    FUTURE_WORK.md                    — lo pendiente (no historico, no implementado)
```

Los documentos de trabajo originales de CRC-SAS (con las distintas rondas
de respuestas del experto) nunca se commitearon a este repo y no deben
asumirse disponibles — todo lo relevante de esas fuentes está volcado en
este documento.
