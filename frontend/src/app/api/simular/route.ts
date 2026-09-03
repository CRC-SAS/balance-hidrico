import { NextRequest, NextResponse } from "next/server";
import type { EscenarioInput } from "@/lib/types";

// Proxy server-side a la API R/plumber (POST /simular). El browser
// nunca le pega directo a la API -- llama a esta ruta, que reenvia el
// pedido con la URL interna (docker-compose: http://api:8000, dev local:
// http://localhost:8000 por default).
const API_URL = process.env.API_URL ?? "http://localhost:8000";

export async function POST(req: NextRequest) {
  const body = (await req.json()) as EscenarioInput;

  let res: Response;
  try {
    res = await fetch(`${API_URL}/simular`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch {
    return NextResponse.json(
      { error: "No se pudo conectar con el servicio de simulación" },
      { status: 502 }
    );
  }

  const data = await res.json();
  return NextResponse.json(data, { status: res.status });
}
