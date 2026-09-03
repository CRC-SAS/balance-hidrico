import type { AnioResultado, EstadisticaVariable, ResultadoSimulacion } from "@/lib/types";
import { VARIABLE_SALIDA_LABELS } from "@/lib/equivalencias";

function formatearNumero(n: number): string {
  return new Intl.NumberFormat("es-AR", { maximumFractionDigits: 1 }).format(n);
}

function TablaAnios({ filas }: { filas: AnioResultado[] }) {
  if (filas.length === 0) return null;
  return (
    <div className="overflow-hidden rounded-xl border border-border">
      <div className="bg-surface px-4 py-3">
        <h3 className="text-sm font-semibold text-heading">Detalle por año</h3>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-t border-border bg-white text-left text-xs uppercase tracking-wide text-text/70">
              <th className="px-4 py-2 font-medium">Año</th>
              <th className="px-4 py-2 font-medium">Eventos de lluvia</th>
              <th className="px-4 py-2 font-medium">AU 1er metro (%)</th>
              <th className="px-4 py-2 font-medium">AU 2do metro (%)</th>
              <th className="px-4 py-2 font-medium">AU total (%)</th>
              <th className="px-4 py-2 font-medium">Sandwich seco</th>
              <th className="px-4 py-2 font-medium">Confort hídrico (%)</th>
            </tr>
          </thead>
          <tbody>
            {filas.map((fila) => (
              <tr key={fila.anio} className="border-t border-border">
                <td className="px-4 py-2 font-medium text-heading">{fila.anio}</td>
                <td className="px-4 py-2">{fila.eventos_lluvia_10mm_14a_7d_siembra}</td>
                <td className="px-4 py-2">{formatearNumero(fila.au_pct_m1)}</td>
                <td className="px-4 py-2">{formatearNumero(fila.au_pct_m2)}</td>
                <td className="px-4 py-2">{formatearNumero(fila.au_pct_total)}</td>
                <td className="px-4 py-2">{fila.sandwich_seco}</td>
                <td className="px-4 py-2">{formatearNumero(fila.confort_hidrico)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function Grupo({ titulo, filas }: { titulo: string; filas: EstadisticaVariable[] }) {
  if (filas.length === 0) return null;
  return (
    <div className="overflow-hidden rounded-xl border border-border">
      <div className="bg-surface px-4 py-3">
        <h3 className="text-sm font-semibold text-heading">{titulo}</h3>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-t border-border bg-white text-left text-xs uppercase tracking-wide text-text/70">
              <th className="px-4 py-2 font-medium">Variable</th>
              <th className="px-4 py-2 font-medium">Media</th>
              <th className="px-4 py-2 font-medium">P20</th>
              <th className="px-4 py-2 font-medium">P50</th>
              <th className="px-4 py-2 font-medium">P80</th>
              <th className="px-4 py-2 font-medium">Desvío</th>
              <th className="px-4 py-2 font-medium">IQR</th>
            </tr>
          </thead>
          <tbody>
            {filas.map((fila) => (
              <tr key={fila.variable} className="border-t border-border">
                <td className="px-4 py-2 text-text">
                  {VARIABLE_SALIDA_LABELS[fila.variable] ?? fila.variable}
                </td>
                <td className="px-4 py-2 font-medium text-heading">{formatearNumero(fila.media)}</td>
                <td className="px-4 py-2">{formatearNumero(fila.p20)}</td>
                <td className="px-4 py-2">{formatearNumero(fila.p50)}</td>
                <td className="px-4 py-2">{formatearNumero(fila.p80)}</td>
                <td className="px-4 py-2">{formatearNumero(fila.desvio)}</td>
                <td className="px-4 py-2">{formatearNumero(fila.iqr)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default function TablaResultado({ resultado }: { resultado: ResultadoSimulacion }) {
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center gap-3 rounded-xl bg-surface px-4 py-3 text-sm">
        <span className="font-medium text-heading">
          {resultado.anios_simulados} años simulados
        </span>
        {resultado.anios_con_error > 0 && (
          <span className="rounded-full bg-highlight/15 px-3 py-1 text-xs font-medium text-highlight">
            {resultado.anios_con_error} año(s) no se pudieron simular
          </span>
        )}
      </div>
      <Grupo titulo="Siembra" filas={resultado.salidas.siembra} />
      <Grupo titulo="Cultivo" filas={resultado.salidas.cultivo} />
      <TablaAnios filas={resultado.anios} />
    </div>
  );
}
