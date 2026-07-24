# Manual tecnico — balancehidrico

Este documento explica **como** esta implementado cada proceso del paquete:
las formulas exactas, de donde salen, que decisiones de diseno se tomaron y
por que, y como se mapean al codigo. Para el contexto del proyecto (por que
existe, que se decidio y cuando) ver `CONTINUIDAD_DESARROLLO.md`. Para como
usar el paquete, ver el `README.md` de la raiz del repo.

Fuente de verdad del metodo: `referencias/documento_maestro_fenologia_balance_hidrico.md`
(sintesis) y `referencias/Documento trabajo fenologia y balance hidrico.docx`
+ `referencias/Calculos fenologia y balance hidrico.xlsx` (fuentes originales
de CRC-SAS, version con las respuestas del experto ya incorporadas).

## Arquitectura general

El paquete separa **lectura de datos** (`R/io.R`), **utilidades climaticas
compartidas** (`R/utils_clima.R`) y **un archivo por paso del metodo**
(`R/fenologia.R`, `R/profundizacion_radicular.R`, `R/curva_kcb.R`). Cada paso
es una funcion pura: recibe datos ya parseados (tibbles/listas), no hace I/O,
y no depende del estado interno de los otros pasos — se comunican pasandose
tibbles/fechas explicitas. Esto permite testear cada paso de forma aislada
(ver `tests/testthat/`) y es deliberado: el balance hidrico (Paso 4, no
implementado aca) va a necesitar recombinar estos resultados de formas que
todavia no estan definidas, y el bajo acoplamiento evita tener que reescribir
Pasos 1-3 cuando eso pase.

### Contrato de datos entre pasos

```
calcular_fenologia(cultivo, cultivar, clima_estacion, fecha_siembra, parametros)
  -> list(
       hitos = tibble de 1 fila: siembra, emergencia, fin_kcb_inicial,
               inicio_kcb_maximo, hito1, nombre_hito1, hito2, nombre_hito2,
               inicio_periodo_critico, fin_periodo_critico, madurez_fisiologica
       serie_diaria = tibble: date, doy, tm, fp, ut_simple_acum
     )
```

`hito1`/`hito2` son un alias generico: el nombre real depende del cultivo
(`nombre_hito1`/`nombre_hito2` lo indican como texto: "ET"/"Z71" en trigo,
"R2"/"R2" en maiz, "R1"/"R5" en soja). Esto es lo que permite que
`calcular_profundidad_radicular()` sea **crop-agnostic**: solo necesita
`fecha_emergencia` y `fecha_hito2`, sin saber que cultivo es.

`ut_simple_acum` (columna `serie_diaria`) es la serie de unidades termicas
acumuladas **sin** ajuste de fotoperiodo desde emergencia — es la que
consume `calcular_curva_kcb()` (ver duda KC-2 mas abajo).

```
calcular_profundidad_radicular(clima_estacion, fecha_emergencia, fecha_hito2,
                                tb_c, pr_s_e, pr, profundidad_maxima_suelo)
  -> tibble: date, profundidad_radical_m

calcular_curva_kcb(serie_ut_simple, ut_fkcbini, ut_ikcbmax, kcb_ini, kcb_max)
  -> tibble: date, kcb
```

## Paso 1 — Fenologia (`R/fenologia.R`)

### Marco general

Cada etapa fenologica se define por una cantidad de **unidades termicas**
(UT, °C-dia) que deben acumularse desde un hito anterior. El incremento
diario de UT es `max(0, Tm - Tb)`, con `Tb` (temperatura base) especifica de
cada cultivo/etapa. La temperatura media (`Tm`) se toma de la base climatica
si esta disponible; si no, se calcula como `(Tx+Tn)/2`
(`calcular_temperatura_media()`, duda **F-7**).

`calcular_fenologia()` es el dispatcher publico: resuelve la latitud de la
estacion y los parametros del cultivar (`obtener_latitud_estacion()`,
`obtener_parametros_cultivo()`), calcula `tm` y `fp`
(`calcular_fotoperiodo()`) para toda la serie climatica desde la siembra, y
delega en la funcion especifica del cultivo.

Internamente, encontrar la fecha en que una etapa termina es: acumular UT
dia a dia (`cumsum()`) y tomar la primera fecha en que el acumulado alcanza
el umbral (`.fecha_en_umbral()`, funcion interna no exportada). Como los
incrementos diarios nunca son negativos, la serie acumulada es monotona no
decreciente, asi que esa primera fecha es unica y bien definida — es el
equivalente en R de la resolucion por `COUNTIFS + INDEX` que usa el xlsx de
referencia.

### Trigo (`calcular_fenologia_trigo()`)

El trigo responde al fotoperiodo (dia largo) **solo entre Emergencia (E) y
Espiguilla Terminal (ET)**; despues es insensible (duda **F-6**). El factor
fotoperiodico es una funcion cuadratica centrada en 20 h, modulada por la
respuesta del cultivar al fotoperiodo (`RCF`):

```
factor_fp = max(0, 1 - ((20 - min(20, Fp))^2 * 0.01 * RCF))
```

El `min(20, Fp)` es clave (duda **F-5**): sin el, el factor tambien
penalizaria fotoperiodos **mayores** a 20 h (la formula es cuadratica y
simetrica), lo cual no es lo que pide el metodo — por encima de 20 h el
efecto del fotoperiodo debe ser nulo (factor = 1). Con el `min`, para
`Fp >= 20` el termino `(20 - min(20,Fp))` es 0 y el factor queda en 1.

Secuencia de hitos:

| Hito | Formula (UT desde el hito anterior) | Con ajuste de Fp |
|---|---|---|
| Emergencia (E) | Siembra + `ut_s_e` | No |
| Fin Kcb inicial | E + `ut_e_fkcbini` | No |
| Inicio Kcb maximo | E + `ut_e_ikcbmax` | No |
| Espiguilla Terminal (ET, **hito1**) | E + `ut_e_et` | **Si** (factor_fp con RCF) |
| Inicio periodo critico | ET + `ut_et_ipc` | No |
| Z71 (cuaje de granos, **hito2**) | ET + `ut_et_z71` | No |
| Fin periodo critico | ET + `ut_et_fpc` | No |
| Madurez fisiologica | Fin periodo critico + `ut_fpc_mf` | No |

**Duda F-1 (bloqueante, resuelta):** Z71 y fin de periodo critico (fPC) son
**dos hitos distintos**, ambos relativos a ET: `Z71 = ET + 700`,
`fPC = ET + 800`. Una version anterior del documento los trataba como el
mismo hito, lo que generaba una discrepancia de 100°C-dia en fPC y en
madurez fisiologica (`MF = fPC + 400`). El xlsx v2 ya separa ambos parametros
(`UT_ET-Z71` y `UT_ET-fPC`) y lo documenta explicitamente. El codigo usa
`params$ut_et_z71` y `params$ut_et_fpc` como dos umbrales independientes
sobre la misma serie acumulada post-ET.

Fin de periodo critico e inicio de periodo critico y Z71 se resuelven todos
sobre la **misma** serie acumulada iniciada en ET (no se reinicia en cada
hito): el codigo construye un unico `acum_post_et` y busca los tres umbrales
sobre el (`ut_et_ipc`, `ut_et_z71`, `ut_et_fpc`), y madurez fisiologica es el
umbral `ut_et_fpc + ut_fpc_mf` sobre esa misma serie (matematicamente
equivalente a "seguir acumulando desde fPC hasta sumar 400 mas", duda
**F-2**: todo se define relativo a ET, no a Z71).

### Maiz (`calcular_fenologia_maiz()`)

El maiz **no responde al fotoperiodo** (duda F-6). La temperatura base
cambia de `tb_a` (Siembra->Emergencia) a `tb_b` (Emergencia en adelante). En
maiz, R2 (cuaje de granos) es **a la vez hito1 y hito2** (no hay una etapa
intermedia como el ET del trigo).

La simplificacion clave de maiz es que **todos** los hitos posteriores a la
emergencia (fin Kcb inicial, inicio Kcb maximo, inicio de periodo critico,
R2, fin de periodo critico, madurez fisiologica) se resuelven sobre una
**unica** serie acumulada de UT (base `tb_b`, sin ajuste de fotoperiodo),
cada uno en su propio umbral absoluto **tomado directamente del cultivar**
(`ut_e_fkcbini`, `ut_e_ikcbmax`, `ut_e_ipc`, `ut_e_r2`, `ut_e_fpc`,
`ut_r2_mf`). Los umbrales de periodo critico (`R2-450` y `R2+100` segun el
documento) **ya vienen precalculados como valores absolutos** en la tabla de
parametros (p.ej. para el cultivar templado-corto: `ut_e_r2=950`,
`ut_e_ipc=500=950-450`, `ut_e_fpc=1050=950+100`) — el codigo no resta/suma
esas constantes, usa los valores de la tabla directamente, para no duplicar
la aritmetica en dos lugares (parametros y codigo) y quedar expuesto a que
se desincronicen.

### Soja (`calcular_fenologia_soja()`)

La soja responde al fotoperiodo (dia corto) **durante todo el ciclo**, desde
Emergencia hasta Madurez Fisiologica, con dos mecanismos que la distinguen
del trigo:

1. **Temperatura optima (`to_a`):** el incremento diario usa
   `min(Tm, to_a) - Tb`, no `Tm - Tb`. Por encima de `to_a` (27°C) las UT
   diarias no siguen aumentando. Aplica en **todas** las fases, incluida
   Siembra->Emergencia (a diferencia de trigo/maiz, que no tienen `to_a`).
2. **Umbral de fotoperiodo (`FpU`), penalizacion lineal:** a diferencia del
   factor cuadratico continuo del trigo, la soja usa un umbral discreto por
   etapa y cultivar (`fpu_e_r1` para Emergencia->R1, `fpu_r1_mf` para
   R1->Madurez Fisiologica). Por debajo del umbral no hay penalizacion; por
   encima, la acumulacion diaria se reduce linealmente a razon de 0.3 por
   hora de exceso:

   ```
   factor_fpu = min(1, max(0, 1 - max(0, Fp - FpU) * 0.3))
   ```

   Nota de diseno (duda **F-6**): aunque el documento describe el efecto del
   fotoperiodo con una frase generica ("por debajo o por encima segun
   cultivo") para los tres cultivos, el **mecanismo** es distinto en cada
   uno: trigo usa una funcion cuadratica continua centrada en 20 h; soja usa
   un umbral discreto con penalizacion lineal. No son la misma formula con
   distintos parametros.

Secuencia de hitos:

| Hito | Formula | Umbral Fp usado |
|---|---|---|
| Emergencia (E) | Siembra + `ut_s_e` | — |
| Fin Kcb inicial | E + `ut_e_fkcbini` | — (sin penalizacion) |
| Inicio Kcb maximo | E + `ut_e_ikcbmax` | — (sin penalizacion) |
| R1 (**hito1**) | E + `ut_e_r1` | `fpu_e_r1` |
| Inicio periodo critico | R1 + `ut_r1_ipc` | `fpu_r1_mf` |
| R5 (cuaje de granos, **hito2**) | R1 + `ut_r1_r5` | `fpu_r1_mf` |
| Fin periodo critico | R1 + `ut_r1_r5` + `ut_r5_fpc` | `fpu_r1_mf` |
| Madurez fisiologica | R1 + `ut_r1_r5` + `ut_r5_mf` | `fpu_r1_mf` |

**Duda F-3 (resuelta):** `UT_R1-R5` (`ut_r1_r5`) es una constante fija de
**300** (no varia por cultivar ni por condiciones). Esto es lo que hace que
`iPC = R1+120` y `iPC = R5-180` sean equivalentes numericamente (300-180=120)
— el codigo usa la definicion `R1+120` (relativa a R1) como canonica, y
`ut_r1_r5=300` esta fijo en la tabla de parametros de todos los cultivares.

Notese que "fin Kcb inicial" e "inicio Kcb maximo" se calculan sobre la
serie **sin** penalizacion de fotoperiodo (`incr_simple`, misma serie que
consume Curva Kcb), mientras que desde R1 en adelante (iPC, R5, fPC, MF) se
usa la serie penalizada por `fpu_r1_mf` de forma continua (no se reinicia en
cada hito, igual que en trigo desde ET).

## Paso 2 — Profundizacion radicular (`R/profundizacion_radicular.R`)

`calcular_profundidad_radicular()` implementa:

1. Profundidad constante `pr_s_e` (m) entre siembra y emergencia.
2. Desde emergencia, crecimiento a tasa `pr` (cm/°C, base `tb_c`):
   `profundidad = pr_s_e + (pr * UT_acumulada_raiz) / 100`.
3. Congelamiento en `fecha_hito2` (cuaje de granos: Z71 en trigo, R2 en
   maiz, R5 en soja) — la profundidad no sigue creciendo despues, aunque el
   clima continue.

La acumulacion de UT de raiz es **independiente** de las series de
fenologia: usa su propia temperatura base `tb_c` (no `tb_a`/`tb_b`), y solo
depende de `fecha_emergencia`/`fecha_hito2` como limites — de ahi que esta
funcion no necesite saber que cultivo es (recibe las fechas ya resueltas por
`calcular_fenologia()`).

**Duda PR-1 (resuelta, con nota de implementacion):** el documento especifica
que la raiz crece "hasta la profundidad maxima del suelo **o** el cuaje de
granos, lo que ocurra primero". El xlsx de referencia (hoja `fenologia`) solo
implementa el congelamiento por cuaje — esa hoja no tiene contexto de suelo,
asi que no puede aplicar el segundo tope. **Esto no es un vacio de
especificacion**, es una limitacion de esa hoja en particular. El codigo de
este paquete si aplica ambos topes: el parametro `profundidad_maxima_suelo`
(por defecto `Inf`, sin tope) se aplica con un `pmin()` final sobre toda la
serie. Se resuelve consultando `obtener_profundidad_maxima_suelo()` sobre la
tabla `suelos` del YAML de parametros.

## Paso 3 — Curva de Kcb (`R/curva_kcb.R`)

`calcular_curva_kcb()` implementa una rampa lineal simple en tres tramos, en
funcion de `ut_simple_acum` (la serie de UT **sin** ajuste de fotoperiodo que
devuelve `calcular_fenologia()` en `serie_diaria`):

```
Kcb = kcb_ini                                              si UT <= ut_fkcbini
Kcb = kcb_max                                               si UT >= ut_ikcbmax
Kcb = kcb_ini + (kcb_max - kcb_ini) * (UT - ut_fkcbini) / (ut_ikcbmax - ut_fkcbini)   en el medio
```

**Duda KC-2 (resuelta):** la serie usada para la rampa es explicitamente la
que **no** tiene ajuste de fotoperiodo (columna `P` / "E->simple" del xlsx de
referencia), no la serie fenologica ajustada por Fp/RCF/FpU. Esto es
deliberado: la velocidad de desarrollo del canopeo (lo que mide Kcb) no
depende del fotoperiodo de la misma forma que la fenologia reproductiva.

**Duda KC-1 (resuelta):** `kcb_max` se mantiene **constante** desde
`ut_ikcbmax` hasta madurez fisiologica — no hay rampa descendente de
senescencia, aunque agronomicamente el Kcb real deberia bajar hacia el final
del ciclo (asi es en FAO-56 dual estandar). Esto es una **decision de diseno
deliberada**, no un vacio de especificacion: el unico output relevante de la
herramienta (confort hidrico) se calcula solo hasta el **fin del periodo
critico**, que ocurre antes de que la caida de Kcb en senescencia importe. Si
en el futuro la herramienta necesita reportar algo mas alla del fin del
periodo critico (p.ej. como parte del Paso 4), esta decision deberia
revisarse.

## Utilidades climaticas (`R/utils_clima.R`)

- `calcular_temperatura_media(tx, tn, tm)`: usa `tm` si no es `NA`; si no,
  `(tx+tn)/2` (duda F-7).
- `calcular_declinacion_solar(dia_anio)`:
  `23.45 * sin(radians(360/365 * (dia_anio - 81)))`.
- `calcular_fotoperiodo(dia_anio, latitud)`: formula estandar del angulo
  horario (`24/pi * acos(-tan(lat)*tan(decl))`), con los casos extremos de
  dia/noche polar resueltos explicitamente (si el argumento del `acos` cae
  fuera de `[-1,1]`, el sol no sale — Fp=0 — o no se pone — Fp=24 — segun el
  signo) en vez de dejar que `acos()` devuelva `NaN`.

Estas formulas se verificaron contra los valores **cacheados** de la hoja
`clima` del xlsx de referencia (estacion 87480, dia 1 y dia 99 del anio) —
ver `tests/testthat/test-utils_clima.R`.

## Entrada/salida y validacion (`R/io.R`)

- `leer_clima_csv(path)`: valida que existan las columnas requeridas
  (`station_id`, `date`, `tx`, `tn`); agrega `doy`.
- `leer_parametros_yaml(path)`: valida que exista la seccion `cultivos`.
- `obtener_parametros_cultivo(parametros, cultivo, cultivar)`: falla con un
  mensaje explicito (`rlang::abort()`) si el cultivo o cultivar no existen,
  listando las opciones disponibles. Esto es deliberado: el desarrollo de
  Thread A (la version DSSAT del pipeline, en `lib/fenologia.R` del repo
  `balance_agua_suelo`) tuvo un antecedente de bugs por parametros faltantes
  que se propagaban silenciosamente como `NULL` hasta romper mucho mas
  abajo. Aca se prefiere fallar rapido y cerca del origen del problema.
- `obtener_latitud_estacion()` / `obtener_profundidad_maxima_suelo()`:
  mismos principios, para las tablas `estaciones` y `suelos` del YAML.

## Testing

Ver `tests/testthat/`. Resumen de la estrategia (detalle en
`CONTINUIDAD_DESARROLLO.md`):

- **Trigo:** validado contra valores reales cacheados del xlsx de
  referencia (8 hitos fenologicos + puntos de control de la serie diaria de
  UT, profundidad radicular y Kcb), tolerancia `1e-9`.
- **Maiz y soja:** el xlsx de referencia solo tiene cacheado el escenario de
  trigo (no hay LibreOffice/Excel disponible para recalcular con otro
  cultivo activo). Se usan climas sinteticos (temperaturas y fotoperiodos
  constantes) donde el resultado esperado se calcula a mano de forma
  independiente del codigo — cubren especificamente los mecanismos nuevos
  de cada cultivo (tope `to_a`, penalizacion `FpU`, UT_R1-R5 fijo en soja;
  serie unica multi-umbral en maiz).
