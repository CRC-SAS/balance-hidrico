// Tipos compartidos del contrato con la API R/plumber (POST /simular,
// ver api/plumber.R en la raiz del repo).
export interface EscenarioInput {
  estacion: number;
  suelo: string;
  cultivo: string;
  cultivar: string;
  siembra: { dia: number; mes: number };
  monitoreo: { dia: number; mes: number };
  cantidad_rastrojo: string;
  au_m1: string;
  au_m2: string;
  sandwich_seco: string;
}

export interface EstadisticaVariable {
  variable: string;
  media: number;
  p20: number;
  p50: number;
  p80: number;
  desvio: number;
  iqr: number;
}

export interface AnioResultado {
  anio: number;
  eventos_lluvia_10mm_14a_7d_siembra: number;
  au_pct_m1: number;
  au_pct_m2: number;
  au_pct_total: number;
  sandwich_seco: string;
  confort_hidrico: number;
}

export interface ResultadoSimulacion {
  anios_simulados: number;
  anios_con_error: number;
  salidas: {
    siembra: EstadisticaVariable[];
    cultivo: EstadisticaVariable[];
  };
  anios: AnioResultado[];
}

export interface ErrorApi {
  error: string;
}
