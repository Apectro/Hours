import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { en } from "./src/copy/en";
import { de } from "./src/copy/de";
import { existsSync } from "node:fs";

/**
 * One config, built twice: English at the root, German at /de/.
 *
 * Two builds rather than one page that switches language in the browser. A
 * static page per language gets the right `lang` attribute, the right title
 * and description for search engines and link previews, and no flash of the
 * wrong language while the bundle loads. It also gives each one a URL that
 * can be shared, which a runtime toggle does not.
 *
 * German takes `base: "/de/"` so its own JS and CSS resolve, but images are
 * referenced absolutely from the components and its publicDir is switched off:
 * the screenshots are identical in both languages and 145KB is not worth
 * duplicating to say the same thing twice.
 */
const LANG = process.env.VITE_LANG === "de" ? "de" : "en";
const copy = LANG === "de" ? de : en;

const SITE = "https://zeitkonto.app";
const canonical = LANG === "de" ? `${SITE}/de/` : `${SITE}/`;

/** Rewrite the shared index.html for whichever language is being built. */
function localiseHtml() {
  return {
    name: "localise-html",
    transformIndexHtml(html: string) {
      return html
        .replace('<html lang="en">', `<html lang="${LANG}">`)
        .replace(/<title>[^<]*<\/title>/, `<title>${copy.htmlTitle}</title>`)
        .replace(/(name="description"\s+content=")[^"]*"/, `$1${copy.htmlDescription}"`)
        .replace(/(property="og:description"\s+content=")[^"]*"/, `$1${copy.ogDescription}"`)
        .replace(/(property="og:url" content=")[^"]*"/, `$1${canonical}"`)
        .replace(/(property="og:image" content=")[^"]*"/, `$1${SITE}/og${LANG === "de" ? "-de" : ""}.png"`)
        .replace(
          /(property="og:image:alt" content=")[^"]*"/,
          `$1Zeitkonto — ${copy.hero.headlineLines.join(" ")}"`,
        )
        .replace(
          "</head>",
          `  <link rel="canonical" href="${canonical}" />\n` +
            `    <link rel="alternate" hreflang="en" href="${SITE}/" />\n` +
            `    <link rel="alternate" hreflang="de" href="${SITE}/de/" />\n` +
            `    <link rel="alternate" hreflang="x-default" href="${SITE}/" />\n` +
            "  </head>",
        );
    },
  };
}

/* Asked of the filesystem rather than declared, so the flag cannot get ahead
   of the images. */
process.env.VITE_GERMAN_SHOTS = existsSync("shots-src/de") ? "1" : "0";

export default defineConfig({
  plugins: [react(), localiseHtml()],
  base: process.env.VITE_BASE ?? (LANG === "de" ? "/de/" : "/"),
  publicDir: LANG === "de" ? false : "public",
  build: { outDir: LANG === "de" ? "dist/de" : "dist", emptyOutDir: LANG !== "de", assetsDir: "assets" },
});
