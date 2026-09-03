// Acceso de solo lectura a balance_hidrico.sqlite (ver
// scripts/construir_base_datos.R en la raiz del repo) para servir el
// catalogo de la plataforma (localidades, suelos, cultivos, cultivares)
// -- la simulacion en si la corre la API R/plumber, este modulo nunca
// llama a esa API, solo lee la SQLite directo (decision del usuario:
// "el catalogo se deberia leer de la base SQLite").
import Database from "better-sqlite3";
import path from "node:path";

const RUTA_SQLITE =
  process.env.BALANCE_HIDRICO_SQLITE ??
  path.join(process.cwd(), "..", "balance_hidrico.sqlite");

let _db: Database.Database | null = null;

function db(): Database.Database {
  if (!_db) {
    _db = new Database(RUTA_SQLITE, { readonly: true, fileMustExist: true });
  }
  return _db;
}

export interface Localidad {
  localidad: string;
  ommId: number;
  nombreEstacion: string;
}

export function getLocalidades(): Localidad[] {
  return db()
    .prepare(
      "SELECT DISTINCT localidad, omm_id as ommId, nombre as nombreEstacion FROM estaciones ORDER BY localidad"
    )
    .all() as Localidad[];
}

export interface Suelo {
  suelo: string;
  tipoSuelo: string | null;
  serieSuelo: string | null;
}

export interface EstacionYSuelos {
  ommId: number;
  suelos: Suelo[];
}

export function getEstacionYSuelosPorLocalidad(localidad: string): EstacionYSuelos {
  const estacion = db()
    .prepare("SELECT omm_id as ommId FROM estaciones WHERE localidad = ?")
    .get(localidad) as { ommId: number } | undefined;
  if (!estacion) {
    throw new Error(`Localidad '${localidad}' no encontrada`);
  }
  const suelos = db()
    .prepare(
      "SELECT suelo, tipo_suelo as tipoSuelo, serie_suelo as serieSuelo FROM suelos WHERE localidad = ? ORDER BY suelo"
    )
    .all(localidad) as Suelo[];
  return { ommId: estacion.ommId, suelos };
}

export function getCultivos(): string[] {
  const rows = db()
    .prepare("SELECT DISTINCT cultivo FROM cultivares ORDER BY cultivo")
    .all() as { cultivo: string }[];
  return rows.map((r) => r.cultivo);
}

export function getCultivaresPorCultivo(cultivo: string): string[] {
  const rows = db()
    .prepare(
      "SELECT DISTINCT cultivar FROM cultivares WHERE cultivo = ? AND cultivar IS NOT NULL ORDER BY cultivar"
    )
    .all(cultivo) as { cultivar: string }[];
  return rows.map((r) => r.cultivar);
}
