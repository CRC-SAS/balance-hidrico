import Image from "next/image";
import { getLocalidades, getCultivos } from "@/lib/db";
import FormularioEscenario from "@/components/FormularioEscenario";

export default function Home() {
  const localidades = getLocalidades();
  const cultivos = getCultivos();

  return (
    <>
      <header className="border-b border-border bg-surface">
        <div className="mx-auto flex max-w-5xl items-start justify-between gap-6 px-6 py-8">
          <div>
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
          <Image
            src="/crc-sas-logo.png"
            alt="Logo CRC-SAS"
            width={121}
            height={139}
            priority
            className="h-14 w-auto flex-shrink-0 sm:h-16"
          />
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
