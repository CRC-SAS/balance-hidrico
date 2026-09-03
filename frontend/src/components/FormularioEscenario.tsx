"use client";

import { useEffect, useState } from "react";
import type { Localidad, Suelo } from "@/lib/db";
import type { EscenarioInput, ErrorApi, ResultadoSimulacion } from "@/lib/types";
import {
  CANTIDAD_RASTROJO,
  HUMEDAD_INICIAL,
  SANDWICH_SECO,
  MESES,
} from "@/lib/equivalencias";
import TablaResultado from "@/components/TablaResultado";

interface Props {
  localidades: Localidad[];
  cultivos: string[];
}

const DIAS = Array.from({ length: 31 }, (_, i) => i + 1);

function Campo({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5 text-sm">
      <span className="font-medium text-heading">{label}</span>
      {children}
    </label>
  );
}

const claseSelect =
  "rounded-lg border border-border bg-white px-3 py-2 text-sm text-text shadow-sm focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30 disabled:cursor-not-allowed disabled:bg-surface disabled:text-text/40";

export default function FormularioEscenario({ localidades, cultivos }: Props) {
  const [localidad, setLocalidad] = useState("");
  const [suelos, setSuelos] = useState<Suelo[]>([]);
  const [suelo, setSuelo] = useState("");

  const [cultivo, setCultivo] = useState("");
  const [cultivares, setCultivares] = useState<string[]>([]);
  const [cultivar, setCultivar] = useState("");

  const [siembraDia, setSiembraDia] = useState(1);
  const [siembraMes, setSiembraMes] = useState(6);
  const [monitoreoDia, setMonitoreoDia] = useState(1);
  const [monitoreoMes, setMonitoreoMes] = useState(3);

  const [cantidadRastrojo, setCantidadRastrojo] = useState(CANTIDAD_RASTROJO[1].codigo);
  const [auM1, setAuM1] = useState(HUMEDAD_INICIAL[3].codigo);
  const [auM2, setAuM2] = useState(HUMEDAD_INICIAL[3].codigo);
  const [sandwichSeco, setSandwichSeco] = useState(SANDWICH_SECO[1].codigo);

  const [cargando, setCargando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [resultado, setResultado] = useState<ResultadoSimulacion | null>(null);

  // Cascada Localidad -> Suelos (la Estación queda fija, no se muestra).
  // El reset de `suelo`/`suelos` va en el handler que cambia `localidad`
  // (ver onLocalidadChange), no sincrono al tope del efecto -- el efecto
  // solo se ocupa de traer la lista nueva.
  useEffect(() => {
    if (!localidad) return;
    fetch(`/api/suelos?localidad=${encodeURIComponent(localidad)}`)
      .then((r) => r.json())
      .then((data: { suelos: Suelo[] }) => setSuelos(data.suelos ?? []));
  }, [localidad]);

  function onLocalidadChange(nuevaLocalidad: string) {
    setLocalidad(nuevaLocalidad);
    setSuelo("");
    setSuelos([]);
  }

  // Cascada Cultivo -> Cultivares (mismo criterio que arriba).
  useEffect(() => {
    if (!cultivo) return;
    fetch(`/api/cultivares?cultivo=${encodeURIComponent(cultivo)}`)
      .then((r) => r.json())
      .then((data: { cultivares: string[] }) => setCultivares(data.cultivares ?? []));
  }, [cultivo]);

  function onCultivoChange(nuevoCultivo: string) {
    setCultivo(nuevoCultivo);
    setCultivar("");
    setCultivares([]);
  }

  const estacionSeleccionada = localidades.find((l) => l.localidad === localidad);
  const listo = Boolean(
    estacionSeleccionada && suelo && cultivo && cultivar
  );

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!estacionSeleccionada) return;
    setCargando(true);
    setError(null);
    setResultado(null);

    const body: EscenarioInput = {
      estacion: estacionSeleccionada.ommId,
      suelo,
      cultivo,
      cultivar,
      siembra: { dia: siembraDia, mes: siembraMes },
      monitoreo: { dia: monitoreoDia, mes: monitoreoMes },
      cantidad_rastrojo: cantidadRastrojo,
      au_m1: auM1,
      au_m2: auM2,
      sandwich_seco: sandwichSeco,
    };

    try {
      const res = await fetch("/api/simular", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = (await res.json()) as ResultadoSimulacion | ErrorApi;
      if (!res.ok || "error" in data) {
        setError("error" in data ? data.error : "Error al correr la simulación");
      } else {
        setResultado(data);
      }
    } catch {
      setError("No se pudo conectar con el servicio de simulación");
    } finally {
      setCargando(false);
    }
  }

  return (
    <div className="space-y-8">
      <form
        onSubmit={onSubmit}
        className="space-y-8 rounded-2xl border border-border bg-white p-6 shadow-sm sm:p-8"
      >
        <section className="space-y-4">
          <h2 className="text-lg font-semibold">Ubicación y suelo</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            <Campo label="Localidad">
              <select
                className={claseSelect}
                value={localidad}
                onChange={(e) => onLocalidadChange(e.target.value)}
                required
              >
                <option value="">Elegir localidad…</option>
                {localidades.map((l) => (
                  <option key={l.localidad} value={l.localidad}>
                    {l.localidad}
                  </option>
                ))}
              </select>
            </Campo>
            <Campo label="Suelo">
              <select
                className={claseSelect}
                value={suelo}
                onChange={(e) => setSuelo(e.target.value)}
                disabled={!localidad}
                required
              >
                <option value="">Elegir suelo…</option>
                {suelos.map((s) => (
                  <option key={s.suelo} value={s.suelo}>
                    {s.suelo}
                    {s.tipoSuelo ? ` — ${s.tipoSuelo}` : ""}
                  </option>
                ))}
              </select>
            </Campo>
          </div>
        </section>

        <section className="space-y-4">
          <h2 className="text-lg font-semibold">Cultivo</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            <Campo label="Cultivo">
              <select
                className={claseSelect}
                value={cultivo}
                onChange={(e) => onCultivoChange(e.target.value)}
                required
              >
                <option value="">Elegir cultivo…</option>
                {cultivos.map((c) => (
                  <option key={c} value={c}>
                    {c[0].toUpperCase() + c.slice(1)}
                  </option>
                ))}
              </select>
            </Campo>
            <Campo label="Cultivar">
              <select
                className={claseSelect}
                value={cultivar}
                onChange={(e) => setCultivar(e.target.value)}
                disabled={!cultivo}
                required
              >
                <option value="">Elegir cultivar…</option>
                {cultivares.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </Campo>
          </div>
        </section>

        <section className="space-y-4">
          <h2 className="text-lg font-semibold">Fechas</h2>
          <p className="text-xs text-text/70">
            Solo día y mes — la simulación corre para todos los años de
            clima disponibles de la estación.
          </p>
          <div className="grid gap-4 sm:grid-cols-2">
            <Campo label="Fecha de siembra">
              <div className="flex gap-2">
                <select
                  className={claseSelect}
                  value={siembraDia}
                  onChange={(e) => setSiembraDia(Number(e.target.value))}
                >
                  {DIAS.map((d) => (
                    <option key={d} value={d}>{d}</option>
                  ))}
                </select>
                <select
                  className={claseSelect}
                  value={siembraMes}
                  onChange={(e) => setSiembraMes(Number(e.target.value))}
                >
                  {MESES.map((m) => (
                    <option key={m.valor} value={m.valor}>{m.nombre}</option>
                  ))}
                </select>
              </div>
            </Campo>
            <Campo label="Fecha de monitoreo">
              <div className="flex gap-2">
                <select
                  className={claseSelect}
                  value={monitoreoDia}
                  onChange={(e) => setMonitoreoDia(Number(e.target.value))}
                >
                  {DIAS.map((d) => (
                    <option key={d} value={d}>{d}</option>
                  ))}
                </select>
                <select
                  className={claseSelect}
                  value={monitoreoMes}
                  onChange={(e) => setMonitoreoMes(Number(e.target.value))}
                >
                  {MESES.map((m) => (
                    <option key={m.valor} value={m.valor}>{m.nombre}</option>
                  ))}
                </select>
              </div>
            </Campo>
          </div>
        </section>

        <section className="space-y-4">
          <h2 className="text-lg font-semibold">Condiciones iniciales</h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Campo label="Cantidad de rastrojo">
              <select
                className={claseSelect}
                value={cantidadRastrojo}
                onChange={(e) => setCantidadRastrojo(e.target.value)}
              >
                {CANTIDAD_RASTROJO.map((n) => (
                  <option key={n.codigo} value={n.codigo}>{n.etiqueta}</option>
                ))}
              </select>
            </Campo>
            <Campo label="AU — 1er metro">
              <select
                className={claseSelect}
                value={auM1}
                onChange={(e) => setAuM1(e.target.value)}
              >
                {HUMEDAD_INICIAL.map((n) => (
                  <option key={n.codigo} value={n.codigo}>{n.etiqueta}</option>
                ))}
              </select>
            </Campo>
            <Campo label="AU — 2do metro">
              <select
                className={claseSelect}
                value={auM2}
                onChange={(e) => setAuM2(e.target.value)}
              >
                {HUMEDAD_INICIAL.map((n) => (
                  <option key={n.codigo} value={n.codigo}>{n.etiqueta}</option>
                ))}
              </select>
            </Campo>
            <Campo label="Sandwich seco">
              <select
                className={claseSelect}
                value={sandwichSeco}
                onChange={(e) => setSandwichSeco(e.target.value)}
              >
                {SANDWICH_SECO.map((n) => (
                  <option key={n.codigo} value={n.codigo}>{n.etiqueta}</option>
                ))}
              </select>
            </Campo>
          </div>
        </section>

        <div className="flex items-center gap-4 border-t border-border pt-6">
          <button
            type="submit"
            disabled={!listo || cargando}
            className="rounded-full bg-accent px-6 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-accent-dark disabled:cursor-not-allowed disabled:opacity-40"
          >
            {cargando ? "Simulando…" : "Correr simulación"}
          </button>
          {error && <p className="text-sm text-highlight">{error}</p>}
        </div>
      </form>

      {resultado && <TablaResultado resultado={resultado} />}
    </div>
  );
}
