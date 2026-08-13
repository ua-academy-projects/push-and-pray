import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  base: "/static/",
  build: {
    outDir: "../backend/src/ui_service/static",
    emptyOutDir: true,
    assetsDir: "assets",
    sourcemap: false,
    chunkSizeWarningLimit: 650,
  },
  server: {
    port: 5173,
    proxy: {
      "/api": "http://127.0.0.1:8080",
      "/health": "http://127.0.0.1:8080",
    },
  },
});
