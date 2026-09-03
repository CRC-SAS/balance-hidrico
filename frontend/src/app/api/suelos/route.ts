import { NextRequest, NextResponse } from "next/server";
import { getEstacionYSuelosPorLocalidad } from "@/lib/db";

// Sirve la cascada Localidad -> Suelos de UI Entrada, leyendo la SQLite
// directo (no pasa por la API R/plumber -- ese servicio solo corre la
// simulacion en si, ver POST /api/simular).
export async function GET(req: NextRequest) {
  const localidad = req.nextUrl.searchParams.get("localidad");
  if (!localidad) {
    return NextResponse.json({ error: "Falta el parametro 'localidad'" }, { status: 400 });
  }
  try {
    return NextResponse.json(getEstacionYSuelosPorLocalidad(localidad));
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 404 });
  }
}
