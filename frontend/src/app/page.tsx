import { getLocalidades, getCultivos } from "@/lib/db";
import FormularioEscenario from "@/components/FormularioEscenario";

export default function Home() {
  const localidades = getLocalidades();
  const cultivos = getCultivos();

  return (
    <>
      <header className="border-b border-border bg-surface">
        <div className="mx-auto max-w-5xl px-6 py-8">
          <p className="text-sm font-semibold uppercase tracking-widest text-accent-dark">
            CRC-SAS
          </p>
          <h1 className="mt-1 text-2xl font-bold sm:text-3xl">
            Balance hídrico — escenarios individuales
          </h1>
          <p className="mt-3 max-w-2xl text-sm leading-relaxed text-text">
            Elegí una localidad, un suelo, un cultivo y las condiciones
            iniciales del escenario. La simulación corre contra todos los
            años de clima disponibles para esa estación y devuelve las
            salidas del método agregadas.
          </p>
        </div>
      </header>

      <main className="mx-auto w-full max-w-5xl flex-1 px-6 py-10">
        <FormularioEscenario localidades={localidades} cultivos={cultivos} />
      </main>

      <footer className="border-t border-border bg-surface py-6">
        <div className="mx-auto max-w-5xl px-6 text-xs text-text/70">
          Centro Regional del Clima para el Sur de América del Sur (CRC-SAS)
        </div>
      </footer>
    </>
  );
}
