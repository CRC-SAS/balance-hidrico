// Mapas nivel (codigo interno, el que espera la API / inst/extdata/
// constantes.yml) -> etiqueta (lo que ve el usuario). Copiados 1:1 de la
// hoja `equivalencias` de base_datos_balance_hidrico.xlsx. Hardcodeados
// a proposito (decision del usuario) -- no salen de la SQLite.
//
// Ojo con cantidad_rastrojo: el codigo interno es "Muy_Alta" (guion bajo,
// el que usa inst/extdata/constantes.yml) pero la etiqueta que ve el
// usuario es "Muy Alta" (con espacio, como esta en el xlsx original).
export interface Nivel {
  codigo: string;
  etiqueta: string;
}

export const CANTIDAD_RASTROJO: Nivel[] = [
  { codigo: "Baja", etiqueta: "Baja" },
  { codigo: "Moderada", etiqueta: "Moderada" },
  { codigo: "Muy_Alta", etiqueta: "Muy Alta" },
];

// Mismos niveles para au_m1 y au_m2 (misma tabla `humedad_inicial` de
// inst/extdata/constantes.yml aplicada a cada metro por separado).
export const HUMEDAD_INICIAL: Nivel[] = [
  { codigo: "Se", etiqueta: "Seco" },
  { codigo: "mS", etiqueta: "Moderadamente seco" },
  { codigo: "mH", etiqueta: "Moderadamente húmedo" },
  { codigo: "Hu", etiqueta: "Húmedo" },
];

export const SANDWICH_SECO: Nivel[] = [
  { codigo: "Si", etiqueta: "Sí" },
  { codigo: "No", etiqueta: "No" },
];

export const MESES: { valor: number; nombre: string }[] = [
  { valor: 1, nombre: "Enero" },
  { valor: 2, nombre: "Febrero" },
  { valor: 3, nombre: "Marzo" },
  { valor: 4, nombre: "Abril" },
  { valor: 5, nombre: "Mayo" },
  { valor: 6, nombre: "Junio" },
  { valor: 7, nombre: "Julio" },
  { valor: 8, nombre: "Agosto" },
  { valor: 9, nombre: "Septiembre" },
  { valor: 10, nombre: "Octubre" },
  { valor: 11, nombre: "Noviembre" },
  { valor: 12, nombre: "Diciembre" },
];

// Etiquetas de las variables de salida (para la tabla de resultado) --
// mismos nombres que devuelve api/agregar_salidas.R.
export const VARIABLE_SALIDA_LABELS: Record<string, string> = {
  eventos_lluvia_10mm_14a_7d_siembra: "Eventos de lluvia ≥10mm (14 días antes / 7 después de la siembra)",
  au_pct_m1: "Agua útil — 1er metro (%)",
  au_pct_m2: "Agua útil — 2do metro (%)",
  au_pct_total: "Agua útil — total (%)",
  confort_hidrico: "Confort hídrico — período crítico (%)",
};
