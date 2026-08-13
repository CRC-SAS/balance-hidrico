# Un método operativo de simulación del balance hídrico de cultivos extensivos para la gestión del riesgo climático en la Argentina

**Guillermo García¹** (ggarcia@crea.org.ar)
**Jorge Luis Mercau¹** (jorgemercau@gmail.com)
**Santiago Rovere²** (srovere@gmail.com)

> ¹ Autores del método (definición agronómica e hidrológica).
> ² Autor de la implementación de referencia (paquete R `balancehidrico`).

---

## Resumen

Se presenta un método de simulación del balance hídrico de cultivos extensivos
concebido como motor de cálculo de una herramienta de apoyo a la decisión
agrícola impulsada por el Centro Regional del Clima para el Sur de América del
Sur (CRC-SAS). El método responde a dos preguntas operativas concretas que un
productor o asesor se formula entre el 1° de marzo y la fecha planeada de
siembra: cuánta agua habrá disponible en el perfil al momento de sembrar, y qué
nivel de confort hídrico cabe esperar durante el período crítico de definición
del rendimiento. La formulación se organiza en cinco pasos encadenados:
(i) fenología por acumulación de unidades térmicas con sensibilidad al
fotoperíodo específica por cultivo; (ii) profundización radicular potencial;
(iii) curva de coeficiente basal de cultivo (Kcb); (iv) balance hídrico diario
sobre ocho horizontes de suelo, resuelto en la secuencia
profundización–lluvia–escorrentía–infiltración–transpiración–evaporación–drenaje;
y (v) tres salidas agregadas de interpretación directa. El alcance actual cubre
trigo, maíz y soja en la Argentina, con dos o tres cultivares por especie y dos
o tres suelos por localidad. El método se implementó como un paquete R de
código abierto, `balancehidrico`, con una arquitectura de una función pura por
paso y una batería de más de 1400 pruebas automatizadas que incluye validación
numérica exacta (tolerancia 1×10⁻⁹) contra un escenario real de trigo con
428 días de simulación diaria. Esa implementación de referencia es en sí misma
un resultado central de este trabajo: traduce una especificación agronómica en
una herramienta reproducible, extensible y verificable.

**Palabras clave:** balance hídrico de suelos; fenología; unidades térmicas;
coeficiente de cultivo dual; curva número; riesgo climático agrícola; trigo;
maíz; soja.

---

## 1. Introducción

La variabilidad interanual de las precipitaciones es, en la región pampeana y en
buena parte del sur de Sudamérica, el principal determinante exógeno del
resultado productivo de los cultivos extensivos de secano. A diferencia de otras
fuentes de riesgo, el riesgo climático no se elimina: se gestiona. Y se gestiona
fundamentalmente en el momento de la decisión de siembra, cuando el productor
todavía puede elegir especie, cultivar, fecha y densidad, y todavía puede decidir
no sembrar. Esa ventana de decisión es el objeto de la herramienta cuyo motor de
cálculo se describe en este trabajo.

La información que se necesita en esa ventana no es una predicción de
rendimiento, sino algo más modesto y más accionable: una caracterización del
estado hídrico del perfil con el que se va a arrancar, y una estimación de si ese
punto de partida, combinado con la climatología del sitio, alcanza para atravesar
sin estrés el período en que el cultivo define su número de granos. El agua
almacenada en el perfil a la siembra es, en ambientes semiáridos y subhúmedos, un
recurso tan determinante como la lluvia posterior, con la ventaja de que a la
fecha de la decisión ya está parcialmente determinado y es por lo tanto
conocible.

El método presentado acá fue definido por CRC-SAS con ese propósito acotado y
explícito. La herramienta admite consultas desde el 1° de marzo hasta la fecha
de siembra planeada, para trigo, maíz o soja. Supone un barbecho libre de
malezas entre la fecha de consulta y la siembra, y supone que el cultivo
simulado es siempre el primero de la campaña; la simulación corre desde la fecha
de consulta hasta la madurez fisiológica. A partir de esa corrida, la
herramienta devuelve tres productos: el número de eventos de lluvia
significativos en la ventana operativa de siembra, el contenido hídrico del
perfil al momento de sembrar desagregado por metro de profundidad, y un índice
de confort hídrico durante el período crítico.

El diseño está deliberadamente subordinado a esas tres salidas, decisión que
explica varias de las simplificaciones descriptas más adelante: el método no
pretende ser un modelo de cultivo de propósito general. No simula biomasa,
partición a órganos, rendimiento ni nitrógeno. Simula el agua del suelo con el
detalle necesario para responder dos preguntas, y donde un mecanismo adicional
no cambia esas respuestas, ese mecanismo se omite. La contrapartida es un método
computacionalmente liviano, de pocos parámetros y agronómicamente
interpretables, que puede correrse sobre climatologías de más de treinta años
para cientos de combinaciones de estación, suelo, cultivo y cultivar sin
infraestructura de cómputo especializada.

Un segundo criterio, igualmente deliberado, es la parametrización por clases en
lugar de por mediciones. El usuario no ingresa un contenido volumétrico medido a
campo ni un porcentaje de cobertura de rastrojo relevado con transecta: elige una
de cuatro clases de humedad inicial y una de tres clases de cobertura, por
comparación subjetiva con situaciones extremas descriptas. El criterio reconoce
que la información disponible al momento de la decisión es cualitativa, y que un
modelo que exija precisión que el usuario no tiene termina alimentado con
números inventados.

Este trabajo describe el método en sí. Las secciones 2 y 3 lo sitúan en su marco
conceptual y lo desarrollan paso por paso; la sección 4 describe brevemente la
implementación de referencia en R y su validación numérica; la sección 5 discute
las decisiones de diseño no triviales, las discrepancias que surgieron durante
la formalización del método y las limitaciones conocidas.

---

## 2. Antecedentes y marco conceptual

El método no propone mecanismos biofísicos nuevos. Su aporte está en la
selección, simplificación y articulación de un conjunto de formulaciones
consolidadas, elegidas por su parsimonia paramétrica y por su adecuación al
alcance operativo descripto. Esta sección identifica cada pilar y lo conecta con
la parte del método que lo utiliza.

### 2.1 Fenología por tiempo térmico

La representación del desarrollo fenológico como acumulación de unidades
térmicas por encima de una temperatura base es el núcleo de la familia de
modelos DSSAT (Jones et al., 2003) y, en particular, de los motores CERES para
gramíneas y CROPGRO para leguminosas. El método CRC-SAS adopta explícitamente
ese enfoque: cada etapa se define por un requerimiento térmico en °C·día que
debe acumularse desde un hito anterior, y el incremento diario es la diferencia
entre la temperatura media del día y una temperatura base específica del cultivo
y de la etapa.

La estructura de etapas y la modulación fotoperiódica de trigo siguen el esquema
de CERES-Wheat (Ritchie & Otter, 1985): temperatura base por etapa, umbrales
térmicos entre hitos y sensibilidad al fotoperíodo restringida a una ventana
vegetativa temprana, que en trigo se cierra con la espiguilla terminal. La
formulación de soja sigue en cambio el esquema de CROPGRO-Soybean (Boote et al.,
1998), donde el fotoperíodo actúa como umbral de día corto con penalización
proporcional al exceso, y donde existe además una temperatura óptima por encima
de la cual la tasa de desarrollo deja de aumentar. Maíz, coherentemente con
CERES-Maize, se trata como insensible al fotoperíodo en el rango de latitudes de
interés.

Cabe aclarar que el método no usa DSSAT como motor de cálculo: reimplementa el
principio de acumulación térmica con un conjunto reducido de parámetros propios,
calibrados para los cultivares de uso corriente en la región.

### 2.2 Coeficiente de cultivo dual

La partición de la evapotranspiración en un componente transpirativo del
cultivo y un componente evaporativo del suelo sigue el enfoque de coeficiente de
cultivo dual de FAO-56 (Allen et al., 1998), en el que la evapotranspiración del
cultivo se descompone como `ETc = (Kcb + Ke) · ETo`. El método CRC-SAS adopta la
lógica de la descomposición pero no el coeficiente de evaporación `Ke` tabulado
de FAO-56: la demanda evaporativa se deriva de la fracción de suelo no cubierta
por el canopeo, aproximada por `1 - Kcb`, y se modula por la cobertura de
rastrojo. La curva de Kcb en función del desarrollo del canopeo, con un valor
inicial bajo, una rampa de crecimiento y una meseta que puede superar la unidad
cuando la cobertura alcanza el 80-85 % y el índice de área foliar ronda 3,0-3,5,
es la de FAO-56.

La evapotranspiración de referencia `ETo` es un dato de entrada de la base
climática y no se calcula dentro del método en sí. Esto desacopla al método
de la elección del estimador de `ETo` —Penman-Monteith de FAO-56 donde hay
datos completos, Hargreaves-Samani (Hargreaves & Samani, 1985) donde solo
hay temperaturas— y permite que la serie de `ETo` sea homogénea con la que
el CRC-SAS ya produce para otros fines. La implementación de referencia
incluye, además, una utilidad opcional que estima `ETo` con Hargreaves-Samani
a partir de temperaturas diarias para los casos en que la base climática no
la trae ya calculada; sigue sin ser parte del cómputo del balance en sí,
solo un paso de preparación de datos que puede usarse antes.

### 2.3 Escorrentía por número de curva

La partición de la lluvia diaria entre escorrentía superficial e infiltración
efectiva usa el método del número de curva del Servicio de Conservación de Suelos
(USDA Soil Conservation Service, 1972), que relaciona la escorrentía con la
lluvia acumulada del evento y una retención potencial máxima derivada de un único
parámetro `CN`, síntesis del grupo hidrológico de suelo, el uso y la condición de
superficie. El método CRC-SAS introduce una modificación relevante: reemplaza el
coeficiente fijo de abstracción inicial `λ = 0,2` de la formulación clásica por
una abstracción inicial dinámica, función del estado de humedad del horizonte
superficial. Se apoya en la crítica extensamente documentada al valor fijo de `λ`
y en las propuestas de tratarlo como parámetro variable (Hawkins et al., 2009), y
reintroduce, dentro de un esquema de balance diario, la dependencia respecto de
la condición de humedad antecedente que el método clásico maneja de forma
discreta mediante clases AMC.

### 2.4 Evaporación del suelo en dos etapas

La evaporación desde el suelo desnudo o parcialmente cubierto se representa con
el modelo de dos etapas de Ritchie (1972): una primera etapa limitada por la
energía disponible, en la que el suelo evapora a la tasa potencial mientras haya
agua fácilmente evaporable en la capa superficial, y una segunda etapa limitada
por la conductividad del suelo, en la que la tasa cae a medida que el frente de
desecamiento se profundiza. La cantidad de agua evaporable en la primera etapa
es el parámetro `U` del suelo, que en el método CRC-SAS se reduce
proporcionalmente a la cobertura de rastrojo, y la caída de la segunda etapa se
modela con una función potencial del grado de agotamiento del horizonte
superficial.

### 2.5 Fotoperíodo con corrección de crepúsculo civil

La duración del día se calcula geométricamente a partir de la latitud y la
declinación solar. El método adopta la variante que incorpora la corrección por
crepúsculo civil, es decir, que define el día efectivo desde el punto de vista
fotoperiódico como el intervalo en que el centro del disco solar está por encima
de 6° bajo el horizonte, en lugar de exactamente en el horizonte. Esta variante
es la recomendada para aplicaciones fenológicas, dado que la respuesta
fotoperiódica de las plantas es sensible a irradiancias muy bajas, y está
sistematizada en la comparación de modelos de duración del día de Forsythe et
al. (1995). Como se discute en la sección 5, la elección entre la formulación
con y sin corrección de crepúsculo no es cosmética: en trigo desplaza hitos
fenológicos hasta dieciséis días.

### 2.6 Contexto ENSO

La caracterización de cada campaña según la fase del El Niño-Oscilación del Sur
se realiza mediante el Oceanic Niño Index (NOAA Climate Prediction Center), que
clasifica trimestres móviles en Niño, Niña o Neutro según la anomalía de
temperatura superficial del mar en la región Niño 3.4. En la versión actual del
método el ENSO está descripto como dato de entrada y como eje previsto de
segmentación de resultados, pero todavía no interviene en ninguna fórmula del
balance; se detalla este punto en la sección 5.4.

---

## 3. Descripción del método

El método se organiza en cinco pasos que se ejecutan en secuencia. Los tres
primeros producen series diarias que dependen únicamente del clima y de los
parámetros del cultivo, y son por lo tanto independientes del suelo y de la
condición hídrica inicial. El cuarto integra esas series con el suelo y con el
estado hídrico inicial para resolver el balance día a día. El quinto agrega los
resultados en las tres salidas de la herramienta. La secuencia completa se
resume así:

```
Fenología  →  Profundización radicular potencial  →  Curva de Kcb  →
Balance hídrico diario  →  Salidas
```

El desacople entre los pasos 1-3 y el paso 4 no es solo una conveniencia de
implementación: refleja la estructura conceptual del método, en el que el
desarrollo del cultivo se supone determinado por la temperatura y el fotoperíodo
y no se retroalimenta del estado hídrico. La única excepción es la
profundización radicular, cuya curva potencial (paso 2) se corrige día a día
dentro del balance según la disponibilidad de agua del horizonte hacia el cual
avanza el frente de raíces (sección 3.4.3).

### 3.1 Paso 1 — Fenología

#### 3.1.1 Marco común

Cada etapa fenológica queda definida por una cantidad de unidades térmicas (UT,
°C·día) que deben acumularse desde un hito anterior. El incremento diario básico
es

```
ΔUT = max(0, Tm - Tb)
```

donde `Tm` es la temperatura media diaria y `Tb` la temperatura base del
cultivo y de la etapa. La temperatura media se toma de la base climática si está
disponible; en su defecto se calcula como `(Tx + Tn)/2`.

La fecha de ocurrencia de un hito es la primera fecha en que la serie acumulada
alcanza el umbral correspondiente. Como los incrementos diarios nunca son
negativos, la serie acumulada es monótona no decreciente y esa primera fecha es
única y está bien definida.

El fotoperíodo `Fp` no es un dato de la base climática sino que se deriva de la
latitud de la estación y del día del año:

```
declinación = 0.4093 · sin(0.0172 · (día_del_año - 82.2))        [radianes]
lat_rad     = latitud · 0.01745
x           = (-sin(lat_rad)·sin(declinación) - 0.1047) / (cos(lat_rad)·cos(declinación))
x           = max(x, -0.87)
Fp          = 7.639 · acos(x)                                     [horas]
```

El término `0.1047 = sin(6°)` es la corrección por crepúsculo civil descripta en
la sección 2.5. El recorte inferior del argumento del arco-coseno en `-0.87`
acota la duración máxima del día en el rango de latitudes de interés.

Cada cultivo modula ese esquema común de forma distinta, y esas diferencias no
son parametrizaciones de una misma fórmula sino mecanismos estructuralmente
diferentes.

#### 3.1.2 Trigo

El trigo responde al fotoperíodo como especie de día largo, y lo hace únicamente
entre emergencia (E) y espiguilla terminal (ET); a partir de ese momento es
insensible. El factor fotoperiódico es una función cuadrática centrada en 20
horas, modulada por la respuesta del cultivar al fotoperíodo (`RCF`):

```
factor_fp = max(0, 1 - ((20 - min(20, Fp))² · 0.01 · RCF))
ΔUT_ajustada = max(0, Tm - Tb) · factor_fp
```

El `min(20, Fp)` es esencial: sin él, la simetría de la parábola penalizaría
también fotoperíodos mayores a 20 horas, cuando el comportamiento buscado es que
por encima de ese umbral el efecto sea nulo y el factor valga exactamente 1. La
interpretación agronómica es directa: días cortos retrasan la inducción floral,
y ese retraso es más marcado en cultivares de mayor respuesta fotoperiódica. El
`RCF` toma el valor 0,7 en cultivares intermedio-cortos y 0,85 en
intermedio-largos.

La secuencia completa de hitos usa temperatura base 0 °C durante todo el ciclo:

| Hito | Umbral (UT desde el hito anterior) | Ajuste por Fp |
|---|---|---|
| Emergencia (E) | Siembra + 150 | No |
| Fin de Kcb inicial | E + 300 (≈3 hojas, filocrono 100 °C/hoja) | No |
| Inicio de Kcb máximo | E + 1000 (≈10 hojas) | No |
| Espiguilla terminal (ET) | E + 400 | **Sí** |
| Inicio de período crítico | ET + 100 | No |
| Z71 (cuaje de granos) | ET + 700 | No |
| Fin de período crítico | ET + 800 | No |
| Madurez fisiológica | Fin de período crítico + 400 | No |

Un punto de definición que resultó crítico durante la formalización: Z71 y el
fin del período crítico son **dos hitos distintos**, ambos referidos a ET, con
umbrales de 700 y 800 °C·día respectivamente. Tratarlos como un mismo hito
—error presente en una versión temprana de la documentación fuente— desplaza en
100 °C·día tanto el fin del período crítico como, en cascada, la madurez
fisiológica. Todos los hitos posteriores a ET se resuelven sobre una única serie
acumulada iniciada en ET, que no se reinicia en cada hito.

#### 3.1.3 Maíz

El maíz se trata como insensible al fotoperíodo. La temperatura base cambia de
10 °C en la fase siembra-emergencia a 8 °C de emergencia en adelante. R2, el
cuaje de granos, cumple simultáneamente el rol que en trigo cumplen ET y Z71:
no hay una etapa reproductiva intermedia.

Todos los hitos posteriores a la emergencia se resuelven sobre una única serie
acumulada con base 8 °C, cada uno contra su propio umbral absoluto tomado de la
tabla de parámetros del cultivar. Los umbrales de inicio y fin de período
crítico, que conceptualmente se definen como `R2 - 450` y `R2 + 100`, vienen
precalculados como valores absolutos.

| Cultivar | UT E→R2 | UT E→inicio PC | UT E→fin PC | UT R2→MF |
|---|---|---|---|---|
| templado-corto | 950 | 500 | 1050 | 550 |
| templado-intermedio | 1050 | 600 | 1150 | 650 |
| tropical-intermedio | 1150 | 700 | 1250 | 700 |

Los umbrales de fin de Kcb inicial (120 °C·día desde emergencia) y de inicio de
Kcb máximo (560) son comunes a los tres cultivares: la diferencia entre
cultivares está concentrada en los requerimientos térmicos hasta el cuaje y en
la duración del llenado.

#### 3.1.4 Soja

La soja responde al fotoperíodo como especie de día corto durante todo el ciclo,
desde emergencia hasta madurez fisiológica, y agrega dos mecanismos que la
distinguen de trigo y maíz.

El primero es una **temperatura óptima** `To = 27 °C`: el incremento diario usa
`min(Tm, To) - Tb` en lugar de `Tm - Tb`, de modo que por encima de 27 °C la
acumulación térmica deja de aumentar. Este mecanismo aplica en todas las fases,
incluida siembra-emergencia.

El segundo es un **umbral de fotoperíodo con penalización lineal**, distinto en
naturaleza del factor cuadrático continuo del trigo:

```
factor_fpu = min(1, max(0, 1 - max(0, Fp - FpU) · 0.3))
```

Por debajo del umbral `FpU` no hay penalización alguna; por encima, la
acumulación diaria se reduce a razón de 0,3 por hora de exceso, de modo que un
exceso de algo más de tres horas anula por completo el avance fenológico del
día. El umbral depende del cultivar y de la etapa: es más alto en la fase
emergencia-R1 que en la fase R1-madurez, y más bajo en cultivares de grupo de
madurez más largo.

| Cultivar | FpU E→R1 (h) | FpU R1→MF (h) |
|---|---|---|
| GM 3C | 13,5 | 13,0 |
| GM 4L | 13,0 | 12,5 |
| GM 6C | 12,5 | 12,0 |

La secuencia de hitos, con temperaturas base de 10 °C en siembra-emergencia y
7 °C de emergencia en adelante, es:

| Hito | Umbral | Umbral de Fp aplicado |
|---|---|---|
| Emergencia (E) | Siembra + 100 | — |
| Fin de Kcb inicial | E + 180 (≈3 nudos) | sin penalización |
| Inicio de Kcb máximo | E + 840 (≈14 nudos) | sin penalización |
| R1 | E + 400 | `FpU` E→R1 |
| Inicio de período crítico | R1 + 120 | `FpU` R1→MF |
| R5 (cuaje de granos) | R1 + 300 | `FpU` R1→MF |
| Fin de período crítico | R1 + 300 + 200 | `FpU` R1→MF |
| Madurez fisiológica | R1 + 300 + 800 | `FpU` R1→MF |

El requerimiento térmico R1→R5 es una constante fija de 300 °C·día, invariante
respecto del cultivar. Esto vuelve numéricamente equivalentes las definiciones
`iPC = R1 + 120` y `iPC = R5 - 180`; se adopta la primera como canónica.

Obsérvese que los dos hitos que gobiernan la curva de Kcb —fin de Kcb inicial e
inicio de Kcb máximo— se resuelven en los tres cultivos sobre la serie **sin**
penalización fotoperiódica, mientras que los hitos reproductivos usan la serie
penalizada. La justificación se desarrolla en la sección 3.3.

### 3.2 Paso 2 — Profundización radicular potencial

La curva potencial de profundidad radicular es común a los tres cultivos en su
estructura y se define en tres tramos:

1. Entre siembra y emergencia, profundidad constante de 0,20 m.
2. Desde emergencia, crecimiento lineal con la acumulación térmica:

```
profundidad(t) = 0.20 + (pr · UT_acumulada_raíz(t)) / 100      [m]
```

donde `pr` es la tasa de profundización en cm/°C·día (0,13 en trigo; 0,20 en
maíz y soja) y `UT_acumulada_raíz` se acumula con una temperatura base propia
`Tb_raíz` (0 °C en trigo; 8 °C en maíz y soja), independiente de las series
térmicas de la fenología.

3. Congelamiento en el hito de cuaje de granos: Z71 en trigo, R2 en maíz, R5 en
soja. A partir de ese momento la profundidad no crece más.

Sobre esa curva se aplica un segundo tope, la profundidad máxima del perfil de
suelo: la raíz crece hasta el cuaje de granos **o** hasta el fondo del perfil,
lo que ocurra primero.

El hecho de que la acumulación térmica radicular tenga su propia temperatura
base y dependa del cultivo solamente a través de dos fechas —emergencia y cuaje—
hace que este paso sea agronómicamente uniforme entre especies: la
diferenciación queda enteramente contenida en los parámetros.

Es importante subrayar que esta es la curva **potencial**. La limitación por
sequía —el hecho de que un frente radicular no penetra un horizonte seco a la
misma velocidad con que penetra uno húmedo— se resuelve dentro del balance
diario, porque requiere conocer el contenido hídrico del horizonte de destino en
cada día (sección 3.4.3).

### 3.3 Paso 3 — Curva de Kcb

El coeficiente basal de cultivo sigue una rampa lineal de tres tramos en función
de las unidades térmicas acumuladas desde la emergencia:

```
Kcb = Kcb_ini                                              si UT ≤ UT_finKcbIni
Kcb = Kcb_ini + (Kcb_max - Kcb_ini) ·
      (UT - UT_finKcbIni) / (UT_iniKcbMax - UT_finKcbIni)   si UT_finKcbIni < UT < UT_iniKcbMax
Kcb = Kcb_max                                              si UT ≥ UT_iniKcbMax
```

Los valores extremos son comunes a los tres cultivos: `Kcb_ini = 0,15` y
`Kcb_max = 1,10`. Que el máximo supere la unidad es consistente con FAO-56 para
cultivos con cobertura de canopeo del orden del 80-85 % e índice de área foliar
de 3,0-3,5 (Allen et al., 1998).

Dos decisiones de este paso merecen destacarse. La primera es que la serie de UT
que gobierna la rampa es la serie **simple**, sin ajuste fotoperiódico. La
justificación agronómica es que la velocidad de expansión del canopeo —que es lo
que el Kcb representa— responde a la temperatura y no comparte la respuesta
fotoperiódica del desarrollo reproductivo. Un cultivar de trigo de alta
respuesta fotoperiódica sembrado en un ambiente de días cortos retrasa su
espigazón, pero no retrasa proporcionalmente el cierre del surco.

La segunda es que `Kcb_max` se mantiene **constante** desde el inicio de la
meseta hasta el final de la simulación: no hay rampa descendente de senescencia,
a diferencia del esquema estándar de FAO-56. Esta es una simplificación
deliberada y no un vacío de especificación; su justificación se desarrolla en la
sección 5.1.

![Fenología y curva de Kcb del escenario de referencia (trigo, cultivar intermedio-largo, estación 87480, siembra 1983-05-30). Los hitos fenológicos (líneas punteadas) determinan los tramos de la rampa de Kcb; la banda sombreada marca el período crítico sobre el que se calcula el confort hídrico (sección 3.5).](figuras/fig1_fenologia_kcb.png)

**Figura 1.** Fenología y curva de Kcb del escenario de referencia usado para
la validación numérica (sección 4.3).

### 3.4 Paso 4 — Balance hídrico diario

Este es el núcleo del método. Simula día a día el contenido de agua en ocho
horizontes de suelo a partir de la oferta —agua inicial, lluvia diaria, capacidad
de extracción de las raíces— y de la demanda —evapotranspiración de referencia
ponderada por Kcb—. El cálculo es estrictamente secuencial: el estado de cada día
depende del estado del día anterior.

La secuencia intradiaria es fija y su orden es parte de la definición del método:

```
agua en cada horizonte al final del día previo
  → profundiza la raíz
  → llueve
  → escurre
  → infiltra
  → transpira
  → evapora
  → drena
  → agua al final del día
```

#### 3.4.1 Representación del suelo

Cada suelo se describe con hasta ocho horizontes de límites inferiores en 0,2;
0,4; 0,6; 0,9; 1,2; 1,5; 1,8 y 2,1 m —un suelo somero puede tener menos—, cada
uno caracterizado por su contenido volumétrico fraccional en punto de marchitez
permanente (PMP), capacidad de campo (CC) y saturación (Sat). Las fórmulas del
balance operan sobre capacidades expresadas en milímetros por horizonte:

```
espesor_i = PFH_i - PFH_(i-1)          (PFH_0 = 0)
PMP_i [mm] = pmp_frac_i · espesor_i · 1000
CC_i  [mm] = cc_frac_i  · espesor_i · 1000
Sat_i [mm] = sat_frac_i · espesor_i · 1000
```

A esos perfiles se agregan cinco escalares por serie de suelo: el número de
curva `CN`, la facilidad de extracción radicular `kl`, el umbral textural de
reducción de esa extracción `Um`, el agua evaporable en primera etapa `U` (mm) y
el factor de drenaje `DR`. Los valores de `kl` y `Um` son directamente
interpretables en términos de textura y estructura:

| Parámetro | Valor | Condición |
|---|---|---|
| `kl` | 0,10 | suelos en general |
| `kl` | 0,08 | argiudol vértico / thapto nátrico |
| `kl` | 0,05 | vertisol |
| `Um` | 0,30 | suelos arenosos |
| `Um` | 0,50 | suelos francos |
| `Um` | 0,70 | suelos vérticos |

La lectura agronómica del par `kl`/`Um` es que un suelo vértico tiene, para un
mismo contenido de agua útil, una extracción más lenta (menor `kl`) y comienza a
restringir esa extracción con un grado de agotamiento mucho menor (mayor `Um`).

#### 3.4.2 Condición inicial

El contenido hídrico del día 1 se deriva de la clase de humedad elegida por el
usuario:

```
CH_i = (CC_i - PMP_i) · AU_i + PMP_i
```

donde `AU_i` es la fracción de agua útil correspondiente a la clase: 0,10
(Seco), 0,35 (Moderadamente Seco), 0,65 (Moderadamente Húmedo) o 0,90 (Húmedo).
La clase se elige de forma independiente para el primer metro (horizontes 1 a 4,
0-0,9 m) y para el segundo (horizontes 5 a 8, 0,9-2,1 m).

Se contempla además la condición de **sándwich seco**, una situación
frecuente en la práctica en la que una capa intermedia permanece seca por debajo
de un horizonte superficial rehumedecido por lluvias recientes. Cuando el usuario
declara su presencia, el horizonte 4 (0,6-0,9 m) se fija en 10 % de agua útil
independientemente de la clase declarada para el primer metro; los horizontes 1 a
3 conservan la clase general. La detección de esta condición durante la
simulación se describe en la sección 3.4.7.

#### 3.4.3 Profundización radicular efectiva

La curva potencial del paso 2 (`PRP`) se corrige día a día en función de la
disponibilidad hídrica del horizonte hacia el cual avanza el frente radicular.
Se define un coeficiente de limitación hídrica de la profundización (`LHPR`):

```
ΔPRP = PRP(t) - PRP(t-1)                              si PRP(t) > 0.2, si no 0

LHPR = 1                                              si PRE(t-1) < PFH_1
LHPR = min(1, (CH_j - PMP_j) / (0.3 · (CC_j - PMP_j)))  si PFH_(j-1) ≤ PRE(t-1) < PFH_j,  2 ≤ j ≤ 8
LHPR = 0                                              si PRE(t-1) ≥ PFH_8

PRE(t) = 0                              si PRP(t) < 0.2
PRE(t) = 0.2                            si PRP(t) = 0.2
PRE(t) = PRE(t-1) + ΔPRP · LHPR         en otro caso
```

El horizonte `j` es el horizonte específico hacia el que avanza la raíz según su
posición del día anterior, no un promedio del perfil; y el contenido hídrico
`CH_j` que se evalúa es el de **hoy**, ya actualizado. El umbral de 0,3 en el
denominador expresa que la profundización se reduce gradualmente por debajo del
30 % de agua útil del horizonte de destino, hasta anularse en el punto de
marchitez. Es el mecanismo por el cual un año seco produce un cultivo con menor
exploración del perfil, con la consecuencia acumulativa de que ese cultivo será
además más vulnerable a la sequía que siga.

#### 3.4.4 Escorrentía e infiltración

La partición de la lluvia diaria usa el método del número de curva con
abstracción inicial dinámica:

```
Absi = 0.15 · (Sat_1 - max(CH_1, PMP_1)) / (Sat_1 - PMP_1)
AtM  = 254 · (100/CN - 1)
Esc  = max(0, Pp - Absi·AtM)² / (Pp + AtM·(1 - Absi))
Inf  = Pp - Esc
```

`AtM` es la retención potencial máxima derivada del número de curva y `Absi` es
el coeficiente de abstracción inicial, que varía entre 0 —horizonte superficial
saturado, ninguna abstracción inicial, toda la lluvia por encima del umbral
escurre— y 0,15 —horizonte superficial en punto de marchitez, abstracción
inicial máxima—. Como se señaló en la sección 2.3, esto sustituye el `λ = 0,2`
fijo del método clásico por una función continua del estado de humedad
antecedente.

#### 3.4.5 Demanda, agua transpirable y transpiración real

La demanda diaria se parte en un componente transpirativo y uno evaporativo:

```
DemT = Eto · Kcb
DemE = max(0, Eto · max(0, 1 - Kcb) · Rastrojo)
```

El factor `Rastrojo` vale 1 para cobertura Baja (0-20 %), 0,8 para Moderada
(30-50 %) y 0,5 para Muy Alta (80-100 %), y se mantiene fijo durante toda la
simulación. El `max(0, 1 - Kcb)` interno no es redundante: dado que
`Kcb_max = 1,10`, el término `1 - Kcb` es efectivamente negativo durante la
meseta.

El agua transpirable se calcula por horizonte, ponderando por la fracción del
horizonte efectivamente explorada por las raíces:

```
frac_explorada_1 = min(1, PRE / PFH_1)
frac_explorada_i = min(1, max(0, PRE - PFH_(i-1)) / (PFH_i - PFH_(i-1)))     i = 2..8

AT_i = max(0, CH_i - PMP_i) · kl ·
       min(1, (CH_i - PMP_i) / (Um · (CC_i - PMP_i))) · frac_explorada_i
AT   = Σ AT_i
```

El agua transpirable de un horizonte es entonces el agua por encima del punto de
marchitez, ponderada por la facilidad de extracción `kl`, reducida linealmente
cuando el contenido cae por debajo del umbral textural `Um`, y limitada a la
porción del horizonte que la raíz efectivamente ocupa.

La transpiración real y su reparto entre horizontes son:

```
TrR   = min(DemT, AT + Inf)
TrRR  = max(0, TrR - Inf)
TrR_i = TrRR · (AT_i / AT)      si AT > 0, si no 0
```

La transpiración real está topada por la demanda o por el agua efectivamente
disponible, lo que sea menor. La infiltración del día se considera disponible
para transpiración de forma inmediata; solo el remanente `TrRR` se extrae de las
reservas de los horizontes, repartido en proporción a la contribución de cada
uno al agua transpirable total. Este reparto proporcional implica que los
horizontes más húmedos y más explorados aportan más, sin necesidad de un
esquema explícito de compensación entre capas.

#### 3.4.6 Evaporación real del suelo

La evaporación sigue el modelo de dos etapas de Ritchie (1972), aplicado
íntegramente sobre el horizonte 1:

```
AEF  = min(DemE, max(0, CH_1 - (CC_1 - U·Rastrojo)) + max(0, Inf - TrR))
AER  = DemE - AEF
base = (Inf + CH_1 - TrR_1 - AEF - 0.5·PMP_1) / (CC_1 - U·Rastrojo - 0.5·PMP_1)
ER   = AEF + min(AER, AER · clamp01(base)⁴)
```

`AEF` es el agua evaporable en la primera etapa, limitada por energía: es el
mínimo entre la demanda evaporativa y la suma del agua fácilmente evaporable
remanente en el horizonte superficial más la infiltración del día no consumida
por transpiración. El producto `U · Rastrojo` reduce el espesor de la capa de
fácil evaporación en proporción a la cobertura: un rastrojo abundante no solo
reduce la demanda evaporativa (sección 3.4.5) sino que además acorta la primera
etapa. `AER` es el remanente de demanda que solo puede satisfacerse en segunda
etapa, y se satisface parcialmente según una función de cuarta potencia del
grado de humedad relativa del horizonte superficial, que decae rápidamente a
medida que este se aproxima a la mitad del punto de marchitez. La función
`clamp01` acota el argumento al intervalo [0, 1] antes de elevarlo a la cuarta
potencia, una salvaguarda numérica de la implementación de referencia que se
describe en la sección 4.1.

#### 3.4.7 Drenaje interno y cierre del día

Una vez extraída el agua por transpiración y evaporación, el excedente por
encima de capacidad de campo drena hacia el horizonte inmediato inferior a tasa
`DR`, y el excedente por encima de saturación se transfiere íntegro. La cascada
se resuelve del horizonte 1 al 8, cada uno dependiendo del resultado del anterior
en el mismo día:

```
CHv_1 = CH_1 - TrR_1 - ER            CHv_i = CH_i - TrR_i          i = 2..8
Dr_i  = max(0, (CHv_i - CC_i) · DR)

Cf_1  = CHv_1 - Dr_1 + max(0, Inf - TrRR - ER)
Me_1  = max(0, Cf_1 - Sat_1)
Cf_i  = CHv_i - Dr_i + Dr_(i-1) + Me_(i-1)                          i = 2..8
Me_i  = max(0, Cf_i - Sat_i)

drenaje_profundo = Dr_8 + Me_8
CH_i(t+1) = min(Sat_i, Cf_i)
```

El drenaje que sale del horizonte 8 abandona el sistema y no se contabiliza como
recarga recuperable. El truncamiento final por saturación cierra el ciclo diario
y garantiza que el estado inicial del día siguiente sea físicamente admisible.

En cada día se evalúa además la condición de sándwich seco como salida
diagnóstica:

```
sándwich_seco = "Sí"   si  (CH_4 - PMP_4) / (CC_4 - PMP_4) < 0.30
```

es decir, cuando el horizonte 0,6-0,9 m cae por debajo del 30 % de agua útil.

![Balance hídrico diario del escenario de referencia, desde el 1° de marzo hasta veinte días después del fin del período crítico. El panel superior muestra el agua útil (%) en el primer metro, el segundo metro y el perfil completo, con la banda sombreada indicando el período crítico y la línea punteada el umbral de sándwich seco (30 %); el panel inferior muestra la precipitación diaria que impulsa las recargas visibles como quiebres ascendentes en las curvas.](figuras/fig2_balance_hidrico.png)

**Figura 2.** Trayectoria diaria del agua útil por horizonte agregado, resultado
del paso 4 sobre el escenario de referencia. El recorte temporal deliberado
—hasta poco después del período crítico— evita mostrar el tramo posterior a la
madurez fisiológica, cuyo dominio de validez se discute en la sección 5.1.

### 3.5 Paso 5 — Salidas

Las tres salidas de la herramienta son agregaciones de los pasos 1 y 4, sin
fórmulas propias nuevas.

**a) Eventos de lluvia en la ventana de siembra.** Número de días con
precipitación ≥ 10 mm en el intervalo que va de 14 días antes a 7 días después
de la fecha de siembra, ambos extremos incluidos. La asimetría de la ventana
refleja el uso operativo: los 14 días previos condicionan el estado del lecho de
siembra y la piso para la maquinaria, y los 7 posteriores condicionan la
implantación.

**b) Estado hídrico del suelo a la siembra.** Porcentaje de agua útil en 0-1 m,
1-2 m y 0-2 m a la fecha de siembra, más la presencia o ausencia de sándwich
seco ese día. Los tres porcentajes se agregan a partir de los horizontes: 0-0,9
m para el primer metro, 0,9-2,1 m para el segundo y el perfil completo para el
total.

**c) Confort hídrico durante el período crítico.** Cociente entre la
transpiración real acumulada y la demanda transpirativa acumulada en la ventana
que va del inicio al fin del período crítico, ambos extremos incluidos:

```
confort_hídrico = Σ TrR / Σ DemT      sobre [inicio_PC, fin_PC]
```

El índice varía entre 0 y 1: vale 1 cuando el cultivo transpiró a demanda
potencial todos los días del período crítico, y se aparta de 1 en la medida en
que el suelo no pudo abastecer esa demanda. Cuando la demanda acumulada en la
ventana es nula, el cociente es indefinido y la salida se reporta como faltante.
Este índice es el producto central de la herramienta: es el que traduce toda la
cadena de cálculo en una magnitud comparable entre años, entre sitios y entre
fechas de siembra, y es el que se prevé segmentar por fase ENSO en versiones
futuras.

---

## 4. Implementación de referencia: el paquete `balancehidrico`

Un aporte central de este trabajo, más allá de la formulación del método, es su
traducción a una **implementación de referencia** completa, verificada y de
código abierto: el paquete R `balancehidrico`. Esta sección describe su
arquitectura, su superficie funcional y la estrategia de validación que respalda
los resultados numéricos reportados en la sección 3.

### 4.1 Arquitectura

El paquete tiene una correspondencia deliberadamente estricta entre la
estructura del método y la estructura del código: un archivo fuente por paso
(`fenologia.R`, `profundizacion_radicular.R`, `curva_kcb.R`,
`balance_hidrico.R`, `salidas.R`), más un módulo de utilidades climáticas
compartidas (`utils_clima.R`) y un módulo de lectura y validación de datos
(`io.R`). Cada paso se expone como una o más **funciones puras**: reciben datos
ya parseados, no realizan operaciones de entrada/salida y no dependen del
estado interno de los otros pasos; la comunicación entre pasos se hace pasando
explícitamente tablas y fechas. El paso 4, el más complejo, se descompone
internamente en ocho funciones privadas —una por sub-cálculo del balance diario
(contenido hídrico inicial, escorrentía/infiltración, limitación hídrica de la
profundización, demanda, transpiración real, evaporación real, drenaje y
cierre)— lo que mantiene cada función en un tamaño auditable y testeable de
forma aislada.

Esta pureza tiene una consecuencia directa sobre la calidad de la validación:
el paso 4 puede testearse alimentándolo con series de profundidad radicular y
de Kcb tomadas **literalmente** de la planilla de cálculo de referencia, en
lugar de las series producidas por los pasos 2 y 3, lo que desacopla por
completo la verificación de las fórmulas del balance de la corrección de los
pasos previos. Un error en el paso 1, si lo hubiera, no se propagaría de forma
silenciosa a los tests del paso 4.

Los datos de entrada se separan según su naturaleza y su volatilidad. Las
series climáticas diarias se leen de CSV; los catálogos de estaciones, suelos,
cultivos y cultivares viven en YAML documentado campo por campo; y las
constantes categóricas de rastrojo y humedad inicial —que, a diferencia de los
catálogos, no varían entre escenarios— viven en un YAML separado, empaquetado
con la biblioteca. Todas las funciones de resolución de catálogo validan la
pertenencia del valor solicitado a la lista correspondiente y, si no
pertenece, abortan enumerando las opciones válidas, en lugar de propagar
valores nulos que producirían errores difíciles de rastrear más abajo en la
cadena de cálculo. La implementación también incorpora salvaguardas numéricas
explícitas donde el dominio matemático de una fórmula podría, en teoría,
exceder su rango físico admisible —por ejemplo, la base de la potencia cuarta
del término de evaporación en segunda etapa se acota a [0, 1] antes de
exponenciarse— de modo que combinaciones de parámetros infrecuentes no
produzcan resultados sin sentido agronómico.

### 4.2 Superficie funcional

El paquete expone 23 funciones públicas, organizadas por módulo:

| Módulo | Archivo | Funciones exportadas | Aserciones de test |
|---|---|---:|---:|
| Fenología | `fenologia.R` | 4 | 40 |
| Profundización radicular | `profundizacion_radicular.R` | 1 | 8 |
| Curva de Kcb | `curva_kcb.R` | 1 | 8 |
| Balance hídrico diario | `balance_hidrico.R` | 1 (+ 8 internas) | 1352 |
| Salidas | `salidas.R` | 4 | 13 |
| Utilidades climáticas | `utils_clima.R` | 3 | 11 |
| Entrada/salida y validación | `io.R` | 9 | 27 |
| **Total** | | **23** | **1459** |

Cada función pública está documentada con `roxygen2` (parámetros, tipos de
retorno, y la fórmula o el criterio que implementa), generando la referencia
completa del paquete de forma automática y mantenida junto con el código.

### 4.3 Estrategia de validación

La validación numérica se apoya en fixtures con valores **reales cacheados**
de la planilla de cálculo de referencia de CRC-SAS, comparados con tolerancia
de 1×10⁻⁹ —el límite práctico de la precisión de punto flotante de doble
exactitud para esta magnitud de cálculos encadenados—. El escenario de
referencia es trigo, cultivar intermedio-largo, estación 87480, siembra del 30
de mayo de 1983, sobre el suelo IN64MARC02 de Marcos Juárez (Haplustol údico).
Para el paso 4, el paso más exigente de validar por ser secuencial y
multivariable, el fixture cubre 428 días de simulación diaria continua, con
comparación completa de las 78 columnas de salida (contenido hídrico y flujos
de cada uno de los 8 horizontes, más las variables agregadas) en 17 fechas de
control distribuidas a lo largo de todo el ciclo agrícola, incluyendo el día de
inicialización, eventos de lluvia con escorrentía positiva, y el tramo posterior
a la madurez fisiológica. Los mecanismos específicos de maíz y soja —cambio de
temperatura base entre fases, temperatura óptima, penalización fotoperiódica
por umbral— se verifican con climas sintéticos diseñados para que el resultado
esperado sea calculable analíticamente de forma independiente del código, dado
que no se dispuso de un escenario de referencia cacheado para esas dos
especies. El conjunto completo de pruebas asciende a 1459 verificaciones
automatizadas (`testthat`), todas en verde, y el paquete pasa sin errores ni
advertencias el chequeo de integridad estándar de R (`R CMD check`).

### 4.4 Reproducibilidad operativa

El paquete incluye un script de corrida (`scripts/simular.R`) que ejecuta los
cinco pasos de punta a punta para un escenario puntual —estación, suelo,
cultivo, cultivar, fecha de siembra y condición hídrica inicial— descripto
íntegramente en un archivo YAML, sin parámetros codificados en el script. La
salida son cuatro archivos CSV (hitos fenológicos, serie diaria de fenología y
Kcb, serie diaria del balance completo, y las tres salidas agregadas),
pensados para que un especialista de dominio los coteje directamente contra la
planilla de cálculo original sin necesidad de leer código R. Este diseño —
configuración externa, salida tabular estándar, sin estado oculto— es lo que
permite que el mismo paquete sirva simultáneamente como motor de cálculo de una
futura herramienta operativa y como objeto de validación científica
independiente.

---

## 5. Discusión

### 5.1 Simplificaciones subordinadas al alcance

La decisión de mantener `Kcb_max` constante hasta el final de la simulación, sin
rampa de senescencia, es la simplificación más visible respecto del esquema
estándar de FAO-56 (Allen et al., 1998), donde el Kcb declina en la etapa final
del ciclo a medida que el canopeo pierde área foliar activa. La justificación es
de alcance: la única salida de la herramienta que depende de Kcb es el confort
hídrico, que se calcula exclusivamente entre el inicio y el fin del período
crítico. En los tres cultivos, el fin del período crítico ocurre bastante antes
de que la senescencia sea cuantitativamente relevante, de modo que agregar la
rampa descendente cambiaría la trayectoria simulada del agua del suelo después
del período crítico sin cambiar ninguna de las tres salidas.

Esto tiene una consecuencia que conviene explicitar: el balance simulado **sigue
transpirando a `Kcb_max` durante todo el resto de la serie climática**, incluso
después de la madurez fisiológica. Esa trayectoria no debe leerse como una
predicción del contenido hídrico en poscosecha; es un artefacto conocido de una
simplificación cuyo dominio de validez termina en el fin del período crítico. Si
se agregaran salidas referidas al barbecho posterior o al agua remanente a
cosecha, la rampa de senescencia dejaría de ser prescindible.

Un razonamiento análogo justifica que la evaporación se resuelva íntegramente
sobre el horizonte 1: el desecamiento de horizontes profundos por evaporación
directa es un fenómeno real pero de segundo orden frente a la extracción
radicular.

### 5.2 Comparación con otros paquetes R

R cuenta con varios paquetes publicados en CRAN para problemas de balance
hídrico de suelo y evapotranspiración, con alcances y supuestos distintos
de los de `balancehidrico`. Repasarlos ayuda a situar la contribución
específica de este trabajo dentro de ese panorama, más que a establecer una
jerarquía de calidad entre herramientas construidas con objetivos diferentes.

`CropWaterBalance` (Blain et al., 2024) calcula el balance hídrico climático diario para
programación de riego, con varios métodos de evapotranspiración de
referencia (Penman-Monteith, Priestley-Taylor, entre otros) sobre un balance
de suelo de compartimento único. `AquaBEHER` (Takele y Dell'Acqua, 2024)
integra evapotranspiración diaria con un balance de la zona radicular,
también de compartimento simplificado, para estimar el calendario de la
estación húmeda (inicio, cese y duración) en sistemas de secano —un problema
de caracterización agroclimática regional distinto del que resuelve el
método aquí descripto—. `Ecohydmod` (Souza, 2017) simula balance
hídrico de suelo junto con lluvia estocástica y dinámica de vegetación vía
NDVI, con un foco ecohidrológico orientado a vegetación natural o pastizales
más que a cultivos agrícolas manejados por cultivar. Ninguno de los tres
representa explícitamente la fenología de un cultivo por acumulación
térmica con sensibilidad al fotoperíodo, ni discretiza el perfil de suelo en
múltiples horizontes con capacidades hídricas propias —dos rasgos centrales
del método de la sección 3—.

En el extremo opuesto de complejidad, los modelos de cultivo de propósito
general —como WOFOST, disponible en R a través de `Rwofost` (Hijmans et al., 2025)— sí simulan
fenología (incluida una reducción por fotoperíodo entre un óptimo y un
crítico), biomasa, partición a órganos y rendimiento, con un nivel de
detalle mecanicista mayor que el de este método. Esa generalidad tiene un
costo: requieren una parametrización sustancialmente más extensa (dinámica
de área foliar, eficiencia de conversión, coeficientes de partición, entre
otros) y no están pensados para responder, con el mínimo de parámetros que
un productor o asesor puede reportar sin mediciones de campo, la pregunta
operativa puntual de este trabajo —cuánta agua hay a la siembra y qué
confort hídrico cabe esperar en el período crítico—.

| Paquete | Fenología por cultivo/cultivar | Fotoperíodo | Horizontes de suelo | Salida principal |
|---|---|---|---|---|
| `balancehidrico` (este trabajo) | Sí — trigo, maíz, soja, por cultivar | Sí, 2 submodelos distintos | 8, con capacidades hídricas propias | 3 indicadores de decisión de siembra |
| CropWaterBalance | No | No | 1 (compartimento único) | Balance climático diario, ETo |
| AquaBEHER | No | No | 1, zona radicular simplificada | Calendario de estación húmeda |
| Ecohydmod | No (vegetación vía NDVI) | No | 1 (simplificado) | Humedad de suelo, escorrentía, NDVI |
| Rwofost (WOFOST) | Sí, genérico multicultivo | Parcial (óptimo/crítico) | 1 o pocas capas configurables | Biomasa, área foliar, rendimiento |

La combinación de rasgos de `balancehidrico` —fenología multi-cultivo
calibrada por cultivar para condiciones de la Argentina; un perfil de ocho
horizontes con limitación explícita de la profundización radicular por
sequía del horizonte de avance (`LHPR`, sección 3.4.3); parametrización por
clases categóricas de humedad y cobertura en lugar de mediciones; y una
salida deliberadamente angosta de tres indicadores en vez de series
completas de biomasa o rendimiento— no coincide, hasta donde se pudo
relevar en CRAN, con ningún paquete disponible. Responde a un caso de uso
puntual —la decisión de siembra bajo información de campo incompleta— que
ni los paquetes de balance hídrico genérico ni los modelos de cultivo de
propósito general abordan directamente con esa combinación de simplicidad
paramétrica y especificidad agronómica regional.

### 5.3 El submodelo de fotoperíodo como decisión de primer orden

La duración del día se calcula con una expresión geométrica que incorpora la
corrección por crepúsculo civil (sección 2.5, 3.1.1): el término `0,1047 =
sin(6°)` extiende el día fotoperiódicamente efectivo hasta que el sol está 6°
bajo el horizonte, siguiendo la práctica recomendada para aplicaciones
fenológicas (Forsythe et al., 1995). Vale la pena cuantificar el efecto de esa
elección, porque no es marginal: en el escenario de validación de trigo, la
corrección desplaza cinco de los ocho hitos fenológicos hasta dieciséis días
respecto de la formulación sin corrección de crepúsculo. El mecanismo explica
la magnitud: la corrección aumenta `Fp` en aproximadamente media hora, y esa
media hora entra al cuadrado en el factor fotoperiódico del trigo (sección
3.1.2), acelerando la acumulación térmica ajustada durante toda la fase
emergencia-espiguilla terminal, con propagación en cascada a todos los hitos
posteriores.

El caso ilustra un punto general para modelos fenológicos con respuesta
fotoperiódica no lineal como el descripto en la sección 3.1: la elección del
submodelo de duración del día es una decisión de primer orden, con impacto
directo sobre la fecha estimada del período crítico y, por lo tanto, sobre el
confort hídrico reportado. Es también un argumento a favor de una
implementación de referencia como la descripta en la sección 4: al fijar el
submodelo de fotoperíodo en una única función testeada, cualquier extensión
futura del método hereda automáticamente esa precisión sin tener que
reproducir el cálculo de forma independiente.

![Fotoperíodo estimado a lo largo del año para la estación 87480 (lat. -32,9°), según el submodelo de duración del día sin corrección de crepúsculo (gris) y con corrección de crepúsculo civil (rojo, formulación vigente). La diferencia es de aproximadamente media hora en cualquier época del año, pero al entrar al cuadrado en el factor fotoperiódico del trigo produce el desplazamiento de hitos fenológicos descripto en el texto.](figuras/fig3_fotoperiodo.png)

**Figura 3.** Comparación de los dos submodelos de fotoperíodo evaluados sobre
la misma latitud y serie de días del año.

### 5.4 Limitaciones conocidas y trabajo futuro

**ENSO sin uso en el cálculo.** La fase ENSO de cada campaña está definida como
dato de entrada, derivada del Oceanic Niño Index (NOAA Climate Prediction
Center), pero no interviene todavía en ninguna fórmula del balance. La estrategia
prevista es completar primero la evaluación del método con un único año
climático, y luego pasar a la evaluación sobre climatología, momento en el cual
se definirán los criterios de uso de esa información. Está prevista además una
cuarta salida que reporte las tres actuales segmentadas por fase, permitiendo
contrastar el confort hídrico esperado en años Niño y Niña; el diseño de esa
segmentación —filtro sobre las campañas de la climatología, ponderación de
probabilidades o ajuste directo de alguna variable— está pendiente.

**Validación cruzada limitada a trigo.** El escenario cacheado disponible en
todas las rondas de la planilla de referencia corresponde a trigo. Los mecanismos
específicos de maíz —cambio de temperatura base entre fases, R2 como hito único—
y de soja —temperatura óptima, umbral fotoperiódico con penalización lineal—
están implementados y verificados con climas sintéticos de resultado calculable
analíticamente, pero no contra valores de la fuente. Como son mecanismos
estructuralmente distintos y no meras reparametrizaciones, una validación cruzada
para las tres especies es la prioridad de verificación pendiente. Lo mismo aplica
a la condición inicial de sándwich seco.

**Ciclos largos y siembras tardías.** El método no define un límite temporal para
la simulación en maíz y soja. En siembras muy tardías o en años fríos, la
acumulación térmica puede no alcanzar el umbral de madurez fisiológica dentro de
una duración razonable de ciclo, y el criterio de corte —presumiblemente
vinculado a una temperatura mínima, como criterio de daño por helada— está
pendiente de definición.

**Ausencia de retroalimentación del estrés hídrico sobre la fenología.** El
método supone que el desarrollo fenológico depende solamente de temperatura y
fotoperíodo. Es una simplificación estándar y razonable en la mayoría de las
condiciones, pero se aparta de la realidad bajo estrés hídrico severo, donde el
desarrollo puede acelerarse o retrasarse según la especie y el momento. Dado que
el confort hídrico se evalúa sobre una ventana definida fenológicamente, un error
en la ubicación de esa ventana bajo estrés severo afecta directamente la salida
principal.

**Catálogo de suelos y orquestación operativa.** Convertir el método en una
herramienta operativa requiere dos desarrollos que exceden el motor de cálculo:
la carga completa del catálogo de suelos —cientos de series con sus perfiles y
escalares— y un componente de orquestación capaz de correr el conjunto de
combinaciones de estación, suelo, cultivo, cultivar y fecha de siembra sobre una
climatología extensa, agregando los resultados en reportes interpretables.
Ninguno de los dos plantea problemas metodológicos, pero ambos condicionan el uso
efectivo del método.

---

## 6. Conclusiones

Se describió un método de simulación del balance hídrico de cultivos extensivos
diseñado para responder dos preguntas operativas —cuánta agua habrá en el perfil
a la siembra y qué confort hídrico cabe esperar en el período crítico— en el
marco de la gestión del riesgo climático en decisiones agrícolas de trigo, maíz y
soja en la Argentina. El método articula formulaciones consolidadas —fenología por tiempo térmico al
estilo DSSAT, coeficiente de cultivo dual de FAO-56, número de curva del SCS con
abstracción inicial variable, evaporación en dos etapas de Ritchie, fotoperíodo
con corrección de crepúsculo civil— en una cadena de cinco pasos de bajo costo
computacional y parametrización interpretable. Las simplificaciones que
introduce —Kcb sin senescencia, evaporación restringida al horizonte
superficial, ausencia de retroalimentación del estrés sobre la fenología— están
todas subordinadas al alcance de sus tres salidas, y su dominio de validez
termina, en todos los casos, en el fin del período crítico del cultivo.

Dos resultados trascienden el método particular. El primero es que la elección
del modelo de duración del día es una decisión de primer orden en modelos
fenológicos con respuesta fotoperiódica no lineal: incorporar la corrección
por crepúsculo civil desplazó hitos de trigo hasta dieciséis días (sección
5.2). El segundo es que el propio ejercicio de implementación —23 funciones
públicas organizadas en cinco módulos, 1459 verificaciones automatizadas y
validación numérica exacta contra un escenario real— constituye una
contribución independiente del método que describe: `balancehidrico` es una
base de código abierta, reproducible y extensible, apta tanto para auditar el
método en sí como para construir sobre ella la herramienta operativa completa.

La implementación de referencia en R reproduce el escenario de validación de
trigo con tolerancia de 1×10⁻⁹ sobre las 78 variables diarias del balance
hídrico, lo que establece una base sólida para las etapas siguientes:
validación cruzada para maíz y soja, incorporación de criterios de uso de la
información ENSO, y evaluación del método sobre climatologías extensas.

---

## Referencias

Allen, R. G., Pereira, L. S., Raes, D., & Smith, M. (1998). *Crop
evapotranspiration: Guidelines for computing crop water requirements.* FAO
Irrigation and Drainage Paper 56. FAO, Roma.

Blain, G. C., Sobierajski, G. R., Pires, R. C. M., Sparks, A. H., & Martins,
L. L. (2024). *CropWaterBalance: Climate Water Balance For Irrigation
Purposes.* R package version 0.2.0.
https://CRAN.R-project.org/package=CropWaterBalance

Boote, K. J., Jones, J. W., Hoogenboom, G., & Pickering, N. B. (1998). The
CROPGRO model for grain legumes. En G. Y. Tsuji, G. Hoogenboom & P. K. Thornton
(Eds.), *Understanding Options for Agricultural Production*, Systems Approaches
for Sustainable Agricultural Development, vol. 7 (pp. 99–128). Springer,
Dordrecht.

Forsythe, W. C., Rykiel, E. J., Stahl, R. S., Wu, H., & Schoolfield, R. M.
(1995). A model comparison for daylength as a function of latitude and day of
year. *Ecological Modelling*, 80, 87–95.

Hargreaves, G. H., & Samani, Z. A. (1985). Reference crop evapotranspiration
from temperature. *Applied Engineering in Agriculture*, 1(2), 96–99.

Hawkins, R. H., Ward, T. J., Woodward, D. E., & Van Mullem, J. A. (2009). *Curve
Number Hydrology: State of the Practice.* ASCE, Reston, VA.

Hijmans, R. J., Fang, H., van Diepen, C. A., de Wit, A., van Kraalingen, D.,
van der Wal, T., Rappoldt, C., Boogaard, H., & Noy, I. G. A. M. (2025).
*Rwofost: WOFOST Crop Growth Simulation Model.* R package version 0.8-7.
https://CRAN.R-project.org/package=Rwofost

Jones, J. W., Hoogenboom, G., Porter, C. H., Boote, K. J., Batchelor, W. D.,
Hunt, L. A., Wilkens, P. W., Singh, U., Gijsman, A. J., & Ritchie, J. T. (2003).
The DSSAT cropping system model. *European Journal of Agronomy*, 18, 235–265.

NOAA Climate Prediction Center. *Oceanic Niño Index (ONI).* Recuperado de
https://origin.cpc.ncep.noaa.gov/products/analysis_monitoring/ensostuff/ONI_v5.php

Ritchie, J. T. (1972). Model for predicting evaporation from a row crop with
incomplete cover. *Water Resources Research*, 8(5), 1204–1213.

Ritchie, J. T., & Otter, S. (1985). Description and performance of CERES-Wheat:
A user-oriented wheat yield model. En *ARS Wheat Yield Project*, ARS-38 (pp.
159–175). USDA-ARS, Springfield.

Souza, R. (2017). *Ecohydmod: Ecohydrological Modelling.* R package version
1.0.0. https://CRAN.R-project.org/package=Ecohydmod

Takele, R., & Dell'Acqua, M. (2024). *AquaBEHER: Estimation and Prediction of
the Wet Season Calendar and Soil Water Balance for Agriculture.* R package
version 1.4.0. https://CRAN.R-project.org/package=AquaBEHER

USDA Soil Conservation Service (1972). *National Engineering Handbook, Section
4: Hydrology.* USDA-SCS, Washington, DC.
