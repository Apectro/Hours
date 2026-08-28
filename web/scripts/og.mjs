/**
 * Render the social card.
 *
 * Sharing the link anywhere — Slack, iMessage, anywhere with an unfurler —
 * shows og:image or shows nothing, and nothing is what it showed before this.
 *
 * It is drawn from the site's own hero rather than made in a graphics program,
 * so it says the same thing the page says and in the same faces. It is built
 * with sharp, which is already a dependency, rather than by screenshotting a
 * headless browser: `npm run og` then works from a clean `npm install` instead
 * of needing a browser nobody declared.
 *
 * The webfonts are downloaded and handed to fontconfig, because the card's
 * whole job is to look like the site, and a renderer quietly falling back to
 * whatever is installed is exactly the drift it exists to avoid. That is
 * checked rather than hoped for — see `assertFontIsUsed`.
 */
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scripts = dirname(fileURLToPath(import.meta.url));
const web = dirname(scripts);

/* ------------------------------------------------------------------ fonts */

const FACES = "family=Archivo:wght@700&family=JetBrains+Mono:wght@400;500";

/**
 * fontconfig looks in $XDG_DATA_HOME/fonts, so putting the faces there and
 * setting the variable is the whole installation. It has to happen before
 * sharp is imported: libvips initialises fontconfig the first time it draws.
 */
const cache = join(web, ".fontcache");
const fonts = join(cache, "fonts");
mkdirSync(fonts, { recursive: true });
process.env.XDG_DATA_HOME = cache;

async function ensureFonts() {
  const stamp = join(cache, "fetched");
  if (existsSync(stamp)) return;

  // Google picks a format from the User-Agent and serves the oldest it can
  // when there is nothing to go on, which is what is wanted here: fontconfig
  // reads TTF, and cannot read the WOFF a browser-shaped request would get.
  const css = await (await fetch(`https://fonts.googleapis.com/css2?${FACES}`)).text();
  const urls = [...new Set([...css.matchAll(/url\((https:\/\/[^)]+\.ttf)\)/g)].map((m) => m[1]))];
  if (urls.length === 0) {
    throw new Error("Google Fonts served no TTF — check the network, or that it still does");
  }

  for (const [index, url] of urls.entries()) {
    const bytes = Buffer.from(await (await fetch(url)).arrayBuffer());
    writeFileSync(join(fonts, `face-${index}.ttf`), bytes);
  }
  writeFileSync(stamp, urls.join("\n"));
  console.log(`Fetched ${urls.length} font files into .fontcache/`);
}

await ensureFonts();

const sharp = (await import("sharp")).default;

/**
 * Draw one string in the wanted face and again in a family that cannot
 * exist. If fontconfig found the face the two differ; if it silently fell
 * back, both are the same fallback and the card would be wrong in a way no
 * later check would notice.
 */
async function assertFontIsUsed(family) {
  const draw = (name) =>
    sharp(
      Buffer.from(
        `<svg xmlns="http://www.w3.org/2000/svg" width="520" height="80">` +
          `<text x="8" y="56" font-family="${name}" font-weight="700" font-size="42">Hours balance</text></svg>`,
      ),
    )
      .png()
      .toBuffer();
  const [wanted, nonsense] = await Promise.all([draw(family), draw("NoSuchFace-9Q4Z")]);
  if (wanted.equals(nonsense)) {
    throw new Error(`${family} was not found by fontconfig — the card would render in a fallback`);
  }
}

await assertFontIsUsed("Archivo");
await assertFontIsUsed("JetBrains Mono");

/* ------------------------------------------------------------------- card */

const W = 1200;
const H = 630;

const INK = "#12161C";
const SOFT = "#7C8697";
const ACCENT = "#276099";
const GROUND = "#F4F6FA";
const RULE = "#D3DAE4";

const HEADLINE = ["Your hours, on your", "phone, and", "nowhere else."];

/** JetBrains Mono is monospaced at 600/1000 units, so x is arithmetic. */
const MONO_SIZE = 23;
const ADVANCE = MONO_SIZE * 0.6;

const EQUATION = [
  ["worked", INK],
  ["+", SOFT],
  ["credited", INK],
  ["−", SOFT],
  ["expected", INK],
  ["+", SOFT],
  ["adjustment", INK],
  ["=", SOFT],
  ["balance", ACCENT],
];

function equationSpans(x, y) {
  let column = 0;
  return EQUATION.map(([text, fill]) => {
    const at = x + column * ADVANCE;
    column += text.length + 1; // one space between every part
    const weight = fill === ACCENT ? 500 : 400;
    return `<text x="${at}" y="${y}" font-family="JetBrains Mono" font-weight="${weight}" font-size="${MONO_SIZE}" fill="${fill}">${text}</text>`;
  }).join("");
}

const card = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">
  <rect width="${W}" height="${H}" fill="${GROUND}"/>
  <rect x="76" y="68" width="52" height="52" rx="13" fill="${ACCENT}"/>
  <text x="102" y="104" font-family="Archivo" font-weight="700" font-size="30" fill="#FFFFFF" text-anchor="middle">h</text>
  <text x="144" y="104" font-family="Archivo" font-weight="700" font-size="30" fill="${INK}">Hours</text>
  ${HEADLINE.map(
    (line, index) =>
      `<text x="76" y="${268 + index * 62}" font-family="Archivo" font-weight="700" font-size="60" fill="${INK}" letter-spacing="-1.4">${line}</text>`,
  ).join("")}
  <rect x="76" y="498" width="714" height="1" fill="${RULE}"/>
  ${equationSpans(76, 552)}
</svg>`;

/* The phone is the same capture the hero uses, rounded to match the page. */
const PHONE = { width: 264, x: 860, y: 74 };
const phone = await sharp(join(web, "shots-src", "01-calendar.png"))
  .resize({ width: PHONE.width })
  .toBuffer();
const { height: phoneHeight } = await sharp(phone).metadata();

const rounded = await sharp(phone)
  .composite([
    {
      input: Buffer.from(
        `<svg xmlns="http://www.w3.org/2000/svg" width="${PHONE.width}" height="${phoneHeight}">` +
          `<rect width="${PHONE.width}" height="${phoneHeight}" rx="26" fill="#fff"/></svg>`,
      ),
      blend: "dest-in",
    },
  ])
  .png()
  .toBuffer();

const out = join(web, "public", "og.png");
await sharp(Buffer.from(card))
  .composite([{ input: rounded, top: PHONE.y, left: PHONE.x }])
  .png({ compressionLevel: 9 })
  .toFile(out);

console.log(`Wrote ${out}`);
