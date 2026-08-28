import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The site is served from its own domain, zeitkonto.app, so the base is the
// root. It used to be /Hours/, which is where GitHub Pages puts a project
// site before a custom domain is attached; public/CNAME is what attaches it.
// Set VITE_BASE=/Hours/ to preview it the old way.
export default defineConfig({
  plugins: [react()],
  base: process.env.VITE_BASE ?? "/",
  build: { outDir: "dist", assetsDir: "assets" },
});
