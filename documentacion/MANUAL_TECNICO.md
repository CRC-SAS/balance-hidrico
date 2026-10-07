# Manual técnico — Método CRC-SAS de balance hídrico de cultivos

Este documento es la **documentación teórica** de `balancehidrico`: describe
todas las ecuaciones y procedimientos que usa el método para simular
fenología, profundización radicular, coeficiente de cultivo, balance hídrico
diario y salidas de trigo, maíz y soja, incluido el procedimiento de relleno
de huecos en las series climáticas.

Es autocontenido: no requiere ninguna fuente externa para entender qué se
calcula ni por qué. Para el diseño del software, ver
[`ARQUITECTURA.md`](ARQUITECTURA.md). Para ejecutar el método, ver las guías
de uso enlazadas desde el [`README.md`](../README.md).

## Índice

1. [Alcance y notación](#1-alcance-y-notación)
2. [Datos de entrada](#2-datos-de-entrada)
3. [Preparación del clima](#3-preparación-del-clima)
   - [3.1 Temperatura media](#31-temperatura-media)
   - [3.2 Fotoperíodo](#32-fotoperíodo)
   - [3.3 Evapotranspiración de referencia (Hargreaves-Samani)](#33-evapotranspiración-de-referencia-hargreaves-samani)
   - [3.4 Relleno de huecos climáticos](#34-relleno-de-huecos-climáticos)
4. [Paso 1 — Fenología](#4-paso-1--fenología)
5. [Paso 2 — Profundización radicular potencial](#5-paso-2--profundización-radicular-potencial)
6. [Paso 3 — Curva de Kcb](#6-paso-3--curva-de-kcb)
7. [Paso 4 — Balance hídrico diario](#7-paso-4--balance-hídrico-diario)
8. [Paso 5 — Salidas](#8-paso-5--salidas)
9. [Procedimiento de simulación de un escenario](#9-procedimiento-de-simulación-de-un-escenario)
10. [Agregación multianual](#10-agregación-multianual)
11. [Supuestos y limitaciones](#11-supuestos-y-limitaciones)
12. [Tablas de parámetros](#12-tablas-de-parámetros)
13. [Referencias](#13-referencias)

---

## 1. Alcance y notación

**Objetivo.** Gestionar el riesgo climático en decisiones agrícolas
estimando, para trigo, maíz y soja, (a) la disponibilidad de agua en el suelo
a la siembra y (b) el confort hídrico del cultivo durante su período crítico.

**Dominio.** Se consulta desde una fecha de monitoreo (típicamente desde el
1° de marzo) hasta la fecha de siembra planeada. Entre ambas se asume un
barbecho libre de malezas; el cultivo simulado es siempre el primero de la
campaña. La simulación del cultivo corre desde la siembra hasta la madurez
fisiológica.

**Secuencia de cálculo.** Cinco pasos, cada uno con entradas y salidas
explícitas:

```
Clima ──► Paso 1 Fenología ──► hitos (fechas) + UT acumuladas
              │
              ├─► Paso 2 Profundización radicular potencial ──┐
              └─► Paso 3 Curva de Kcb ────────────────────────┤
                                                              ▼
Suelo + condiciones iniciales + Clima ──────────► Paso 4 Balance hídrico diario
                                                              │
                                  hitos + balance ──► Paso 5 Salidas
```

**Notación.**

| Símbolo | Significado | Unidad |
|---|---|---|
| `Tx`, `Tn`, `Tm` | temperatura máxima, mínima y media diaria | °C |
| `Pp` | precipitación diaria | mm |
| `Fp` | fotoperíodo (duración del día) | h |
| `ETo` | evapotranspiración de referencia diaria | mm |
| `UT` | unidades térmicas (tiempo térmico) | °C·día |
| `Tb` | temperatura base | °C |
| `Kcb` | coeficiente basal de cultivo | – |
| `PMP`, `CC`, `Sat` | punto de marchitez permanente, capacidad de campo y saturación | mm (por horizonte) |
| `CH` | contenido hídrico del horizonte | mm |
| `AU` | agua útil, `(CH − PMP)/(CC − PMP)` | fracción 0–1 o % |
| `PFH` | profundidad inferior acumulada de un horizonte | m |

Los subíndices `i` indican el horizonte de suelo (1 = superficial).

## 2. Datos de entrada

**Clima diario** de una estación meteorológica (serie larga, idealmente más
de 30 años): `Tx`, `Tn`, `Tm` (si no está, se calcula), `Pp` y `ETo` (si no
está, se calcula con Hargreaves-Samani, sección 3.3). El fotoperíodo no es un
dato: se calcula a partir de la latitud de la estación (sección 3.2).

**Suelo.** Cada suelo tiene horizontes (típicamente 8, de 0–0.2, 0.2–0.4,
0.4–0.6, 0.6–0.9, 0.9–1.2, 1.2–1.5, 1.5–1.8 y 1.8–2.1 m; un suelo somero puede
tener menos) con contenido volumétrico de agua en PMP, CC y Sat, y los
escalares:

| Escalar | Significado |
|---|---|
| `CN` | Curva Número (escorrentía) |
| `U` | agua evaporable en fase 1 (mm) |
| `DR` | factor de drenaje (0–1) |
| `kl` | facilidad de extracción de agua (0.1 general; 0.08 argiudol vértico / thapto nátrico; 0.05 vertisol) |
| `Um` | umbral de reducción de `kl` por textura (0.3 arenosos; 0.5 francos; 0.7 vérticos) |

**Cultivo y cultivar.** Trigo (intermedio-corto, intermedio-largo), maíz
(templado-corto, templado-intermedio, tropical-intermedio) y soja (GM 3C, GM 4L,
GM 6C). Determinan los requerimientos térmicos de cada etapa, la sensibilidad
al fotoperíodo, la tasa de profundización radicular y el Kcb (sección 12).

**Condiciones del escenario.**

- Fecha de siembra y fecha de monitoreo (primer día del balance).
- **Cantidad de rastrojo**, constante durante toda la simulación:

  | Clase | Cobertura | Factor |
  |---|---|---|
  | `Baja` | 0–20 % | 1.0 |
  | `Moderada` | 30–50 % | 0.8 |
  | `Muy_Alta` | 80–100 % | 0.5 |

- **Humedad inicial** del primer y del segundo metro de suelo, cada uno en una
  de cuatro clases:

  | Clase | Descripción | Fracción de AU |
  |---|---|---|
  | `Se` | Seco | 0.10 |
  | `mS` | Moderadamente seco | 0.35 |
  | `mH` | Moderadamente húmedo | 0.65 |
  | `Hu` | Húmedo | 0.90 |

- **Sándwich seco** inicial (sí/no): capa seca intermedia en el perfil
  (sección 7.2).

## 3. Preparación del clima

### 3.1 Temperatura media

```
Tm = Tm_observada      si existe
Tm = (Tx + Tn) / 2     si no
```

### 3.2 Fotoperíodo

Se calcula con la declinación solar y la latitud de la estación, con
corrección por crepúsculo civil (`0.1047 = sen 6°`):

```
δ       = 0.4093 · sen(0.0172 · (J − 82.2))          J = día del año, δ en radianes
φ       = latitud · 0.01745                           φ en radianes
x       = (−sen φ · sen δ − 0.1047) / (cos φ · cos δ)
x       = max(x, −0.87)
Fp      = 7.639 · acos(x)                             horas
```

La constante `0.01745` (en lugar de `π/180`) y el recorte inferior asimétrico
de `x` en −0.87 son parte de la formulación del método. Para las latitudes de
Argentina (hasta ≈ −55°) el argumento del arco-coseno no supera 1; con
latitudes fuera de ese rango la función puede devolver `NaN`. El enfoque
general de duración del día con corrección de crepúsculo sigue a
Forsythe et al. (1995).

### 3.3 Evapotranspiración de referencia (Hargreaves-Samani)

La `ETo` es un dato de entrada del Paso 4. Cuando la base climática no la trae,
se calcula con Hargreaves y Samani (1985), usando las ecuaciones 21–25 y 52 de
Allen et al. (1998, FAO-56):

```
δ   = 0.409 · sen(2π·J/365 − 1.39)                      (Eq. 24)
d_r = 1 + 0.033 · cos(2π·J/365)                         (Eq. 23)
ω_s = acos(−tan φ · tan δ)                              (Eq. 25)   φ = latitud · π/180
Ra  = (24·60/π) · Gsc · d_r · (ω_s·sen φ·sen δ + cos φ·cos δ·sen ω_s)   (Eq. 21)   Gsc = 0.0820 MJ m⁻² min⁻¹
ETo = 0.0023 · (Tm + 17.8) · √(Tx − Tn) · Ra / λ        (Eq. 52)   λ = 2.45 MJ kg⁻¹
```

La declinación solar de esta fórmula (Eq. 24 de FAO-56) es **distinta a
propósito** de la del fotoperíodo (3.2): cada una está calibrada para su
propio fin y no deben unificarse.

### 3.4 Relleno de huecos climáticos

No es parte del método agronómico: es un paso de calidad de datos. El balance
hídrico es secuencial (cada día depende del anterior), de modo que un solo
día sin dato invalida el resto del ciclo que lo contiene. Por eso los huecos
puntuales de la serie histórica se completan antes de simular.

**Qué se rellena.** Solo las corridas de días sin dato **acotadas por
observaciones reales de ambos lados**. Las corridas que llegan al primer o al
último día de la serie (por ejemplo, el resto de un año en curso todavía no
observado) quedan intactas: no son huecos, son datos que aún no existen. El
procedimiento es estocástico pero reproducible (semilla fija, por defecto
1234).

**Temperaturas (`Tx`, `Tn`, `Tm`): tratamiento conjunto.** Modelar las tres
series por separado podría producir `Tn > Tx` (físicamente imposible, y rompe
`√(Tx − Tn)` de Hargreaves-Samani). Se usa una jerarquía primario/derivado:

1. **`Tx` es la serie primaria.** Se descompone con STL (`stlplus`, que tolera
   datos faltantes) en tendencia + estacionalidad + residuo. Sobre el residuo
   se ajusta un AR(1). El valor faltante se genera como una **muestra** (no el
   promedio) de la distribución condicional a los valores reales inmediatamente
   anterior y posterior al hueco: un suavizado tipo Kalman/RTS de fórmula
   cerrada. Para un hueco de `k` días, en el paso `t` (con `m = k + 1 − t`
   pasos restantes hasta el dato real posterior `r_post`):

   ```
   μ_prior   = φ · r_(t−1)
   V_futuro  = σ² · (1 − φ^(2m)) / (1 − φ²)
   var_post  = 1 / (1/σ² + φ^(2m)/V_futuro)
   media_post = var_post · (μ_prior/σ² + φ^m · r_post / V_futuro)
   r_t ~ N(media_post, var_post)
   ```

   La varianza de innovación `σ²` se escala por trimestre del año
   (`σ² = sd_trimestre² · (1 − φ²)`), porque la variabilidad día a día no es
   constante a lo largo del año. El valor final es
   `estacionalidad + tendencia + residuo generado`.

2. **`Tn` se deriva de `Tx`.** Se modela el rango térmico `Tx − Tn` en escala
   logarítmica (siempre positivo) con el mismo método (STL + puente AR(1)) y
   se calcula `Tn = Tx_completo − exp(log-rango generado)`. Esto garantiza
   `Tn < Tx` por construcción, incluso el día en que faltan ambas.
3. **Salvaguarda física:** `Tx = max(Tx, Tn)` y `Tn = min(Tx, Tn)` donde ambas
   tengan valor. Solo actúa si falta únicamente `Tx` con una `Tn` real
   presente ese día.
4. **`Tm` nunca se modela por separado:** siempre se deriva al final con la
   fórmula de 3.1.

**Precipitación (`Pp`): modelo de dos partes tipo Richardson (1981, WGEN).**

- *Ocurrencia:* cadena de Markov de dos estados (día lluvioso: `Pp > 0.1 mm`),
  con `P(llueve hoy | llovió ayer)` y `P(llueve hoy | ayer seco)` estimadas de
  toda la serie histórica.
- *Monto:* condicional a que llueva, distribución gamma ajustada por máxima
  verosimilitud a los días de lluvia históricos.
- Los días de un hueco se recorren secuencialmente, porque el estado "llovió
  ayer" de cada día puede depender de un día del mismo hueco.

**29 de febrero.** Se excluye de la descomposición STL, que requiere un ciclo
estacional de exactamente 365 días (incluirlo corre de fase la estacionalidad
≈ 1 día cada 4 años). Si el 29-feb tiene dato real, se conserva; si falta, se
interpola linealmente entre el 28-feb y el 1-mar ya completos.

## 4. Paso 1 — Fenología

### 4.1 Marco general

Cada etapa fenológica se define por una cantidad de **unidades térmicas**
(UT) que deben acumularse desde un hito anterior. El incremento diario es

```
ΔUT = max(0, Tm − Tb)
```

con `Tb` específica de cada cultivo y etapa. El esquema es el de los modelos
de tiempo térmico CERES-Wheat/CERES-Maize (temperatura base por etapa, umbrales
térmicos, sensibilidad al fotoperíodo; Ritchie y Otter, 1985) y CROPGRO-Soybean
(umbral de fotoperíodo con penalización lineal, temperatura óptima; Boote et
al., 1998), en el marco general de acumulación térmica multicultivo de Jones et
al. (2003). La implementación es propia y no usa DSSAT.

**Búsqueda de la fecha de un hito.** Se acumula `ΔUT` día a día desde el hito
de partida (`acum = Σ ΔUT`) y el hito ocurre el **primer día en que `acum`
alcanza el umbral**. Como `ΔUT ≥ 0`, la serie es monótona no decreciente y esa
fecha es única.

La serie desde la siembra usa `Tm` (3.1) y `Fp` (3.2) de cada día.

### 4.2 Trigo

El trigo responde al fotoperíodo (día largo) **solo entre Emergencia (E) y
Espiguilla Terminal (ET)**; después es insensible. El factor fotoperiódico es
una función cuadrática centrada en 20 h, modulada por la respuesta del
cultivar (`RCF`):

```
factor_Fp = max(0, 1 − (20 − min(20, Fp))² · 0.01 · RCF)
```

El `min(20, Fp)` hace que por encima de 20 h el efecto sea nulo (factor 1);
sin él, la parábola penalizaría también fotoperíodos mayores a 20 h. A mayor
`RCF`, menor acumulación diaria en la etapa sensible y mayor duración.

Temperatura base 0 °C en todo el ciclo. Secuencia de hitos (todos los
umbrales son UT desde el hito indicado):

| Hito | Definición | Ajuste por Fp |
|---|---|---|
| Emergencia (E) | Siembra + `ut_s_e` (150) | no |
| Fin Kcb inicial | E + `ut_e_fkcbini` (300) | no |
| Inicio Kcb máximo | E + `ut_e_ikcbmax` (1000) | no |
| Espiguilla terminal (ET, *hito 1*) | E + `ut_e_et` (400) | **sí** (`factor_Fp`) |
| Inicio período crítico | ET + `ut_et_ipc` (100) | no |
| Z71, cuaje de granos (*hito 2*) | ET + `ut_et_z71` (700) | no |
| Fin período crítico | ET + `ut_et_fpc` (800) | no |
| Madurez fisiológica | Fin período crítico + `ut_fpc_mf` (400) | no |

Z71 y el fin del período crítico son **hitos distintos**, ambos relativos a
ET (ET+700 y ET+800). Los hitos posteriores a ET se resuelven sobre una única
serie acumulada que arranca en ET (no se reinicia en cada hito); la madurez
fisiológica es el umbral `ut_et_fpc + ut_fpc_mf` sobre esa misma serie.

`RCF`: intermedio-corto 0.7; intermedio-largo 0.85.

### 4.3 Maíz

El maíz **no responde al fotoperíodo**. La temperatura base es `tb_a = 10 °C`
entre siembra y emergencia y `tb_b = 8 °C` desde emergencia. El cuaje de
granos (R2) es a la vez *hito 1* y *hito 2*.

Todos los hitos posteriores a la emergencia (fin Kcb inicial, inicio Kcb
máximo, inicio de período crítico, R2, fin de período crítico y madurez
fisiológica) se resuelven sobre **una única serie acumulada** (base `tb_b`,
sin fotoperíodo) con umbrales absolutos desde la emergencia, tomados
directamente de la tabla del cultivar (`ut_e_fkcbini = 120`,
`ut_e_ikcbmax = 560`, `ut_e_ipc`, `ut_e_r2`, `ut_e_fpc`; la madurez
fisiológica es `ut_e_r2 + ut_r2_mf`). El inicio y el fin del período crítico
equivalen a R2 − 450 y R2 + 100 y se cargan ya como valores absolutos en la
tabla (sección 12).

### 4.4 Soja

La soja responde al fotoperíodo (día corto) **durante todo el ciclo** desde
la emergencia, con dos mecanismos propios:

1. **Temperatura óptima `to_a = 27 °C`:** el incremento diario es
   `max(0, min(Tm, to_a) − Tb)`. Aplica en todas las fases, incluida
   siembra → emergencia.
2. **Umbral de fotoperíodo (`FpU`) con penalización lineal** de 0.3 por hora de
   exceso:

   ```
   factor_FpU = min(1, max(0, 1 − max(0, Fp − FpU) · 0.3))
   ```

   con `FpU` por etapa y cultivar: `fpu_e_r1` (E → R1) y `fpu_r1_mf` (R1 →
   madurez).

Trigo y soja no usan la misma fórmula con distintos parámetros: el trigo usa
una función cuadrática continua centrada en 20 h; la soja, un umbral discreto
con penalización lineal.

Temperaturas base `tb_a = 10 °C` (siembra → E) y `tb_b = 7 °C` (E → madurez).

| Hito | Definición | `FpU` aplicado |
|---|---|---|
| Emergencia (E) | Siembra + `ut_s_e` (100) | – |
| Fin Kcb inicial | E + `ut_e_fkcbini` (180) | sin penalización |
| Inicio Kcb máximo | E + `ut_e_ikcbmax` (840) | sin penalización |
| R1 (*hito 1*) | E + `ut_e_r1` (400) | `fpu_e_r1` |
| Inicio período crítico | R1 + `ut_r1_ipc` (120) | `fpu_r1_mf` |
| R5, cuaje de granos (*hito 2*) | R1 + `ut_r1_r5` (300) | `fpu_r1_mf` |
| Fin período crítico | R1 + `ut_r1_r5` + `ut_r5_fpc` (200) | `fpu_r1_mf` |
| Madurez fisiológica | R1 + `ut_r1_r5` + `ut_r5_mf` (800) | `fpu_r1_mf` |

`UT_R1→R5` es una constante de 300, lo que vuelve equivalentes `R1 + 120` y
`R5 − 180` para el inicio del período crítico; se usa `R1 + 120` como
definición. "Fin Kcb inicial" e "inicio Kcb máximo" se calculan sobre la serie
**sin** penalización por fotoperíodo (la misma que consume el Paso 3). Desde R1
se usa la serie penalizada por `fpu_r1_mf` de forma continua, sin reiniciarla
en cada hito.

### 4.5 Productos del Paso 1

- `hitos`: fechas de siembra, emergencia, fin Kcb inicial, inicio Kcb máximo,
  *hito 1* y *hito 2* (con su nombre: ET/Z71 en trigo, R2/R2 en maíz, R1/R5
  en soja), inicio y fin del período crítico y madurez fisiológica.
- `serie diaria de UT acumuladas sin ajuste de fotoperíodo` desde la
  emergencia, que consume el Paso 3.

## 5. Paso 2 — Profundización radicular potencial

La profundidad potencial de la raíz `PRP(t)` (m) se calcula así:

1. Entre siembra y emergencia es constante: `pr_s_e = 0.20 m` (los tres
   cultivos).
2. Desde la emergencia crece a razón `pr` (cm/°C) sobre su propia acumulación
   térmica `UT_raíz`, con base `tb_c`:

   ```
   UT_raíz(t) = Σ max(0, Tm − tb_c)      desde emergencia
   PRP(t)     = pr_s_e + pr · UT_raíz(t) / 100
   ```

   Trigo: `pr = 0.13`, `tb_c = 0 °C`. Maíz y soja: `pr = 0.20`, `tb_c = 8 °C`.
3. La raíz **se congela en el hito 2** (cuaje de granos: Z71, R2 o R5): la
   `UT_raíz` deja de acumularse.
4. La profundidad se topa con la **profundidad máxima del suelo**:
   `PRP = min(PRP, profundidad_máxima)`.

La acumulación térmica de raíz es independiente de la fenológica: solo usa los
límites emergencia y hito 2. Esta es la curva **potencial**; la limitación por
sequía se aplica día a día en el Paso 4 (sección 7.5).

## 6. Paso 3 — Curva de Kcb

El coeficiente basal de cultivo sigue una rampa lineal de tres tramos en
función de las UT acumuladas **sin ajuste de fotoperíodo** desde la emergencia:

```
Kcb = kcb_ini                                                     si UT ≤ ut_fkcbini
Kcb = kcb_max                                                     si UT ≥ ut_ikcbmax
Kcb = kcb_ini + (kcb_max − kcb_ini) · (UT − ut_fkcbini) / (ut_ikcbmax − ut_fkcbini)    en el medio
```

`kcb_ini = 0.15` y `kcb_max = 1.10` para los tres cultivos. `Kcb` puede
superar 1 con coberturas del canopeo del 80–85 % (IAF ≈ 3.0–3.5), de acuerdo
con el coeficiente dual de cultivo de FAO-56 (Allen et al., 1998).

Se usa la serie **sin** fotoperíodo porque la velocidad de desarrollo del
canopeo no depende del fotoperíodo de la misma forma que la fenología
reproductiva. `kcb_max` se mantiene constante hasta el final de la serie, sin
rampa descendente de senescencia (ver sección 11).

Antes de la emergencia, y para fechas fuera de la serie del cultivo, el
balance asume `Kcb = 0` y profundidad radicular `0` (todavía no hay cultivo).

## 7. Paso 4 — Balance hídrico diario

Simula día a día el contenido hídrico del suelo por horizonte, a partir de la
oferta (agua inicial, lluvia, capacidad de extracción de las raíces) y la
demanda (`ETo` ponderada por `Kcb`). El cálculo es secuencial: el estado de
cada día depende del anterior. El orden de operaciones de cada día es:

```
agua de cada horizonte del día previo → profundiza la raíz → llueve →
escurre → infiltra → transpira → evapora → drena → agua al final del día
```

### 7.1 Suelo en milímetros

Con `PFH_0 = 0`:

```
espesor_i = PFH_i − PFH_(i−1)
PMP_i (mm) = pmp_frac_i · espesor_i · 1000
CC_i  (mm) = cc_frac_i  · espesor_i · 1000
Sat_i (mm) = sat_frac_i · espesor_i · 1000
```

**Primer y segundo metro.** El primer metro son los horizontes 1 a
`min(4, n)`; el segundo metro, los siguientes hasta un máximo de 4 más
(`min(4,n)+1` a `min(8,n)`), con `n` la cantidad de horizontes del suelo. En un
suelo de 8 horizontes: primer metro = 0–0.9 m (horizontes 1–4) y segundo metro
= 0.9–2.1 m (horizontes 5–8). En un suelo de 5 horizontes el segundo metro es
solo el horizonte 5. Horizontes más allá del 8° participan del balance pero no
de ninguno de los dos metros.

### 7.2 Contenido hídrico inicial (día 1)

```
CH_i = (CC_i − PMP_i) · AU_i + PMP_i
```

con `AU_i` igual a la fracción de la clase de humedad del primer metro
(horizontes del primer metro) o del segundo metro (resto).

**Sándwich seco.** Si se declara al inicio, el horizonte 4 (0.6–0.9 m) se
fuerza a `AU = 0.10`, independientemente de la humedad declarada para el
primer metro. Los demás horizontes siguen su clase.

### 7.3 Escorrentía e infiltración

Método de la Curva Número (USDA-SCS, 1972) con abstracción inicial dinámica:

```
Absi = 0.15 · (Sat_1 − max(CH_1, PMP_1)) / (Sat_1 − PMP_1)
AtM  = 254 · (100/CN − 1)
Esc  = max(0, Pp − Absi·AtM)² / (Pp + AtM·(1 − Absi))
Inf  = Pp − Esc
```

`AtM` es la retención potencial máxima. `Absi` vale 0 con el horizonte
superficial saturado y hasta 0.15 con el horizonte en PMP; reemplaza al
coeficiente fijo `λ = 0.2` del método clásico (ver la discusión de `λ` variable
en Hawkins et al., 2009).

### 7.4 Demanda hídrica

```
DemT = ETo · Kcb                               demanda transpirativa
DemE = max(0, ETo · max(0, 1 − Kcb) · Rastrojo)    demanda evaporativa
```

El `max(0, 1 − Kcb)` interno protege contra `Kcb > 1`.

### 7.5 Profundización radicular efectiva (PRE) y limitación hídrica (LHPR)

La curva potencial `PRP` (Paso 2) se ajusta cada día según el agua disponible
en el horizonte hacia el que avanza el frente radicular:

```
ΔPRP = PRP(t) − PRP(t−1)       si PRP(t) > 0.2, si no 0

LHPR = 1                                                   si PRE(t−1) < PFH_1
LHPR = min(1, (CH_j − PMP_j) / (0.3·(CC_j − PMP_j)))       si PFH_(j−1) ≤ PRE(t−1) < PFH_j   (2 ≤ j ≤ n)
LHPR = 0                                                   si PRE(t−1) ≥ PFH_n

PRE(t) = 0                           si PRP(t) < 0.2
PRE(t) = 0.2                         si PRP(t) = 0.2
PRE(t) = PRE(t−1) + ΔPRP · LHPR      en otro caso
```

`j` es el horizonte específico hacia el que avanza la raíz según `PRE(t−1)`, y
`LHPR` usa el `CH_j` **de hoy**. Con menos de 30 % de AU en ese horizonte la
tasa de profundización se reduce gradualmente hasta 0 con 0 % de AU. Como
`LHPR ≤ 1`, `PRE` nunca crece más rápido que `PRP`, así que no hace falta un
tope explícito.

### 7.6 Agua transpirable y transpiración real

Fracción del horizonte explorada por la raíz:

```
frac_1 = min(1, PRE / PFH_1)
frac_i = min(1, max(0, PRE − PFH_(i−1)) / (PFH_i − PFH_(i−1)))      i = 2..n
```

Agua transpirable por horizonte y total:

```
AT_i = max(0, CH_i − PMP_i) · kl · min(1, (CH_i − PMP_i) / (Um·(CC_i − PMP_i))) · frac_i
AT   = Σ AT_i
```

`kl` pondera el agua sobre PMP por la facilidad de extracción del suelo, y se
reduce linealmente por debajo del umbral `Um` (según textura). Transpiración:

```
TrR  = min(DemT, AT + Inf)                  transpiración real (tope: demanda o agua disponible)
TrRR = max(0, TrR − Inf)                    parte que se extrae de las reservas tras usar la infiltración del día
TrR_i = TrRR · AT_i / AT   si AT > 0, si no 0       reparto proporcional entre horizontes
```

### 7.7 Evaporación real del suelo (dos etapas)

Modelo de evaporación en dos etapas (Ritchie, 1972): una etapa 1 limitada por
energía (agua evaporable fácilmente, `AEF`) y una etapa 2 de tasa decreciente
(`AER`):

```
AEF  = min(DemE, max(0, CH_1 − (CC_1 − U·Rastrojo)) + max(0, Inf − TrR))
AER  = DemE − AEF
base = (Inf + CH_1 − TrR_1 − AEF − 0.5·PMP_1) / (CC_1 − U·Rastrojo − 0.5·PMP_1)
ER   = AEF + min(AER, AER · clamp01(base)⁴)
```

`U·Rastrojo` reduce el espesor de la capa de evaporación fácil según la
cobertura de rastrojo. La etapa 2 cae con la cuarta potencia a medida que el
horizonte superficial se aproxima a PMP. `clamp01(x) = min(max(x, 0), 1)`
acota la base al rango 0–1 antes de elevarla.

### 7.8 Drenaje interno y contenido hídrico final

Con el agua ya extraída por transpiración y evaporación, el excedente sobre CC
de cada horizonte drena a tasa `DR` hacia el horizonte inferior, junto con el
excedente por sobresaturación. Se resuelve en cascada del horizonte 1 al `n`,
cada uno dependiendo del anterior **el mismo día**:

```
CHv_1 = CH_1 − TrR_1 − ER              CHv_i = CH_i − TrR_i        (i = 2..n)
Dr_i  = max(0, (CHv_i − CC_i) · DR)

Cf_1  = CHv_1 − Dr_1 + max(0, Inf − TrRR − ER)
Me_1  = max(0, Cf_1 − Sat_1)
Cf_i  = CHv_i − Dr_i + Dr_(i−1) + Me_(i−1)         (i = 2..n)
Me_i  = max(0, Cf_i − Sat_i)

drenaje_profundo = Dr_n + Me_n                      (sale del sistema)
CH_i (día siguiente) = min(Sat_i, Cf_i)
```

El horizonte 1 recibe el excedente de infiltración directamente
(`Inf − TrRR − ER`), porque no tiene un horizonte superior; y su propio `Me_1`
no se resta de `Cf_1` el mismo día, sino que se trunca al día siguiente vía
`min(Sat_1, Cf_1)`.

### 7.9 Variables de estado diarias

Al cierre de cada día se calculan:

```
AU_mm_m = Σ CH_i − Σ PMP_i                         (por metro, y total)
AU_%_m  = AU_mm_m / (Σ CC_i − Σ PMP_i)             (fracción 0–1 por metro, y total)
sándwich_seco = "Si"  si (CH_4 − PMP_4)/(CC_4 − PMP_4) < 0.30,  si no "No"
```

El umbral del sándwich seco es estricto (`< 30 %`) y se evalúa sobre el
horizonte 4.

`AU` puede superar 100 % (fracción > 1): el 100 % corresponde a capacidad de
campo, y entre CC y saturación el suelo contiene más agua que esa referencia.

## 8. Paso 5 — Salidas

Son tres agregaciones sobre los Pasos 1 y 4, sin fórmulas nuevas.

**1. Eventos de lluvia pre-siembra.** Cantidad de días con `Pp ≥ 10 mm` en la
ventana `[siembra − 14 días, siembra + 7 días]`, extremos incluidos.

**2. Estado hídrico a la siembra.** `AU %` del primer metro, del segundo metro
y de todo el perfil (0–100), y la indicación de sándwich seco, tomados del
balance del día de siembra.

**3. Confort hídrico.** Porcentaje de la demanda transpirativa cubierta durante
el período crítico:

```
Confort = 100 · Σ TrR / Σ DemT        entre inicio y fin del período crítico (extremos incluidos)
```

Es `NA` si `Σ DemT = 0` en la ventana.

## 9. Procedimiento de simulación de un escenario

Un escenario fija estación, suelo, cultivo/cultivar, fecha de siembra, fecha
de monitoreo (inicio del balance) y condiciones iniciales. Se simula así:

1. **Fenología** (Paso 1) desde la siembra con el clima de la estación.
2. **Profundización radicular potencial** (Paso 2) y **curva de Kcb** (Paso 3).
3. **Ventana de clima.** El balance recorre todos los días de clima que recibe,
   así que antes se recorta a `[min(monitoreo, siembra − 14), madurez
   fisiológica]`. El inicio cubre el balance y además los 14 días previos a la
   siembra que necesita la salida 1; el fin es la madurez fisiológica, porque
   las salidas no requieren clima posterior. Si la ventana excede el rango de
   clima disponible, la simulación falla explícitamente en vez de truncarse en
   silencio.
4. **Balance hídrico diario** (Paso 4) desde la fecha de monitoreo.
5. **Salidas** (Paso 5).

**Fecha de monitoreo con día y mes.** Cuando el monitoreo se especifica solo
como día y mes (sin año), se resuelve respecto de cada año de siembra: si su
día del año es **posterior** al de la siembra, se asume que corresponde al año
calendario **anterior** al de la siembra; si no, al mismo año. La comparación
usa un año de referencia no bisiesto, solo para decidir el cruce de año. Las
fechas se construyen directamente desde (año, mes, día), de modo que "1 de
junio" es siempre 1 de junio, también en años bisiestos.

## 10. Agregación multianual

Un escenario de la plataforma web se simula contra **todos los años de clima
disponibles** de la estación (la misma fecha de siembra y monitoreo en cada
año). Cada año produce una fila de salidas; se resumen por variable con:

| Estadístico | Cálculo |
|---|---|
| Media | media aritmética |
| P20, P50, P80 | percentiles 20, 50 y 80 (`quantile`, tipo 7) |
| Desvío | desvío estándar muestral |
| IQR | rango intercuartílico (tipo 7) |

Se agregan: eventos de lluvia pre-siembra, `AU %` del primer metro, del
segundo metro y total, y confort hídrico. Los valores faltantes se excluyen. El
sándwich seco es categórico (Sí/No) y no se agrega; se informa año por año. Si
un año no puede simularse (por ejemplo, por exceder el rango de clima), se
omite del resumen y se informa la cantidad de años descartados.

## 11. Supuestos y limitaciones

- **Sin senescencia en Kcb.** `Kcb = kcb_max` se mantiene hasta el final de la
  serie. Es una decisión deliberada: la única salida que depende de `Kcb`
  (confort hídrico) se calcula hasta el fin del período crítico, que ocurre
  antes de que la caída de `Kcb` por senescencia importe. El balance sigue
  transpirando a `kcb_max` en los días posteriores a la madurez, que no se
  usan para ninguna salida.
- **Cultivo único por campaña**, barbecho libre de malezas entre monitoreo y
  siembra, rastrojo constante durante toda la simulación.
- **ENSO.** El método no incorpora el estado ENSO (Niño/Niña/Neutro, por
  ejemplo vía ONI de NOAA) en ningún cálculo.
- **Una estación por escenario.** Cada simulación usa el clima de una única
  estación; un lote de simulaciones tiene una estación.
- **Clima.** El relleno de huecos (3.4) solo cubre huecos internos de la
  serie; los días futuros o previos al inicio del registro quedan sin dato.
- **Suelos.** El método es tan bueno como el catálogo de suelos que se le
  provea (horizontes, PMP/CC/Sat, `CN`, `U`, `DR`, `kl`, `Um`).
- **Fotoperíodo fuera de Argentina.** La fórmula de 3.2 está acotada
  asimétricamente y puede devolver `NaN` para latitudes extremas (|lat| > ≈ 55°).

## 12. Tablas de parámetros

Valores por defecto del catálogo de cultivos. Temperaturas en °C, UT en °C·día,
fotoperíodos en horas, `pr` en cm/°C y `pr_s_e` en m.

### Parámetros comunes (los tres cultivos)

| Parámetro | Valor |
|---|---|
| `kcb_ini` | 0.15 |
| `kcb_max` | 1.10 |
| `pr_s_e` | 0.2 |

### Trigo

| Parámetro | Valor |
|---|---|
| `tb_a` | 0 |
| `ut_s_e` | 150 |
| `ut_e_fkcbini` | 300 |
| `ut_e_ikcbmax` | 1000 |
| `ut_e_et` | 400 |
| `ut_et_ipc` | 100 |
| `ut_et_z71` | 700 |
| `ut_et_fpc` | 800 |
| `ut_fpc_mf` | 400 |
| `pr` / `tb_c` | 0.13 / 0 |

| Cultivar | `rcf` |
|---|---|
| intermedio-corto | 0.70 |
| intermedio-largo | 0.85 |

### Maíz

| Parámetro | Valor |
|---|---|
| `tb_a` / `tb_b` | 10 / 8 |
| `ut_s_e` | 80 |
| `ut_e_fkcbini` | 120 |
| `ut_e_ikcbmax` | 560 |
| `pr` / `tb_c` | 0.20 / 8 |

| Cultivar | `ut_e_r2` | `ut_e_ipc` | `ut_e_fpc` | `ut_r2_mf` |
|---|---|---|---|---|
| templado-corto | 950 | 500 | 1050 | 550 |
| templado-intermedio | 1050 | 600 | 1150 | 650 |
| tropical-intermedio | 1150 | 700 | 1250 | 700 |

### Soja

| Parámetro | Valor |
|---|---|
| `tb_a` / `tb_b` / `to_a` | 10 / 7 / 27 |
| `ut_s_e` | 100 |
| `ut_e_fkcbini` | 180 |
| `ut_e_ikcbmax` | 840 |
| `ut_e_r1` | 400 |
| `ut_r1_r5` | 300 |
| `ut_r1_ipc` | 120 |
| `ut_r5_fpc` | 200 |
| `ut_r5_mf` | 800 |
| `pr` / `tb_c` | 0.20 / 8 |

| Cultivar | `fpu_e_r1` | `fpu_r1_mf` |
|---|---|---|
| GM 3C | 13.5 | 13.0 |
| GM 4L | 13.0 | 12.5 |
| GM 6C | 12.5 | 12.0 |

## 13. Referencias

- Allen, R. G., Pereira, L. S., Raes, D., & Smith, M. (1998). *Crop
  evapotranspiration: Guidelines for computing crop water requirements.* FAO
  Irrigation and Drainage Paper 56. FAO, Roma.
- Boote, K. J., Jones, J. W., Hoogenboom, G., & Pickering, N. B. (1998). The
  CROPGRO model for grain legumes. En Tsuji, G. Y., Hoogenboom, G. & Thornton,
  P. K. (Eds.), *Understanding Options for Agricultural Production* (pp.
  99–128). Springer, Dordrecht.
- Forsythe, W. C., Rykiel, E. J., Stahl, R. S., Wu, H., & Schoolfield, R. M.
  (1995). A model comparison for daylength as a function of latitude and day
  of year. *Ecological Modelling*, 80, 87–95.
- Hargreaves, G. H., & Samani, Z. A. (1985). Reference crop evapotranspiration
  from temperature. *Applied Engineering in Agriculture*, 1(2), 96–99.
- Hawkins, R. H., Ward, T. J., Woodward, D. E., & Van Mullem, J. A. (2009).
  *Curve Number Hydrology: State of the Practice.* ASCE, Reston, VA.
- Jones, J. W., Hoogenboom, G., Porter, C. H., Boote, K. J., Batchelor, W. D.,
  Hunt, L. A., Wilkens, P. W., Singh, U., Gijsman, A. J., & Ritchie, J. T.
  (2003). The DSSAT cropping system model. *European Journal of Agronomy*, 18,
  235–265.
- NOAA Climate Prediction Center. *Oceanic Niño Index (ONI).*
  https://origin.cpc.ncep.noaa.gov/products/analysis_monitoring/ensostuff/ONI_v5.php
- Richardson, C. W. (1981). Stochastic simulation of daily precipitation,
  temperature, and solar radiation. *Water Resources Research*, 17(1), 182–190.
- Ritchie, J. T. (1972). Model for predicting evaporation from a row crop with
  incomplete cover. *Water Resources Research*, 8(5), 1204–1213.
- Ritchie, J. T., & Otter, S. (1985). Description and performance of
  CERES-Wheat: A user-oriented wheat yield model. En *ARS Wheat Yield
  Project*, ARS-38 (pp. 159–175). USDA-ARS, Springfield.
- USDA Soil Conservation Service (1972). *National Engineering Handbook,
  Section 4: Hydrology.* USDA-SCS, Washington, DC.
