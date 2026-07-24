# Documento de continuidad de desarrollo

**Proposito de este documento:** este repo (`balance-hidrico`) nace como una
migracion desde un repo mas viejo (`balance_agua_suelo`) que va a **borrarse
localmente pronto**. Todo lo que hacia falta para seguir el desarrollo sin
esa historia se volco aca. Si estas retomando este proyecto y no tenes el
contexto de como se llego hasta aca, este es el documento a leer primero.

Fecha de la migracion: 2026-07-24.

## 1. Que es este proyecto

Herramienta de simulacion de balance hidrico de cultivos para CRC-SAS
(Centro Regional de Cambio Climatico y Ayuda a la Toma de Decisiones,
Argentina), para trigo, maiz y soja. El objetivo final de la herramienta
(no implementado todavia, ver seccion 6) es: dado un lugar, un suelo, un
cultivo/cultivar y una fecha de siembra planeada, predecir:

1. Numero de eventos de lluvia >=10mm en la ventana -14/+7 dias alrededor de
   la siembra.
2. Contenido hidrico del suelo (agua util %) en la fecha de siembra.
3. Confort hidrico (0-1) del cultivo durante su periodo critico.

Este paquete R (`balancehidrico`) implementa los **Pasos 1 a 3** del metodo
(fenologia, profundizacion radicular potencial, curva de Kcb) — los pasos
previos y necesarios para poder calcular el balance hidrico diario (Paso 4),
que **todavia no esta implementado** porque su especificacion esta
incompleta (ver seccion 6).

## 2. Historia: dos lineas de trabajo (Thread A vs Thread B)

En el repo original (`balance_agua_suelo`) hubo dos intentos paralelos de
extender un pipeline que originalmente solo soportaba trigo via DSSAT:

- **Thread A (DSSAT, abandonado para este repo):** extender
  `lib/fenologia.R` del repo viejo (funciones basadas en el motor CERES de
  DSSAT, con archivos `.CUL`/`.ECO`/`.SOL`) para soportar maiz y soja. Quedo
  **en pausa, no abandonado del todo**, pero fuera del alcance de este repo
  nuevo: este repo (`balance-hidrico`) es exclusivamente la linea B.
- **Thread B (metodo propio CRC-SAS, es este repo):** CRC-SAS definio un
  metodo propio, mas simple, de acumulacion de unidades termicas (no usa
  DSSAT en absoluto). Se decidio priorizar esta linea porque es la que
  CRC-SAS realmente quiere usar en produccion.

**Decision (2026-07-23, en el repo viejo):** foco exclusivo en Thread B.

## 3. Proceso de validacion con el experto del dominio

El metodo (Thread B) partio de dos documentos fuente de CRC-SAS: un
documento de trabajo (`.docx`) y una planilla de calculo (`.xlsx`) —
copiados en `referencias/`. Un analisis inicial detecto ~20 dudas /
divergencias / vacios, documentados en
`referencias/documento_maestro_fenologia_balance_hidrico.md` (Seccion 2,
"Dudas"), separadas en dos bloques:

- **Seccion 2a** — dudas puntuales sobre los Pasos 1-3 (que SI estaban
  desarrollados en las fuentes): F-1 a F-7 (fenologia), PR-1/PR-2
  (profundizacion radicular), KC-2 (curva Kcb).
- **Seccion 2b** — todo lo que el metodo no llego a desarrollar (el docx
  fuente queda cortado a mitad del Paso 4) o son datos de soporte/generales:
  BH-1 a BH-7 (balance hidrico diario), KC-1 (curva Kcb, senescencia), DS-1
  a DS-3 (datos de soporte), G-1 a G-3 (generales).

**El experto respondio la Seccion 2a completa, en dos rondas** (2026-07-24):
primero F-1 a F-7 + PR-1 + PR-2 + KC-2 (todas las de 2a excepto KC-1, que en
realidad pertenece a la 2b); despues, a pedido explicito, tambien **KC-1**
(que no era parte del pedido original pero se necesitaba para poder cerrar
la Curva de Kcb). Los archivos con las respuestas y las fuentes actualizadas
en consecuencia son exactamente los que estan en `referencias/`:
`Respuestas.docx`, `Documento trabajo fenologia y balance hidrico.docx` y
`Calculos fenologia y balance hidrico.xlsx` (version final, con ambas
rondas incorporadas).

**Todas las dudas de la Seccion 2a (incluida KC-1) estan resueltas y
verificadas** — no solo leidas, sino chequeadas contra las formulas reales
del xlsx (valores cacheados, no solo texto) antes de implementar. Resumen
de cada una (el detalle completo, con la formula, esta en
`MANUAL_TECNICO.md`):

| Duda | Resolucion |
|---|---|
| F-1 (bloqueante) | `fPC = ET+800`, distinto de `Z71 = ET+700` (antes se confundian). `MF = fPC+400`. |
| F-2 | Todo relativo a ET (no a Z71). |
| F-3 | `iPC (soja) = R1+120`. `UT_R1-R5` es una constante fija = 300. |
| F-4 | Formato de fecha de salida (absoluta/DOY/dias desde siembra) queda a criterio de implementacion; no es visible al usuario final. |
| F-5 (importante) | Formula del factor fotoperiodico de trigo lleva `min(20, Fp)` para anular el efecto por encima de 20h. |
| F-6 (importante) | Mecanismos de fotoperiodo por cultivo: trigo = cuadratica continua (E->ET); maiz = sin efecto; soja = umbral discreto + penalizacion lineal (E->MF). |
| F-7 | Usar `Tm` de la base climatica si existe; si no, `(Tx+Tn)/2`. |
| PR-1 (importante) | La raiz crece hasta el cuaje de granos **o** la profundidad maxima del suelo, lo que ocurra primero. El xlsx no aplica el segundo tope (no tiene contexto de suelo); el codigo de este repo si lo aplica. |
| PR-2 | Pertenece al Paso 4 (limitacion por sequia) — sigue sin poder responderse hasta implementar el Paso 4. |
| KC-1 (importante) | Kcb se mantiene constante en `kcb_max` desde `ut_ikcbmax` hasta madurez fisiologica, **a proposito** (no es un vacio): el output relevante se calcula solo hasta fin del periodo critico. |
| KC-2 | La rampa de Kcb usa la serie de UT **sin** ajuste de fotoperiodo. |

**La Seccion 2b (BH-1 a BH-7, DS-1 a DS-3, G-1 a G-3) sigue sin responder**
— ver seccion 6 de este documento.

## 4. Que esta implementado en este repo

Paquete R `balancehidrico`, con estructura de paquete formal (DESCRIPTION,
NAMESPACE, `R/`, `tests/testthat/`, `man/` generado con roxygen2). Un
archivo por paso del metodo (alta cohesion, bajo acoplamiento — cada paso es
testeable por separado):

- `R/fenologia.R` — Paso 1: `calcular_fenologia()` (dispatcher) +
  `calcular_fenologia_trigo()` / `_maiz()` / `_soja()`.
- `R/profundizacion_radicular.R` — Paso 2: `calcular_profundidad_radicular()`.
- `R/curva_kcb.R` — Paso 3: `calcular_curva_kcb()`.
- `R/utils_clima.R` — temperatura media, declinacion solar, fotoperiodo.
- `R/io.R` — lectura de CSV de clima y YAML de parametros, con validacion
  explicita (falla rapido con mensajes claros si falta algo, en vez de
  propagar `NULL`s silenciosos).

Detalle completo de formulas y decisiones de diseno: `MANUAL_TECNICO.md`.
Como usarlo: `README.md` de la raiz.

### Verificacion hecha

- `devtools::test()`: **67/67 tests en verde**, 0 warnings.
- `devtools::check()`: **0 errores, 0 warnings**, 1 nota irrelevante
  ("unable to verify current time", limitacion de sandbox sin red — no es
  un problema real).
- Los tests de **trigo** comparan contra valores **reales cacheados** en
  `referencias/Calculos fenologia y balance hidrico.xlsx` (estacion 87480,
  cultivar intermedio-largo, siembra 1983-05-30): los 8 hitos fenologicos y
  varios puntos de control de la serie diaria (UT, profundidad radicular,
  Kcb) coinciden con tolerancia `1e-9`.
- Los tests de **maiz y soja NO tienen fixture cruzado contra el xlsx**: el
  archivo de referencia solo tiene cacheado el escenario de trigo (no hay
  LibreOffice/Excel disponible en el entorno de desarrollo para recalcular
  con otro cultivo activo en el dropdown). Se usan climas sinteticos donde
  el resultado se calcula a mano de forma independiente del codigo. **Si en
  algun momento se puede conseguir del experto una version del xlsx con
  maiz o soja como cultivo activo (recalculada), vale la pena sumar
  fixtures cruzados** — es la mejora de testing mas valiosa pendiente.

Nada de este codigo esta commiteado a git todavia en este repo (al momento
de escribir este documento) — el usuario decide cuando commitear/pushear.

## 5. Decisiones de arquitectura (por que esta hecho asi)

Decisiones tomadas explicitamente por el usuario durante el diseno (no
son solo elecciones tecnicas mias, son requerimientos):

- **Codigo completamente nuevo**, sin tocar el pipeline DSSAT (Thread A).
- Paquete R formal (no scripts sueltos) — porque en algun momento va a haber
  ademas un **script de orquestacion de simulaciones** que haga
  `library(balancehidrico)` / `devtools::load_all()` sobre el paquete. Ese
  script **todavia no existe** (ver seccion 7).
- **Un archivo por paso**, alta cohesion / bajo acoplamiento — pedido
  explicito del usuario, para que cada paso se pueda testear de forma
  aislada.
- Clima en **CSV**, parametros de cultivo/cultivar/estacion/suelo en
  **YAML bien documentado** (con ejemplo comentado campo por campo) — pedido
  explicito del usuario.
- **Tests automatizados con testthat** — pedido explicito del usuario, pese
  a que el repo original no tenia ninguna convencion de testing (asi que
  esto es una convencion nueva que arranca en este repo).

El plan de implementacion completo (aprobado por el usuario antes de
escribir codigo) tiene mas detalle sobre la estructura de archivos y el
contrato de datos exacto; si sigue existiendo, esta en
`~/.claude/plans/harmonic-scribbling-cat.md` de la maquina donde se hizo
este trabajo — pero como es una ruta local fuera de git, **no asumas que va
a seguir estando disponible**; el contenido relevante ya esta volcado en
`MANUAL_TECNICO.md` (contrato de datos) y este documento.

## 6. Que falta: Paso 4 (Balance hidrico diario)

**No implementado, y su especificacion esta incompleta.** El documento de
trabajo original queda cortado a mitad de este paso; la Seccion 2b del
documento maestro (`referencias/documento_maestro_fenologia_balance_hidrico.md`,
lineas ~517 en adelante) tiene todas las dudas pendientes, agrupadas asi:

### Balance hidrico diario (las mas bloqueantes)

- **BH-1 [BLOQUEANTE]** — El Paso 4 completo no esta especificado ni
  implementado: faltan las formulas de Infiltracion, Transpiracion,
  Evaporacion, Drenaje y Agua-final-por-horizonte. Solo Escorrentia tiene
  formula (BH-2).
- **BH-2 [BLOQUEANTE]** — La formula de escorrentia
  (`Esc = max(Pp - Absi*AtM, 0)^2 / (Pp + AtM*(1-Absi))`) esta, pero faltan
  los parametros: la relacion `AtM`<->`CN`, el valor de `Absi`, y como
  entran las constantes hidricas de los primeros 20cm y la cobertura de
  rastrojo. *(Nota: en una version mas reciente del xlsx, la hoja `Balance
  Hidrico` ya no esta vacia y tiene una formula `Atm=254*(100/CN-1)` — el
  clasico SCS — pero esto **no fue confirmado por el experto** todavia; hay
  que preguntarlo antes de asumirlo.)*
- **BH-3 [BLOQUEANTE]** — ETo (Hargreaves-Samani) no implementada: la celda
  `clima!K` (`ETO(H-S)`) esta vacia, no hay formula. Sin ETo no hay demanda
  evapotranspirativa.
- **BH-4 [BLOQUEANTE]** — Calculo del confort hidrico (0-1): no hay formula
  ni definicion operativa (¿ratio transpiracion real/potencial acumulado en
  iPC-fPC?). Es uno de los 3 outputs de la herramienta.
- **BH-5 [IMPORTANTE]** — Limitacion de la profundizacion radicular por
  sequia (con horizonte <30% AU la tasa decae linealmente hasta 0% AU): la
  regla general esta descripta pero no la formula exacta ni sobre que
  horizonte se evalua. Este repo implementa solo la profundizacion
  **potencial** (sin esta limitacion) — ver PR-2 en la seccion 3.
- **BH-6 [IMPORTANTE]** — La discretizacion de horizontes del balance
  (0-0.2/0.2-0.4/.../1.8-2.1 m) no coincide 1:1 con los PFH propios de la
  tabla `suelos` (ej. 20/40/60/80cm) — falta como mapear/interpolar.
- **BH-7 [IMPORTANTE]** — Los parametros `kl`, `Um`, `U`, `DR` y cobertura
  de rastrojo estan provistos en la tabla `suelos` pero sin ecuacion que
  los use (transpiracion, evaporacion, drenaje).

### Datos de soporte / generales (menos bloqueantes, pero pendientes)

- **DS-1 [IMPORTANTE]** — Como se traduce el AU% inicial informado por
  metro (0-1, 1-2, 0-2.1m) al contenido inicial por horizonte del balance
  (incluida la regla de "sandwich seco").
- **DS-2 [IMPORTANTE]** — El ENSO esta descripto en el docx (categorizacion
  Nino/Nina/Neutro via ONI) pero no aparece en ninguna hoja del xlsx — no
  esta claro si se usa en el calculo o solo para segmentar campañas
  climatologicas.
- **DS-3 [MENOR]** — En la tabla `suelos`, los atributos de serie (U, DR,
  CN, kl, Um) solo estan en la primera fila de cada serie de suelo; falta
  confirmar si hay que propagarlos (forward-fill) al resto de los
  horizontes.
- **G-1 [IMPORTANTE]** — El xlsx tiene una ventana fija de ~500 filas para
  la tabla auxiliar; falta garantizar/definir que pasa con ciclos largos o
  siembras tardias que se salgan de esa ventana ("Datos insuficientes").
  *(Nota: este repo no tiene esa limitacion — la implementacion en R
  itera sobre toda la serie climatica disponible, sin ventana fija — pero
  vale la pena confirmar con el experto si hay algun limite de dias
  esperado de todas formas.)*
- **G-2 [MENOR]** — Habia un typo (`tropial-intermedio` en vez de
  `tropical-intermedio`) en una version anterior del xlsx. **Ya
  normalizado** en `inst/extdata/parametros_ejemplo.yml` de este repo
  (usa "tropical-intermedio"), pero si se regenera el YAML desde una nueva
  version del xlsx, prestar atencion a esto.
- **G-3 [MENOR]** — El Paso 5 ("Salidas") del docx no esta desarrollado mas
  alla de listar los 3 outputs generales; falta la logica de agregacion
  temporal/espacial (climatologia >30 años, reporte por campaña, etc.).

**Como retomar el Paso 4:** antes de escribir codigo, resolver al menos las
4 dudas bloqueantes (BH-1 a BH-4) con el experto del dominio, siguiendo el
mismo proceso que se uso para la Seccion 2a (preguntar, verificar la
respuesta contra el xlsx actualizado con valores reales, no solo texto,
antes de implementar).

## 7. Proximos pasos sugeridos

En orden de expectativa, no de obligacion:

1. **Resolver Paso 4** con el experto (seccion 6) y luego implementarlo,
   siguiendo el mismo patron de los Pasos 1-3 (archivo propio, funciones
   puras, tests con fixtures reales cuando sea posible).
2. **Script de orquestacion de simulaciones (batch)**: `scripts/simular.R`
   (agregado 2026-07-24) corre un escenario puntual y exporta CSV
   (`<prefix>_hitos.csv`, `<prefix>_serie_diaria.csv`), pensado para generar
   salidas que el experto de dominio pueda validar contra el xlsx — ver
   `README.md` seccion "Script de corrida". Recibe como unico argumento la
   ruta a un **YAML de configuracion de escenario** (`scripts/
   escenario_ejemplo.yml` es el ejemplo: apunta a `inst/extdata/
   clima_ejemplo.csv` y `inst/extdata/parametros_ejemplo.yml`) — no tiene
   parametros hardcodeados, para correr otro escenario se copia y edita ese
   YAML. Lo que **todavia no existe** es una version batch que corra un
   **conjunto** real de estaciones/suelos/cultivos/cultivares y agregue
   resultados (climatologia >30 años, reporte por campaña — ver G-3 en la
   seccion 6); hay que definir su alcance cuando se llegue a esa etapa.
3. **Fixtures cruzados para maiz y soja**: si el experto puede reenviar el
   xlsx con maiz o soja como cultivo activo en el dropdown (recalculado),
   agregar tests equivalentes a los de trigo para esos dos cultivos.
4. Si se retoma Thread A (DSSAT) en el repo viejo en paralelo, tener en
   cuenta que este repo es independiente — no hay codigo compartido entre
   ambos.

## 8. Mapa del repo

```
balance-hidrico/
  README.md                          — overview, instalacion, uso
  DESCRIPTION, NAMESPACE, LICENSE     — metadata del paquete R
  R/                                  — codigo fuente (ver MANUAL_TECNICO.md)
  man/                                — documentacion generada (roxygen2)
  tests/testthat/                     — tests automatizados
  inst/extdata/                       — CSV de clima y YAML de parametros de ejemplo
  scripts/simular.R                   — corrida de un escenario puntual -> CSV para validar con el experto
  scripts/escenario_ejemplo.yml        — YAML de configuracion de ejemplo para simular.R
  documentacion/
    MANUAL_TECNICO.md                 — como esta implementado cada proceso
    CONTINUIDAD_DESARROLLO.md         — este documento
    referencias/                      — documentos fuente de CRC-SAS + respuestas del experto
      documento_maestro_fenologia_balance_hidrico.md   — sintesis con TODAS las dudas (2a + 2b)
      Documento trabajo fenologia y balance hidrico.docx — fuente original de CRC-SAS (actualizada)
      Calculos fenologia y balance hidrico.xlsx          — planilla de referencia (actualizada, con formulas y valores cacheados)
      Respuestas.docx                                    — respuestas del experto a la Seccion 2a (incluye KC-1)
```
