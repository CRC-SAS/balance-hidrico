import { NextRequest, NextResponse } from "next/server";
import { getCultivaresPorCultivo } from "@/lib/db";

// Sirve la cascada Cultivo -> Cultivares de UI Entrada, leyendo la
// SQLite directo (mismo criterio que /api/suelos).
export async function GET(req: NextRequest) {
  const cultivo = req.nextUrl.searchParams.get("cultivo");
  if (!cultivo) {
    return NextResponse.json({ error: "Falta el parametro 'cultivo'" }, { status: 400 });
  }
  return NextResponse.json({ cultivares: getCultivaresPorCultivo(cultivo) });
}
