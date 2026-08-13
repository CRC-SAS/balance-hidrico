# Future work

Este documento reemplaza a `CONTINUIDAD_DESARROLLO.md` (hasta el 2026-08-01,
cuando se completaron los Pasos 4 y 5). El contenido historico de ese
documento — la migracion desde `balance_agua_suelo`, el proceso de
validacion con el experto de CRC-SAS, y las decisiones de arquitectura —
esta ahora en `MANUAL_TECNICO.md` (secciones "Historia del proyecto" y
"Decisiones de arquitectura"), junto con el detalle tecnico completo de los
5 pasos del metodo. Este documento contiene **unicamente** lo que sigue
pendiente.

## Pendientes confirmados por CRC-SAS (no bloqueantes, sin fecha)

Estos fueron preguntados explicitamente al experto de CRC-SAS
(Guillermo Garcia / Jorge) el 2026-07-29 y respondidos por escrito el
2026-08-01, en un documento de trabajo que nunca se commiteo a este repo.
Quedan igual de vigentes aunque esa fuente no este disponible aca.

- **ENSO en el calculo del balance en si.** El ONI/ENSO esta descripto como
  dato de entrada (categorizacion Niño/Niña/Neutro por campaña, ver
  `MANUAL_TECNICO.md`) pero no interviene en ninguna formula del balance
  hidrico todavia. Respuesta de CRC-SAS: *"Aun no hemos implementado nada
  respecto al ENSO. Una vez que terminemos de evaluar el modelo con un solo
  año climatico, empezaremos las pruebas con climatologia. Alli
  indicaremos los criterios para utilizar informacion sobre ENSO."* — no
  hay diseño que implementar todavia, hay que esperar a que CRC-SAS defina
  el criterio.
- **Salida adicional de comparacion Niño vs Niña.** CRC-SAS confirmo que
  las 3 salidas de Paso 5 son definitivas, pero van a pedir sumar una
  cuarta comparacion (los mismos 3 valores segmentados por fase ENSO) "una
  vez que evaluemos el modelo con un solo año climatico" — depende de que
  se resuelva el punto anterior primero.
- **Limite de dias para ciclos largos / siembras tardias (maiz y soja).**
  La implementacion en R no tiene limite (itera sobre toda la serie
  climatica disponible, a diferencia de la ventana fija de ~500 filas de la
  planilla de referencia). Respuesta de CRC-SAS: *"No lo hemos especificado, pero podemos
  poner algun limite para maiz y soja vinculado a temperatura minima.
  Debemos definirlo."* — sin diseño ni fecha.

## Testing

- **Fixtures cruzados para maiz y soja (Pasos 1 y 3).** Los tests de estos
  cultivos usan climas sinteticos calculados a mano (`tests/testthat/test-fenologia.R`,
  `test-curva_kcb.R`) porque la planilla de referencia de CRC-SAS solo
  tuvo, en todas las rondas recibidas, el escenario de trigo activo en el
  dropdown. Si el experto puede reenviar la planilla con maiz o soja como
  cultivo activo (recalculado), vale la pena agregar fixtures reales
  equivalentes a los de trigo (que si comparan contra valores cacheados,
  Pasos 1 a 4).
- **Sandwich seco en la condicion inicial, sin fixture cruzado.** El
  comportamiento (`sandwich_seco_inicial = TRUE` en
  `calcular_balance_hidrico()`) esta implementado y testeado con un caso
  sintetico (`tests/testthat/test-balance_hidrico.R`), pero el escenario
  cacheado de la planilla de referencia no ejercita ese caso (usa 0.9 parejo en
  ambos metros). No es bloqueante, pero seria mas solido tener un fixture
  real si CRC-SAS puede correr ese escenario en su herramienta.

## Alcance no implementado (deliberadamente fuera de esta version)

- **Script de orquestacion batch — resuelto (2026-08-13), acotado a una
  estacion por corrida.** `scripts/simular_batch.R` corre un **conjunto**
  de suelos/cultivos/cultivares/condiciones iniciales x anios de siembra
  (una estacion fija por batch) a partir de un xlsx de condiciones
  iniciales (`scripts/lib_simular.R::leer_condiciones_iniciales_xlsx()`)
  y acumula resultados en los mismos 4 CSV de siempre + un CSV de
  errores (ver seccion "Script de corrida batch" del `README.md`).
  Multi-estacion por batch y agregacion/reporte por campaña siguen sin
  implementar (quedan para una ronda futura si hace falta).
  **Limitacion encontrada y resuelta (2026-08-13) con un suelo real de
  menos de 8 horizontes** (`IN65JUNI03`, 5 horizontes hasta 1.2m):
  `R/balance_hidrico.R` asumia una estructura fija "primer metro =
  horizontes 1-4, segundo metro = horizontes 5-8", nunca antes puesta a
  prueba contra un suelo mas somero. CRC-SAS confirmo la regla general
  (primer metro = horizontes 1 a `min(4,n_h)`, segundo metro = el resto
  hasta un maximo de 4 horizontes mas) y se generalizo el codigo (ver
  seccion 8.11bis de `MANUAL_TECNICO.md`) sin regresion contra el fixture
  de 8 horizontes.
  **Limitacion encontrada y resuelta (2026-08-13) con dias puntuales sin
  dato en la estacion real** (Junin Aero, ~80 dias sin `tx`/`tn`/`tm`/`pp`
  en 35 anios de serie -- la mayoria de `tm` ya se resolvian solos via
  `calcular_temperatura_media()`, el resto rompia el balance secuencial):
  `completar_gaps_clima()` (`R/imputacion_clima.R`, seccion 12bis de
  `MANUAL_TECNICO.md`) rellena esos huecos con un modelo estocastico
  (STL + AR(1) estacional para temperaturas, Markov + gamma para
  precipitacion) antes de correr el batch. Con esto y el fix de suelos,
  el batch de Junin corre **840/840** sin errores.
- **Catalogo completo de suelos.** La planilla de referencia de CRC-SAS
  tiene 600+ filas de suelos (multiples series por localidad). Este paquete solo
  tiene cargados en `inst/extdata/parametros_ejemplo.yml` los 2 suelos
  usados en los fixtures de test (`RC00000001` para Paso 2,
  `IN64MARC02` con datos completos de Paso 4); el batch de Junín agrega 3
  suelos mas (`IN65JUNI01/02/03`) via el xlsx de condiciones iniciales,
  pero eso sigue siendo especifico de esa localidad, no el catalogo
  completo. Convertir el catalogo completo a YAML (o a otro formato de
  carga) es un problema de transformacion de datos, no de diseño del
  paquete, pero sigue pendiente.
- **Paso 5 sin completar en el documento de trabajo formal de CRC-SAS.**
  Las 3 salidas estan confirmadas y documentadas en
  `MANUAL_TECNICO.md`, pero en el documento de trabajo original de CRC-SAS
  la seccion "Paso 5 - Salidas" seguia solo con el titulo, sin desarrollar,
  al 2026-08-01. No bloquea nada de este repo (la fuente de verdad de Paso
  5 quedo asentada en `MANUAL_TECNICO.md` a partir de las respuestas
  escritas del experto), pero si CRC-SAS termina de redactar esa seccion
  en su propio documento, vale la pena chequear que no haya agregado nada
  nuevo.
- **Thread A (DSSAT).** Este repo es exclusivamente el metodo propio de
  CRC-SAS (Thread B). Si se retoma el pipeline DSSAT (`lib/fenologia.R`
  del repo `balance_agua_suelo`) en paralelo, no hay codigo compartido con
  este paquete.
