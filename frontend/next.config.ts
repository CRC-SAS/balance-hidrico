import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Imagen Docker minima (ver frontend/Dockerfile) -- copia solo los
  // archivos de runtime necesarios, sin el node_modules completo.
  output: "standalone",
};

export default nextConfig;
