import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Caminhos relativos: o build é carregado via file:// pelo Electron.
export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    outDir: "dist",
    emptyOutDir: true
  },
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"]
  }
} as never);
