import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The site is served from the repository's GitHub Pages, which sits at
// /Hours/ rather than the domain root. Set VITE_BASE=/ when serving it
// somewhere that has its own domain.
export default defineConfig({
  plugins: [react()],
  base: process.env.VITE_BASE ?? "/Hours/",
  build: { outDir: "dist", assetsDir: "assets" },
});
