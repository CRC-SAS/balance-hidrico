# Documento maestro — Balance hídrico de cultivos (CRC-SAS)

> **Base para implementación.** Este documento consolida TODO lo que surge de los dos archivos fuente del proyecto (`Documento trabajo fenología y balance hídrico.docx` y `Cálculos fenología y balance hídrico.xlsx`) y está pensado para reemplazar la lectura de esos originales por parte del desarrollador que implemente el nuevo script (fenología + profundización radical + curva Kcb + balance hídrico diario) para trigo, maíz y soja.
>
> **Alcance de fuentes (regla estricta del proyecto):** solo se considera lo analizado en el docx y el xlsx. No se incorpora ningún otro archivo del repositorio (.R, .csv, .md, etc.). El conocimiento agronómico general (FAO-56, DSSAT, Hargreaves-Samani, Kcb dual) se usa únicamente para *explicar* conceptos ya nombrados en las fuentes, nunca para inventar valores, fórmulas o pasos.
>
> **Convención de trazabilidad usada en todo el documento:**
> - `[DOCX-narrativa]` — proviene del texto/lista de pasos del documento de trabajo.
> - `[DOCX-fórmula]` — proviene de una fórmula explícita escrita en el documento de trabajo.
> - `[XLSX]` — proviene de la implementación real en la planilla (hojas `clima`, `suelos`, `cultivo`, `condiciones iniciales`, `fenologia`, `balance hídrico`).
> - `[DIVERGENCIA]` — hay contradicción entre fuentes; se remite a la Sección 2 (Dudas).
> - `[NO ESPECIFICADO]` — no está en ninguna fuente; requiere definición del experto.

---

# SECCIÓN 1 — Todo lo entendido (la base para implementación)

## 1. Propósito y alcance de la herramienta

**Propósito** `[DOCX-narrativa]`: gestionar el riesgo climático en decisiones agrícolas combinando información climática con ecofisiología de cultivos. Concretamente, predice:
- La disponibilidad de agua en el suelo a la siembra.
- El confort hídrico durante el período crítico del cultivo.

**Qué es** `[DOCX-narrativa]`: una herramienta de simulación del balance hídrico de cultivos basada en climatología, monitoreo y pronóstico. Cultivos soportados: **trigo, maíz y soja** (siempre como primer cultivo de la campaña).

**Dominio temporal** `[DOCX-narrativa]`:
- El usuario puede consultar desde el **1 de marzo** hasta la **fecha de siembra planeada**.
- Se asume **barbecho libre de malezas** entre la fecha de consulta y la siembra.
- La simulación corre desde la fecha de consulta hasta la **madurez fisiológica** del cultivo.

**Dominio espacial** `[DOCX-narrativa]` / `[XLSX]`:
- Estaciones meteorológicas validadas por el SMN (se muestran como localidad).
- Se usa la climatología histórica (>30 años) de la estación.
- El xlsx incluye **16 localidades** `[XLSX suelos]`: Benito Juárez, Coronel Suárez, Gualeguaychú, Junín, Laboulaye, Marcos Juárez, Nueve de Julio, Paraná, Pehuajó, Pilar, Reconquista, Río Cuarto, Tandil, Tartagal, Tres Arroyos, Villa Reynolds.

---

## 2. Inputs completos

### 2.1 Clima — hoja `clima` `[XLSX]`

Serie climática **diaria** por estación. Dimensiones del ejemplo: `A1:K548` (una estación, ~547 días de datos; la ventana se extiende con la climatología histórica).

| Columna | Encabezado | Contenido | Origen |
|---|---|---|---|
| A | `omm_id` | ID de estación (ej. 87480) | dato |
| B | `fecha` | fecha (datetime) | dato |
| C | `dia_año` | día del año (1–365/366) | fórmula `=B2-DATE(YEAR(B2),1,1)+1` |
| D | `Tx` | temperatura máxima (°C) | dato |
| E | `Tn` | temperatura mínima (°C) | dato |
| F | `Tm` | temperatura media (°C) | dato (en el ejemplo viene dado; ver nota) |
| G | `Pp` | precipitación (mm) | dato |
| H | `latitud` | latitud de la estación (grados, negativa en HS) | dato |
| I | `declinación solar` | δ (grados) | fórmula `=23.45*SIN(RADIANS(360/365*(C2-81)))` |
| J | `Fp` | fotoperíodo (h) | fórmula (abajo) |
| K | `ETO(H-S)` | ETo por Hargreaves-Samani (mm) | **encabezado presente pero celda VACÍA** `[XLSX]` — ver Duda |

**Fotoperíodo** `[XLSX clima!J]`:
```
Fp = IFERROR( 24/PI() * ACOS( -TAN(RADIANS(lat)) * TAN(RADIANS(decl)) ),
              IF( -TAN(RADIANS(lat)) * TAN(RADIANS(decl)) >= 1, 0, 24) )
```
Fórmula estándar de duración del día a partir de latitud y declinación solar (ángulo horario del ocaso). El `IFERROR`/`IF` cubre los casos de sol de medianoche / noche polar (irrelevantes a estas latitudes, pero conviene replicarlos).

**Declinación solar** `[XLSX clima!I]`: `δ = 23.45 · sin( 360/365 · (día_año − 81) )` (en grados; el argumento del seno se pasa por `RADIANS`).

**Nota sobre Tm:** en la hoja `clima` la Tm figura como dato. En la hoja `fenologia` (motor de cálculo) la Tm se lee de `clima!F` `[XLSX fenologia!K2 =INDEX(clima!$F:$F,...)]`. El docx, en cambio, define `Tm = (Tx + Tn)/2` `[DOCX-fórmula]`. El desarrollador debe decidir si Tm viene dada o se recomputa (ver Duda).

**Nota sobre ETo (Hargreaves-Samani):** el docx nombra "ETo disponible" como variable de clima `[DOCX-narrativa]` y el encabezado `ETO(H-S)` `[XLSX]` indica el método Hargreaves-Samani (estima ETo de referencia a partir de temperaturas extremas y radiación extraterrestre; no requiere datos de viento/humedad). **La celda está vacía: la fórmula de ETo NO está implementada en la planilla** `[NO ESPECIFICADO]` — ver Duda bloqueante.

**Variables listadas en el docx** `[DOCX-narrativa]` (con redundancias/repeticiones del propio documento): fecha; temperaturas promedio, máxima y mínima; precipitaciones (mm); fotoperíodo; ETo disponible; y **ENSO** (categorización de campaña como Niño/Niña/Neutro según ONI de NOAA en el trimestre OND). El ENSO se describe conceptualmente pero **no aparece en ninguna hoja del xlsx** `[NO ESPECIFICADO]` — ver Duda.

### 2.2 Suelo — hoja `suelos` `[XLSX]`

Tabla **estática** (sin fórmulas) de propiedades físico-hídricas por localidad y horizonte. Dimensiones `A1:N306`. Cada localidad tiene 2–3 series de suelo; cada serie se despliega en varias filas (una por horizonte). Los atributos a nivel serie aparecen solo en la primera fila de cada serie (las demás filas los dejan en blanco = herencia).

| Columna | Encabezado | Nivel | Descripción |
|---|---|---|---|
| A | `Localidad` | serie | nombre de localidad |
| B | `Codigo` | serie | código de serie (ej. `IN54BJUA01`) |
| C | `Serie Suelo` | serie | nombre de serie |
| D | `Tipo Suelo` | serie | clasificación (ej. `PALEUDOL PETROCÁLCICO`) |
| E | `U` | serie | agua evaporable en fase 1 (mm) |
| F | `DR` | serie | factor de drenaje |
| G | `CN` | serie | Curva Número (escorrentía) |
| H | `kl` | serie | facilidad de uso (0.1 / 0.08 / 0.05) |
| I | `Um` | serie | umbral de AU bajo el cual kl decae a 0 (0.3/0.5/0.7 según textura) |
| J | `Horiz` | horizonte | nombre del horizonte (Ap, Bt, etc.) |
| K | `PFH` | horizonte | profundidad final del horizonte (cm) |
| L | `PMP` | horizonte | punto de marchitez permanente (fracción, m³/m³) |
| M | `CC` | horizonte | capacidad de campo (fracción) |
| N | `Sat` | horizonte | saturación (fracción) |

**Ejemplo (Benito Juárez, serie `Azul 80`, `PALEUDOL PETROCÁLCICO`, U=10, DR=0.6, CN=81, kl=0.1, Um=0.5):**
| Horiz | PFH(cm) | PMP | CC | Sat |
|---|---|---|---|---|
| Ap | 20 | 0.17 | 0.31 | 0.56 |
| BAt | 40 | 0.22 | 0.35 | 0.50 |
| Bt | 60 | 0.25 | 0.37 | 0.45 |
| BC | 80 | 0.15 | 0.27 | 0.41 |

**Horizontes objetivo del docx** `[DOCX-narrativa]`: 0-0.2, 0.2-0.4, 0.4-0.6, 0.6-0.9, 0.9-1.2, 1.2-1.5, 1.5-1.8, 1.8-2.1 m (la profundidad final puede ser menor en suelos someros). **Atención:** la discretización de horizontes del docx no coincide 1:1 con los `PFH` de la tabla `suelos` del ejemplo (que llega a 80 cm en 4 horizontes con cortes distintos) — ver Duda.

**Parámetros de suelo descritos en el docx** `[DOCX-narrativa]`:
- PMP, CC, Sat por horizonte.
- Escorrentía vía Curva Número (CN).
- Agua evaporable en fase 1 (U).
- Factor de drenaje (DR).
- Facilidad de uso `kl`: 0.1; 0.08 (argiudol vértico, thapto nátrico); 0.05 (vertisol). Se reduce gradualmente hasta 0 cuando el AU cae por debajo de un umbral `Um` según textura: 30% arenosos, 50% francos, 70% vérticos.

### 2.3 Cultivo y cultivar — hoja `cultivo` `[XLSX]`

Tabla de parámetros en formato largo: `cultivo | cultivar | parametro | valor | unidad | descripción`. Se lee desde `fenologia` vía `SUMIFS`. Contenido completo:

**Trigo** (cultivares: `intermedio-corto`, `intermedio-largo`):
| parámetro | cultivar | valor | unidad |
|---|---|---|---|
| Tb_a | — | 0 | °C |
| UT_S-E | — | 150 | °C |
| UT_E-fKcbIni | — | 300 | °C |
| UT_E-iKcbMax | — | 1000 | °C |
| UT_E-ET | — | 400 | °C |
| RCF | intermedio-corto | 0.7 | — |
| RCF | intermedio-largo | 0.85 | — |
| UT_ET-iPC | — | 100 | °C |
| UT_ET-fPC | — | 700 | °C |
| UT_fPC-MF | — | 400 | °C |

**Maíz** (cultivares: `templado-corto`, `templado-intermedio`, `tropial-intermedio` [sic, ver typo]):
| parámetro | cultivar | valor | unidad |
|---|---|---|---|
| Tb_a | — | 10 | °C |
| UT_S-E | — | 80 | °C |
| Tb_b | — | 8 | °C |
| UT_E-fKcbIni | — | 120 | °C |
| UT_E-iKcbMax | — | 560 | °C |
| UT_E-R2 | templado-corto | 950 | °C |
| UT_E-R2 | templado-intermedio | 1050 | °C |
| UT_E-R2 | tropial-intermedio | 1150 | °C |
| UT_E-iPC | templado-corto | 500 | °C |
| UT_E-iPC | templado-intermedio | 600 | °C |
| UT_E-iPC | tropial-intermedio | 700 | °C |
| UT_E-fPC | templado-corto | 1050 | °C |
| UT_E-fPC | templado-intermedio | 1150 | °C |
| UT_E-fPC | tropial-intermedio | 1250 | °C |
| UT_R2-MF | templado-corto | 550 | °C |
| UT_R2-MF | templado-intermedio | 650 | °C |
| UT_R2-MF | tropial-intermedio | 700 | °C |

**Soja** (cultivares: `GM 3C`, `GM 4L`, `GM 6C`):
| parámetro | cultivar | valor | unidad |
|---|---|---|---|
| Tb_a | — | 10 | °C |
| To_a | — | 27 | °C |
| UT_S-E | — | 100 | °C |
| Tb_b | — | 7 | °C |
| UT_E-fKcbIni | — | 180 | °C |
| UT_E-iKcbMax | — | 840 | °C |
| FpU_E-R1 | GM 3C | 13.5 | h |
| FpU_E-R1 | GM 4L | 13 | h |
| FpU_E-R1 | GM 6C | 12.5 | h |
| UT_E-R1 | — | 400 | °C |
| FpU_R1-MF | GM 3C | 13 | h |
| FpU_R1-MF | GM 4L | 12.5 | h |
| FpU_R1-MF | GM 6C | 12 | h |
| UT-R1-R5 | — | 300 | °C |
| UT-R5-MF | — | 800 | °C |
| UT_R1-iPC | — | 120 | °C |
| UT_R5-fPC | — | 200 | °C |

**Profundización radical y Kcb (los tres cultivos):**
| parámetro | trigo | maíz | soja | unidad |
|---|---|---|---|---|
| PR_S-E | 0.2 | 0.2 | 0.2 | m |
| PR (tasa) | 0.13 | 0.20 | 0.20 | cm/°C |
| Tb_c (raíces) | 0 | 8 | 8 | °C |
| KcbIni | 0.15 | 0.15 | 0.15 | — |
| KcbMax | 1.10 | 1.10 | 1.10 | — |

> Typo en fuente: el cultivar de maíz figura como `tropial-intermedio` (falta la "c"). Los `SUMIFS` casan por esa misma cadena, así que funciona; conviene normalizar en el nuevo script y documentar el mapeo.

### 2.4 Condiciones iniciales — hoja `condiciones iniciales` `[XLSX]`

Inputs del caso de ejemplo simulado. Estructura `variable | dato | descripción` más columnas auxiliares de selección (`localidad | omm_id | suelo`):
| variable | dato (ejemplo) |
|---|---|
| omm_id | 87480 |
| suelo | (vacío en el ejemplo) |
| cultivo | soja |
| cultivar | GM 4L |
| dda_S | 300 (día del año de siembra) |

`dda_S` = día del año de la siembra (en el ejemplo, día 300). Es el ancla temporal del motor de fenología.

**Inputs adicionales del usuario descritos en el docx** (no todos presentes en `condiciones iniciales`) `[DOCX-narrativa]`:
- **Fecha de inicio** (medición de agua): entre 1 de marzo y siembra planeada.
- **Fecha planeada de siembra**.
- **Agua inicial**: contenido de agua útil (AU) en 0-1 m (base 0-0.9), 1-2 m (0.9-2.1) y perfil 0-2.1 m. Con clases de humedad predefinidas: Seco = 10% AU, moderadamente seco = 35%, moderadamente húmedo = 65%, húmedo = 90%.
- **"Sándwich seco"** (sí/no): capa de ~30 cm con <30% AU entre 0.5 y 1.2 m. Si el usuario lo indica, se simula 10% AU entre 0.6 y 0.9 m.
- **Cobertura de rastrojos**: 0-20%, 30-50%, 80-100% (fija durante toda la simulación).

---

## 3. Outputs esperados `[DOCX-narrativa]`

1. **Eventos de lluvia** ≥ 10 mm/d en los 14 días previos y 7 días posteriores a la fecha de siembra elegida por el usuario (conteo).
2. **Contenido hídrico del suelo en la fecha de siembra:**
   - AU (%) en 0-1 m (base 0-0.9), 1-2 m (0.9-2.1) y 0-2 m (0-2.1).
   - Presencia de "sándwich seco" según el horizonte 0.6-0.9 m: si AU ≤ 30% → "sí".
3. **Confort hídrico** (escala 0-1) del cultivo durante el período crítico.

> El confort hídrico se reporta sobre el **período crítico**, cuyas fechas (iPC, fPC) salen del Paso 1. Esto vuelve críticas las dudas de fenología que mueven iPC/fPC.

---

## 4. Paso 1 — Fenología

### 4.1 Marco general `[DOCX-narrativa]`

Fenología basada en los procesos de **DSSAT**, a partir de temperatura y fotoperíodo. El efecto térmico se cuantifica por **unidades térmicas** (UT, °C) acumuladas día a día. Cada etapa de cada cultivo tiene su requerimiento térmico (UT a acumular) y su temperatura base.

- `Tm = (Tx + Tn)/2` `[DOCX-fórmula]` (en el motor xlsx la Tm se toma de `clima!F`).
- **UT diaria (base):** `UT_etapa = Σ max(0; Tm − Tb)` `[DOCX-fórmula]`.
- El fotoperíodo actúa como umbral (por debajo o por encima según cultivo) que modifica el requerimiento térmico.

**Estadios que la fenología debe fechar** (salidas `dda_*` = día del año) `[DOCX-narrativa]` / `[XLSX fenologia!A5:B14]`: emergencia (E), fin Kcb inicial, inicio Kcb máximo, hito reproductivo (ET trigo / R2 maíz / R1 soja), R2 (maíz) / R5 (soja), inicio período crítico (iPC), fin período crítico (fPC), madurez fisiológica (MF).

### 4.2 Trigo

**Biología** `[DOCX-narrativa]`: responde al fotoperíodo entre emergencia (E) y espiguilla terminal (ET); ahí radica la diferencia entre cultivares (respuesta al fotoperíodo, RCF). El cuaje de granos Z71 ocurre 700 °C después de ET, sin respuesta al fotoperíodo. Tb = 0 °C durante todo el ciclo.

**Parámetros** `[XLSX cultivo]`: `Tb_a=0`; `UT_S-E=150`; `UT_E-fKcbIni=300`; `UT_E-iKcbMax=1000`; `UT_E-ET=400`; `RCF` = 0.7 (intermedio-corto) / 0.85 (intermedio-largo); `UT_ET-iPC=100`; `UT_ET-fPC=700`; `UT_fPC-MF=400`.

**Fórmulas** (dda = día del año acumulando desde el estadio ancla):
- `UT_S-E = 150` → `dda_E = dda_S + Σ max(0; Tm − Tb_a)` `[DOCX-fórmula]` / `[XLSX]`
- `UT_E-fKcbIni = 300` → `dda_fKcbIni = dda_E + Σ max(0; Tm − Tb_a)` `[DOCX-fórmula]`
- `UT_E-iKcbMax = 1000` → `dda_iKcbMax = dda_E + Σ max(0; Tm − Tb_a)` `[DOCX-fórmula]`
- Espiguilla terminal, con respuesta a fotoperíodo `[DOCX-fórmula]` / `[XLSX col Q]`:
  `UT_E-ET = 400` → `dda_ET = dda_E + Σ [ max(0; Tm − Tb_a) · (1 − ((20 − Fp)² · 0.01 · RCF)) ]`
  El motor xlsx lo envuelve en `MAX(0, …)` para que el incremento diario nunca sea negativo (relevante si Fp se aleja mucho de 20 h — ver Duda).
- `UT_E-iPC = UT_E-ET + 100` → `dda_iPC = dda_ET + Σ max(0; Tm − Tb_a)` `[DOCX-fórmula]`
- `UT_E-fPC = UT_E-ET + 700` → `dda_fPC = dda_ET + Σ max(0; Tm − Tb_a)` `[DOCX-fórmula]`
- `UT_fPC-MF = 400` → `dda_MF = dda_fPC + Σ max(0; Tm − Tb_a)` `[DOCX-fórmula]` / `[XLSX]`

**`[DIVERGENCIA]` — la lista de pasos del docx difiere de las fórmulas y del xlsx en +100 °C** en fin de PC y madurez:
- Lista: "Fin PC: Z71 + 100 °C"; "Madurez: Z71 + 500 °C" (con Z71 = ET+700 ⇒ fPC = ET+800, MF = ET+1200).
- Fórmulas + xlsx: fPC = ET+700 (= Z71 exacto); MF = ET+1100 (= Z71+400).
- El xlsx trata Z71 y fPC como el **mismo** hito. Ver **Duda F-1 (bloqueante)**. Los valores tabulados arriba son los del xlsx (fuente de verdad operativa), pero el desarrollador NO debe codear hasta confirmar.

### 4.3 Maíz

**Biología** `[DOCX-narrativa]`: no responde al fotoperíodo. La diferencia entre cultivares está en el requerimiento térmico hasta R2 (cuaje). Tb cambia de 10 °C (S→E) a 8 °C (post-emergencia).

**Parámetros** `[XLSX cultivo]`: `Tb_a=10`; `Tb_b=8`; `UT_S-E=80`; `UT_E-fKcbIni=120`; `UT_E-iKcbMax=560`; `UT_E-R2` = 950/1050/1150 (corto/intermedio/tropical); `UT_E-iPC` = 500/600/700; `UT_E-fPC` = 1050/1150/1250; `UT_R2-MF` = 550/650/700.

**Fórmulas** `[DOCX-fórmula]` / `[XLSX]`:
- `UT_S-E = 80` → `dda_E = dda_S + Σ max(0; Tm − Tb_a)`
- `UT_E-fKcbIni = 120` → `dda_fKcbIni = dda_E + Σ max(0; Tm − Tb_b)`
- `UT_E-iKcbMax = 560` → `dda_iKcbMax = dda_E + Σ max(0; Tm − Tb_b)`
- `UT_E-R2` (según cultivar) → `dda_R2 = dda_E + Σ max(0; Tm − Tb_b)`
- `UT_E-iPC = UT_E-R2 − 450` → `dda_iPC = dda_E + ...` (ancla en E, umbral `UT_E-iPC`)
- `UT_E-fPC = UT_E-R2 + 100` → `dda_fPC = dda_E + ...`
- `UT_R2-MF` (según cultivar) → `dda_MF = dda_R2 + Σ max(0; Tm − Tb_b)`

**Coherencia verificada:** iPC = R2 − 450 y `UT_E-iPC` tabulado cierran (950−450=500 ✓); fPC = R2 + 100 cierra (950+100=1050 ✓). **Maíz no presenta divergencias de valores** entre docx y xlsx. En maíz el "hito1" y "hito2" coinciden en R2 (no hay etapa intermedia); iPC/fPC se anclan a la serie E-simple con umbrales `UT_E-iPC`/`UT_E-fPC`, no a la serie hito1→hito2.

### 4.4 Soja

**Biología** `[DOCX-narrativa]`: responde al fotoperíodo desde emergencia hasta madurez. La diferencia entre cultivares es el fotoperíodo umbral (FpU), que además cambia entre las etapas E-R1 y R1-R5. Tb cambia de 10 °C (S→E) a 7 °C (post-emergencia). Hay temperatura óptima To=27 °C: por encima de ella, la Tm efectiva se topea (`min(Tm; To)`), de modo que la acumulación no sigue creciendo.

**Parámetros** `[XLSX cultivo]`: `Tb_a=10`; `Tb_b=7`; `To_a=27`; `UT_S-E=100`; `UT_E-fKcbIni=180`; `UT_E-iKcbMax=840`; `UT_E-R1=400`; `UT-R1-R5=300`; `UT-R5-MF=800`; `UT_R1-iPC=120`; `UT_R5-fPC=200`; `FpU_E-R1` = 13.5/13/12.5 (GM 3C/4L/6C); `FpU_R1-MF` = 13/12.5/12.

**Factor fotoperiódico** (retraso cuando el día es largo): con `Fp ≤ FpU` avanza a tasa plena; con `Fp > FpU` se multiplica por `min(1; 1 − (Fp − FpU)·0.3)`.

**Fórmulas** `[DOCX-fórmula]` / `[XLSX]` (incremento diario `= max(0; min(Tm; To_a) − Tb)`; el factor Fp aplica solo en etapas con respuesta):
- `UT_S-E = 100` → `dda_E = dda_S + Σ max(0; min(Tm; To_a) − Tb_a)`
- `UT_E-fKcbIni = 180` → `dda_fKcbIni = dda_E + Σ max(0; min(Tm; To_a) − Tb_b)`
- `UT_E-iKcbMax = 840` → `dda_iKcbMax = dda_E + Σ max(0; min(Tm; To_a) − Tb_b)`
- E→R1 (`UT_E-R1 = 400`, umbral FpU_E-R1): si Fp ≤ FpU → incremento pleno; si Fp > FpU → `× min(1; 1 − (Fp − FpU)·0.3)`.
- R1→R5 (`UT-R1-R5 = 300`, umbral FpU_R1-MF): misma lógica de factor.
- `UT_R1-iPC = 120` → `dda_iPC = dda_R1 + ...` (serie R1→R5, con FpU_R1-MF). Equivale numéricamente a R5 − 180 (dado UT-R1-R5=300). Ver Duda F-3.
- `UT_R5-fPC = 200` → `dda_fPC = dda_R5 + ...`
- `UT-R5-MF = 800` → `dda_MF = dda_R5 + ...`

**Notas:** el docx (lista de pasos) también describe iPC como "R5 − 180 °C" y fPC como "R5 + 200 °C"; numéricamente consistente con la implementación (ancla R1+120). En el ejemplo, R5/fPC/MF caen en el año calendario siguiente, por lo que sus `dda_*` (13, 31, 74) son días-del-año del año siguiente, no días desde siembra (ver Duda F-4, presentación).

---

## 5. Paso 2 — Profundización radical

**Descripción** `[DOCX-narrativa]`: crecimiento radicular diario a partir de una tasa por unidad térmica (crecimiento **potencial**; las limitaciones por suelo seco se aplican en el Paso 4).

**Reglas** `[DOCX-narrativa]` / `[XLSX cultivo]`:
1. **Siembra → Emergencia:** profundidad constante = **0.20 m** (`PR_S-E`), igual para los tres cultivos.
2. **Desde emergencia** hasta alcanzar la profundidad máxima del suelo **o** el cuaje de granos (trigo Z71, maíz R2, soja R5), lo que ocurra primero, la tasa (`PR`, cm/°C) es:
   - Trigo: **0.13 cm/°C**, con `Tb_c = 0 °C`.
   - Maíz: **0.20 cm/°C**, con `Tb_c = 8 °C`.
   - Soja: **0.20 cm/°C**, con `Tb_c = 8 °C`.
3. Con un horizonte a <30% AU, la tasa se reduce gradualmente hasta 0 cm/°C a 0% AU (esto **se aplica en el Paso 4**, no en el potencial).

**Implementación (columna X de `fenologia`)** `[XLSX]`:
```
X = IF(día < fila_E,               PR_S-E,
     IF(día <= fila_hito2,          PR_S-E + (PR · V)/100,
                                    PR_S-E + (PR · INDEX(V, fila_hito2))/100))
```
donde `V` = UT acumuladas para raíces (serie con `Tb_c`, columna V; el incremento diario U = `max(0; Tm − Tb_c)` solo entre emergencia `fila_E` y cuaje `fila_hito2`). La división por 100 convierte cm→m (PR está en cm/°C, PR_S-E y X en m). Antes de emergencia X = 0.20 m; después del cuaje X se congela en el valor alcanzado en `fila_hito2`.

> La versión de la columna X es el **potencial** (no incluye la limitación por suelo seco del punto 3, que pertenece al Paso 4 no implementado).

---

## 6. Paso 3 — Curva de Kcb

**Descripción** `[DOCX-narrativa]`: se define la curva de Kcb (coeficiente basal de cultivo — componente de transpiración del enfoque **Kcb dual** de FAO-56, que separa transpiración del cultivo de evaporación del suelo) a partir de la fenología simulada.

**Reglas** `[DOCX-narrativa]` / `[XLSX cultivo]`:
1. `Kcb inicial = 0.15` (los tres cultivos), desde emergencia hasta fin Kcb inicial.
2. `Kcb máximo = 1.10` (los tres cultivos), desde inicio Kcb máximo hasta madurez fisiológica.
3. Entre fin Kcb inicial e inicio Kcb máximo, incremento **lineal** en función de las UT acumuladas `[DOCX-narrativa Paso 1]`.

**Implementación (columna Y de `fenologia`)** `[XLSX]`:
```
Y = IF(día < fila_E,                       0,
     IF(P <= UT_E-fKcbIni,                 KcbIni,
       IF(P >= UT_E-iKcbMax,               KcbMax,
          KcbIni + (KcbMax − KcbIni)·(P − UT_E-fKcbIni)/(UT_E-iKcbMax − UT_E-fKcbIni))))
```
donde `P` = UT acumuladas de la serie E-simple (columna P, base `Tb_b`, o `Tb_a` en trigo). Antes de emergencia Kcb = 0; luego se mantiene en 0.15 hasta `UT_E-fKcbIni`, interpola linealmente hasta `UT_E-iKcbMax`, y se mantiene en 1.10 en adelante (hasta MF).

> Observación: la columna Y interpola con la serie P (UT desde emergencia sin ajuste de fotoperíodo). No hay una rampa descendente de Kcb hacia la senescencia en las fuentes (Kcb queda en 1.10 hasta MF).

---

## 7. Paso 4 — Balance hídrico diario

> **ESTADO CRÍTICO:** el Paso 4 está esencialmente **NO especificado y NO implementado**. El docx corta abruptamente (documento de trabajo incompleto) y la hoja `balance hídrico` del xlsx está **completamente vacía** (`A1:A1`, sin fórmulas ni datos) `[XLSX]`. Solo existe la fórmula de Escorrentía y una lista de sub-pasos sin desarrollar. Esto es lo más bloqueante del proyecto.

### 7.1 Marco conceptual `[DOCX-narrativa]`

Balance en función de oferta y demanda de agua, con cálculo de **pase diario** usando el día actual (d0) y el previo (d−1):
- **Oferta:** agua inicial del suelo (usuario) + precipitaciones diarias (clima) + capacidad de extracción por raíces.
- **Demanda:** principalmente evapotranspiración potencial (ETo de clima × curva de Kcb).

### 7.2 Sub-pasos del pase diario `[DOCX-narrativa]` — estado de especificación

Lista textual del docx (misma lista dos veces en el documento), con el estado de cada uno:

| # | Sub-paso | Descripción del docx | Estado |
|---|---|---|---|
| a | Agua en cada horizonte (día previo) | útil y sobre CC | `[NO ESPECIFICADO]` (fórmula) |
| b | Prof. radical | suma térmica y % agua en horizonte de avance | Potencial en Paso 2; limitación por sequía **no especificada** |
| c | Llueve | Pp diaria de clima | dato de entrada (sin transformación) |
| d | **Escurre (CN)** | Escorrentía por Curva Número | **ÚNICO con fórmula** (abajo) |
| e | Infiltra | "llena a saturación todo" | `[NO ESPECIFICADO]` — solo la frase, sin fórmula |
| f | Transpira | "agua explorada por raíces más los mm que infiltran" | `[NO ESPECIFICADO]` — solo la frase |
| g | Evapora | — | `[NO ESPECIFICADO]` — sin descripción ni fórmula |
| h | Drena | — (existe parámetro DR en `suelos`) | `[NO ESPECIFICADO]` — sin fórmula |
| i | Agua al final del día en cada horizonte | cierre del balance por horizonte | `[NO ESPECIFICADO]` — sin fórmula |

### 7.3 Escorrentía — ÚNICA fórmula disponible `[DOCX-fórmula]`

Texto literal del docx (Paso 4, punto 2): la escorrentía (Esc, mm) usa el CN del suelo elegido, las constantes hídricas de los primeros 20 cm, el nivel de cobertura del suelo (constante), y la precipitación diaria (Pp). Fórmula tal como aparece:

```
Esc (mm) = max(Pp − Absi · AtM, 0)² / (Pp + AtM · (1 − Absi))
```

**Variables** (según el texto; algunas quedan sin definición completa por el corte del documento):
- `Pp` = precipitación diaria (mm) `[DOCX]`.
- `AtM` = almacenamiento/retención potencial máximo, ligado al CN. **El docx no da la fórmula que conecta AtM con CN** `[NO ESPECIFICADO]` — es la S del método SCS-CN (`S = 25400/CN − 254` en mm), pero eso es conocimiento general, NO está escrito en las fuentes.
- `Absi` = coeficiente de abstracción inicial (Ia = Absi·S). **No definido numéricamente en las fuentes** `[NO ESPECIFICADO]` — el valor clásico SCS es 0.2, pero no figura en el docx/xlsx.
- Se menciona además el uso de las constantes hídricas de los primeros 20 cm y el nivel de cobertura del suelo, pero **la fórmula escrita no muestra explícitamente cómo entran** (la frase queda cortada: "...y las constantes hídricas de" — fin del documento) `[NO ESPECIFICADO]`.

> La estructura de la fórmula corresponde al método **SCS Curve Number** (escorrentía = `(P − Ia)² / (P − Ia + S)` con `Ia = 0.2·S`). El desarrollador la reconocerá, pero los parámetros `AtM`/`Absi` y su relación con CN, cobertura y humedad de los primeros 20 cm **deben ser confirmados por el experto** porque no están numéricamente cerrados en las fuentes.

### 7.4 Lo que NO está en ninguna fuente (marcado explícito) `[NO ESPECIFICADO]`

- Fórmula de **Infiltración** (más allá de "llena a saturación todo").
- Fórmula de **Transpiración** (reparto de la demanda entre horizontes explorados por raíces; uso de `kl`, `Um`, del Kcb y de la ETo).
- Fórmula de **Evaporación** (fase 1 con `U`; rol de la cobertura de rastrojos; agua evaporable).
- Fórmula de **Drenaje** (uso del factor `DR`; redistribución entre horizontes; drenaje por debajo del perfil).
- Fórmula de **Agua al final del día por horizonte** (cierre del balance).
- Cómo se calcula el **confort hídrico (0-1)** del período crítico (output 3) a partir del balance.
- Cómo se aplica la **limitación por sequía a la profundización radical** (Paso 2 punto 3).
- Cómo se calcula/deriva la **ETo (Hargreaves-Samani)** (columna `ETO(H-S)` vacía).

**Ningún desarrollador puede completar el Paso 4 ni los outputs 2 y 3 sin definiciones adicionales del experto.**

---

## 8. Apéndice — Detalle técnico de implementación en Excel

Motor de cálculo real = hoja **`fenologia`**. Traduce parámetros de `cultivo`/`condiciones iniciales` y la serie `clima` en fechas fenológicas + curvas de raíz y Kcb.

### 8.1 Bloque de salidas (A:B, filas 2-14)
- `B2 = 'condiciones iniciales'!B4` (cultivo), `B3 = ...!B5` (cultivar), `B4 = ...!B6` (`dda_S`).
- `B5:B14` = fechas fenológicas (día del año), resueltas con COUNTIFS+INDEX (patrón abajo). Cada una filtra por cultivo con `IF($B$2="trigo"/"maiz"/"soja", ...)` para devolver "" cuando no aplica (p. ej. `dda_ET` solo para trigo, `dda_R2` solo maíz, `dda_R1`/`dda_R5` solo soja).

### 8.2 Bloque de parámetros derivados (E:F, filas 2-42)
Lee la hoja `cultivo` con `SUMIFS(cultivo!D:D, cultivo!A:A, $B$2, cultivo!C:C, "<param>")`, filtrando además por cultivar (`cultivo!B:B = $B$3`) para RCF, UT_E-R2, FpU, etc. Índices de fila clave:
- `F26 = fila_S = MATCH($B$4, clima!$C$2:$C$548, 0) + 1` → fila en `clima` de la siembra.
- `F27 = fila_E = F26 + COUNTIFS(...serie S→E supera UT_S-E...)` → fila de emergencia.
- `F28 = fila_hito1` (ET trigo / R1 soja / R2 maíz) → primera fila donde la serie E→hito1 supera su umbral.
- `F42 = fila_hito2 / fila_granoCuaje` = cuaje (Z71=fPC trigo / R2 maíz / R5 soja); marca el fin del crecimiento potencial de raíz.

### 8.3 Tabla auxiliar día a día (H:Y, filas 2-501)
Una fila por día desde la siembra (máx. ~500 días). Encabezados:
`n | fila_clima | día_año | Tm | Fp | incr S→E | acum S→E | incr E→simple | acum E→simple | incr E→hito1 | acum E→hito1 | incr hito1→hito2 | acum hito1→hito2 | incr raíz(Tbc) | acum raíz(Tbc) | n(días desde siembra) | Profundidad radical (m) | Kcb`

Fórmulas clave (fila 2; la fila 3+ replica con acumulación):
- `H = n` (0,1,2,…); `I = F26 + H` (fila en `clima`); `J = INDEX(clima!C:C, I)` (día_año); `K = INDEX(clima!F:F, I)` (Tm); `L = INDEX(clima!J:J, I)` (Fp).
- **Serie S→E (M incr / N acum):** `M = max(0, (IF soja: min(K,To_a) else K) − Tb_a)`; `N` acumula.
- **Serie E-simple (O/P):** activa solo si `I ≥ F27` (post-emergencia): `O = max(0, (IF soja: min(K,To_a) else K) − Tb_b)`; `P` acumula. Es la serie usada para fin/inicio Kcb (columna Y).
- **Serie E→hito1 (Q/R):** post-emergencia, con la regla de fotoperíodo por cultivo:
  - Trigo: `max(0, max(0, K − Tb_a) · (1 − ((20 − L)² · 0.01 · RCF)))`.
  - Maíz: `max(0, K − Tb_b)` (sin Fp).
  - Soja: si `L ≤ FpU_E-R1` → `max(0, min(K,To_a) − Tb_b)`; si no → `× min(1, 1 − (L − FpU_E-R1)·0.3)`.
- **Serie hito1→hito2 (S/T):** activa si `I ≥ F28`:
  - Trigo: `max(0, K)`.
  - Soja: análoga a Q pero con `FpU_R1-MF` (F19).
  - Maíz: 0 (no se usa; hito1=hito2).
- **Serie raíz (U/V):** `U = IF(F27 ≤ I ≤ F42, max(0, K − Tb_c), 0)`; `V` acumula. Solo entre emergencia y cuaje.
- **Profundidad radical (X):** ver Sección 5.
- **Kcb (Y):** ver Sección 6.

### 8.4 Resolución de fechas: COUNTIFS + INDEX
Patrón general de cada `dda_*`:
```
IFERROR(
  IF( fila_ancla + COUNTIFS(rango_n, ">="&fila_ancla, rango_serie_acum, "<"&umbral_UT) > 548,
      "Datos insuficientes",
      INDEX(clima!$C:$C, fila_ancla + COUNTIFS(...)) ),
  "Sin datos")
```
- `COUNTIFS(...)` cuenta cuántas filas de la serie acumulada están **por debajo** del umbral desde la fila ancla → nº de días hasta cruzar el umbral.
- `fila_ancla + ese conteo` = fila en `clima` del estadio → `INDEX(clima!C:C, ...)` devuelve el día del año.
- Esto **respeta el cruce de año calendario** (por eso R5/fPC/MF de soja aparecen como días-del-año del año siguiente).
- Guardas: `> 548` → "Datos insuficientes"; `IFERROR` → "Sin datos". La tabla auxiliar solo llega a la fila 501 (~500 días desde siembra). Ver Duda G-1.

### 8.5 Linkeo entre hojas
- `condiciones iniciales` → `fenologia!B2:B4` (cultivo, cultivar, dda_S).
- `cultivo` → `fenologia!E:F` (parámetros, vía SUMIFS por cultivo+cultivar).
- `clima` → `fenologia` (Tm, día_año, Fp, vía INDEX por número de fila).
- `suelos` → **no linkeada** al motor de fenología (solo relevante para el Paso 4, no implementado).
- `balance hídrico` → **vacía**.

---

# SECCIÓN 2 — Dudas para el experto

Prioridad: **[BLOQUEANTE]** = sin esto no se puede codear el script; **[IMPORTANTE]** = necesario para exactitud del resultado; **[MENOR]** = prolijidad/presentación.

> Nota: el documento fuente (docx) está inconcluso — desarrolla con fórmulas completas los Pasos 1-3 (fenología, profundización radical, curva Kcb) pero corta a mitad del Paso 4 (balance hídrico diario). Por eso las dudas se separan en dos bloques con naturaleza distinta: (a) dudas puntuales sobre pasos que SÍ están desarrollados, y (b) todo lo que falta desarrollar del resto del método.

---

## a) Dudas sobre Pasos 1-3 (Fenología, Profundización radical, Curva Kcb)

Estos tres pasos están desarrollados y mayormente implementados en el xlsx. Las dudas acá son puntuales: divergencias numéricas concretas o detalles a confirmar, no vacíos de método.

### Fenología

**F-1 [BLOQUEANTE para trigo] — Trigo: +100 °C de divergencia en fin de período crítico y madurez.**
- *Qué se sabe:* lista de pasos dice fPC = Z71+100 y MF = Z71+500; fórmulas + xlsx dan fPC = Z71 (ET+700) y MF = Z71+400 (ET+1100). El xlsx trata Z71 y fPC como el mismo hito.
- *Qué falta/contradice:* diferencia sistemática de +100 °C en dos estadios clave.
- *Por qué bloquea:* fPC define el fin del período crítico (sobre el que se reporta el confort hídrico) y MF define hasta dónde corre la simulación. Hipótesis: la lista tiene errata; el xlsx es la fuente de verdad. **Confirmar la tabla canónica de trigo.**

**F-2 [MENOR] — Trigo: doble parametrización de iPC (Z71−600 vs ET+100).**
- *Qué se sabe:* ambas dan iPC = ET+100 (coinciden).
- *Qué falta:* solo elegir una definición canónica (todo relativo a ET o todo a Z71) para evitar confusión.
- *Por qué:* prolijidad; no cambia valores.

**F-3 [MENOR] — Soja: iPC como R1+120 vs R5−180.**
- *Qué se sabe:* coinciden numéricamente solo si UT-R1-R5 = 300 (120 = 300−180). El xlsx ancla en R1+120.
- *Qué falta:* confirmar que UT-R1-R5 siempre valdrá 300; si cambiara, definir cuál manda.
- *Por qué:* robustez ante cambio de parámetros.

**F-4 [MENOR/presentación] — Salida de fechas: día-del-año vs fecha absoluta.**
- *Qué se sabe:* `dda_*` devuelve día del año; con siembra tardía, R5/fPC/MF caen en el año siguiente (ej. 13, 31, 74) y parecen anteriores a la siembra (300).
- *Qué falta:* definir el formato de salida (fecha absoluta o días desde siembra) para no confundir el orden.
- *Por qué:* presentación; el cálculo es correcto.

**F-5 [IMPORTANTE] — Trigo: comportamiento del factor fotoperiódico con Fp lejano a 20 h.**
- *Qué se sabe:* factor `(1 − ((20−Fp)²·0.01·RCF))` sin umbral (continuo); el xlsx lo envuelve en `MAX(0,…)`, truncando el incremento diario a 0 con Fp muy largo.
- *Qué falta:* confirmar el rango válido de Fp y si el truncado a 0 es intencional (si no, el trigo podría "dejar de acumular" hacia ET).
- *Por qué importa:* afecta la fecha de ET y por cascada todo el ciclo del trigo.

**F-6 [IMPORTANTE] — Fotoperíodo "por debajo o por encima según cultivo": mecanismos distintos.**
- *Qué se sabe:* trigo = función cuadrática continua centrada en 20 h; soja = umbral discreto con penalización lineal (0.3). El docx los describe con la misma frase genérica.
- *Qué falta:* validar que ambos mecanismos son los deseados y documentar la dirección del efecto en cada cultivo.
- *Por qué importa:* define la respuesta fotoperiódica, central en trigo y soja.

**F-7 [MENOR] — Definición de Tm: dada vs recomputada.**
- *Qué se sabe:* docx define Tm=(Tx+Tn)/2; el motor lee `clima!F` (Tm ya provista).
- *Qué falta:* decidir si el nuevo script recomputa Tm o confía en la columna provista.
- *Por qué:* coherencia; puede haber diferencias si la Tm de la base no es el promedio de extremos.

### Profundización radical

**PR-1 [IMPORTANTE] — Congelamiento post-cuaje y unidades.**
- *Qué se sabe:* X congela la profundidad en `fila_hito2` (cuaje); PR en cm/°C, X/PR_S-E en m, con `/100`.
- *Qué falta:* confirmar que la raíz no crece más después del cuaje y que no debe topearse contra la profundidad máxima del suelo dentro del propio Paso 2 (el docx dice "hasta la prof. máxima del suelo o el cuaje, lo que ocurra primero", pero la columna X no aplica el tope de profundidad del suelo explícitamente).
- *Por qué importa:* la profundidad efectiva define el agua explorable.

**PR-2 [MENOR] — Ver BH-5** (limitación por sequía; pertenece al Paso 4, sección b).

### Curva Kcb

**KC-2 [MENOR] — Serie usada para interpolar.**
- *Qué se sabe:* la columna Y interpola con la serie P (E-simple, sin ajuste de Fp).
- *Qué falta:* confirmar que la rampa de Kcb debe basarse en UT sin corrección fotoperiódica (y no en la serie con Fp).
- *Por qué:* consistencia interna.

---

## b) Dudas del resto (Balance hídrico diario, datos de soporte, generales)

Acá se agrupa todo lo que corresponde a partes del método que el docx no llegó a desarrollar (quedó cortado) o que son datos de soporte/generales no ligados directamente al motor de fenología. Son las dudas de mayor volumen y las más bloqueantes del documento.

### Balance hídrico diario (Paso 4) — las más bloqueantes

**BH-1 [BLOQUEANTE] — El Paso 4 completo no está especificado ni implementado.**
- *Qué se sabe:* marco conceptual (oferta/demanda, pase diario d0/d−1) y la lista de sub-pasos (a–i). Solo Escorrentía tiene fórmula.
- *Qué falta:* fórmulas de Infiltración, Transpiración, Evaporación, Drenaje y Agua-final-por-horizonte. La hoja `balance hídrico` está vacía.
- *Por qué bloquea:* es el núcleo de la herramienta; sin esto no hay balance hídrico, ni outputs 2 (contenido hídrico) ni 3 (confort hídrico).

**BH-2 [BLOQUEANTE] — Parámetros de la fórmula de escorrentía (AtM, Absi) sin definir.**
- *Qué se sabe:* `Esc = max(Pp − Absi·AtM, 0)² / (Pp + AtM·(1−Absi))`, usa CN, constantes hídricas de los 20 cm y cobertura.
- *Qué falta:* la relación AtM↔CN, el valor de Absi, y cómo entran las constantes hídricas de los primeros 20 cm y la cobertura de rastrojos (la frase del docx queda cortada). El valor SCS clásico (Absi=0.2, S=25400/CN−254) NO está escrito en las fuentes.
- *Por qué bloquea:* sin cerrar estos parámetros la escorrentía no es computable de forma reproducible.

**BH-3 [BLOQUEANTE] — ETo (Hargreaves-Samani) no implementada.**
- *Qué se sabe:* el docx pide "ETo disponible"; el encabezado `ETO(H-S)` indica el método.
- *Qué falta:* la celda `clima!K` está vacía; no hay fórmula de ETo. La demanda del balance depende de ETo × Kcb.
- *Por qué bloquea:* sin ETo no hay demanda evapotranspirativa → no hay balance.

**BH-4 [BLOQUEANTE] — Cálculo del confort hídrico (0-1).**
- *Qué se sabe:* es un output sobre el período crítico.
- *Qué falta:* no hay fórmula ni definición operativa (¿ratio transpiración real/potencial acumulado en iPC–fPC?).
- *Por qué bloquea:* es uno de los tres outputs y no puede derivarse de lo disponible.

**BH-5 [IMPORTANTE] — Limitación de la profundización radical por sequía.**
- *Qué se sabe:* con horizonte <30% AU la tasa decae linealmente hasta 0 a 0% AU; "se modifica en el Paso 4".
- *Qué falta:* la fórmula exacta de reducción y sobre qué horizonte se evalúa (el de avance).
- *Por qué importa:* afecta la profundidad radical efectiva y, por lo tanto, el agua explorable y la transpiración.

**BH-6 [IMPORTANTE] — Estructura de horizontes del balance vs tabla `suelos`.**
- *Qué se sabe:* el docx define horizontes 0-0.2/0.2-0.4/…/1.8-2.1 m; la tabla `suelos` tiene PFH propios (ej. 20/40/60/80 cm) que no coinciden 1:1.
- *Qué falta:* cómo se mapean/interpolan las constantes hídricas de `suelos` a la discretización del balance; qué hacer en suelos someros.
- *Por qué importa:* define la geometría del balance por capa.

**BH-7 [IMPORTANTE] — Uso de `kl`, `Um`, `U`, `DR` y cobertura en las fórmulas.**
- *Qué se sabe:* `suelos` provee kl (facilidad de uso), Um (umbral), U (agua evaporable fase 1), DR (factor de drenaje); la cobertura de rastrojos es un input.
- *Qué falta:* las ecuaciones donde intervienen (transpiración, evaporación, drenaje). No están escritas.
- *Por qué importa:* son parámetros provistos pero sin uso definido.

### Curva Kcb — vacío no cubierto por ninguna fuente

**KC-1 [IMPORTANTE] — Ausencia de rampa descendente / senescencia.**
- *Qué se sabe:* Kcb sube 0.15→1.10 y se mantiene en 1.10 hasta MF (no baja).
- *Qué falta:* no hay ninguna mención, en docx ni en xlsx, de un decaimiento de Kcb en la fase final (en FAO-56 dual habitualmente Kcb desciende hacia la madurez). Es un vacío total, no una divergencia entre fuentes.
- *Por qué importa:* afecta la demanda transpirativa en la fase final del ciclo.

### Datos de soporte / suelos / clima

**DS-1 [IMPORTANTE] — Cobertura de agua inicial y "sándwich seco".**
- *Qué se sabe:* clases de humedad (10/35/65/90% AU) y regla de sándwich (10% AU entre 0.6-0.9 m).
- *Qué falta:* cómo se traduce el AU% informado por metro (0-1, 1-2, 0-2.1) al contenido inicial por horizonte del balance.
- *Por qué importa:* define la condición inicial del Paso 4.

**DS-2 [IMPORTANTE] — ENSO descrito pero no presente en datos.**
- *Qué se sabe:* el docx define categorización ENSO (ONI OND). No aparece en ninguna hoja del xlsx.
- *Qué falta:* si el ENSO se usa en el cálculo o es solo para selección/segmentación de campañas climatológicas.
- *Por qué importa:* podría condicionar qué años de clima entran en la simulación.

**DS-3 [MENOR] — Herencia de atributos de serie en la tabla `suelos`.**
- *Qué se sabe:* los atributos de serie (U, DR, CN, kl, Um) solo figuran en la primera fila de cada serie; el resto de horizontes los deja en blanco.
- *Qué falta:* confirmar que el parser debe propagar (forward-fill) esos valores a los horizontes de la misma serie.
- *Por qué:* correcta lectura de la tabla.

### Generales

**G-1 [IMPORTANTE] — Ventana de 500 filas y "Datos insuficientes".**
- *Qué se sabe:* la tabla auxiliar corre hasta la fila 501 (~500 días); las fórmulas devuelven "Datos insuficientes" si superan la fila 548 de `clima`.
- *Qué falta:* garantizar que ningún cultivar/fecha de siembra válida quede sin resolver; definir el comportamiento esperado en el borde.
- *Por qué importa:* robustez para ciclos largos / siembras tardías.

**G-2 [MENOR] — Typo `tropial-intermedio` en `cultivo`.**
- *Qué se sabe:* el cultivar de maíz está mal escrito; los SUMIFS casan igual.
- *Qué falta:* normalizar la cadena en el nuevo script.
- *Por qué:* prolijidad.

**G-3 [MENOR] — Salidas del Paso 5 ("Salidas") no desarrolladas.**
- *Qué se sabe:* el docx lista "Salidas" como Paso 5 pero no lo desarrolla más allá de los outputs generales.
- *Qué falta:* la lógica de agregación temporal/espacial de los outputs (climatología >30 años, reporte por campaña, etc.).
- *Por qué:* define la capa de reporte final.
