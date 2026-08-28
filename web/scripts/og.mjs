/**
 * Render the social card.
 *
 * Sharing the link anywhere — Slack, iMessage, anywhere with an unfurler —
 * shows og:image or shows nothing, and nothing is what it showed before this.
 *
 * The card is drawn from the site's own hero rather than made in a graphics
 * program, so it says the same thing the page says and in the same faces. The
 * webfonts are fetched and inlined because a headless browser resolving them
 * over the network would silently fall back to whatever is installed, which is
 * exactly the drift the card exists to avoid.
 *
 * Needs playwright, which is not a dependency of the site: this is run when
 * the wording or the palette changes, not on every build, and public/og.png
 * is committed output.
 */
import sharp from "sharp";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scripts = dirname(fileURLToPath(import.meta.url));
const web = dirname(scripts);

const FACES = "family=Archivo:wght@700&family=JetBrains+Mono:wght@400;500";
const BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36";

/** Google serves TTF to an old UA and WOFF2 to a modern one; either is fine. */
async function inlineFonts() {
  const css = await (
    await fetch(`https://fonts.googleapis.com/css2?${FACES}&display=swap`, {
      headers: { "User-Agent": BROWSER },
    })
  ).text();

  const urls = [...new Set([...css.matchAll(/url\((https:\/\/[^)]+)\)/g)].map((m) => m[1]))];
  const data = new Map();
  for (const url of urls) {
    const bytes = Buffer.from(await (await fetch(url)).arrayBuffer());
    data.set(url, `data:font/${url.endsWith(".woff2") ? "woff2" : "ttf"};base64,${bytes.toString("base64")}`);
  }
  return css.replace(/url\((https:\/\/[^)]+)\)/g, (whole, url) => `url(${data.get(url) ?? url})`);
}

const { chromium } = await import("playwright");

/* The phone on the card is the same capture the hero uses, at the width the
   card draws it, inlined because setContent has no directory to resolve
   relative paths against. */
const shot = await sharp(join(web, "shots-src", "01-calendar.png"))
  .resize({ width: 528 })
  .png({ compressionLevel: 9 })
  .toBuffer();

const html = readFileSync(join(scripts, "og.html"), "utf8")
  .replace("/* FONTS */", await inlineFonts())
  .replace("/* SHOT */", `data:image/png;base64,${shot.toString("base64")}`);

const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
});
const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
await page.setContent(html, { waitUntil: "load" });
await page.evaluate(() => document.fonts.ready);
const out = join(web, "public", "og.png");
await page.screenshot({ path: out });
await browser.close();

writeFileSync(out, readFileSync(out));
console.log(`Wrote ${out}`);
