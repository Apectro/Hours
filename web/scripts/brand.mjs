/**
 * Where the card gets its facts.
 *
 * The headline lives in src/brand.json and the palette and typefaces live in
 * src/styles.css, which are the files the page itself uses. Reading them here
 * means the social card cannot drift from the site, which it did once: after a
 * redesign it went on rendering the old headline in the old colours in the old
 * fonts, because it was carrying its own copies.
 *
 * Both `og.mjs` and `verify-published.mjs` import this, so the generator and
 * the check cannot disagree about what the card was supposed to contain.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const web = dirname(dirname(fileURLToPath(import.meta.url)));

export function readBrand() {
  const brand = JSON.parse(readFileSync(join(web, "src", "brand.json"), "utf8"));
  const css = readFileSync(join(web, "src", "styles.css"), "utf8");

  // The first :root block is the light palette. The card is a light one; an
  // unfurler has no viewer theme to ask about.
  const lightRoot = css.slice(css.indexOf(":root {"), css.indexOf("@media"));

  const token = (name) => {
    const match = lightRoot.match(new RegExp(`--${name}:\\s*([^;]+);`));
    if (!match) throw new Error(`styles.css has no --${name} — did the palette get renamed?`);
    return match[1].trim();
  };

  /** `--display: "Bricolage Grotesque", ...` → `Bricolage Grotesque`. */
  const family = (name) => {
    const first = token(name).match(/"([^"]+)"/);
    if (!first) throw new Error(`--${name} does not start with a quoted family name`);
    return first[1];
  };

  return {
    brand,
    palette: {
      INK: token("ink"),
      SOFT: token("ink-faint"),
      ACCENT: token("accent"),
      GROUND: token("paper"),
      RULE: token("rule"),
      ON_ACCENT: token("on-accent"),
    },
    fonts: { display: family("display"), type: family("type") },
  };
}

/** Exactly what gets written beside the card, and compared against later. */
export function cardInputs() {
  const { brand, palette, fonts } = readBrand();
  return { headlineLines: brand.headlineLines, equation: brand.equation, palette, fonts };
}
