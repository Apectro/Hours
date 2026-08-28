/**
 * Render the social card.
 *
 * Sharing the link anywhere — Slack, iMessage, anywhere with an unfurler —
 * shows og:image or shows nothing, and nothing is what it showed before this
 * existed.
 *
 * It reads its headline from brand.json and its palette and typefaces out of
 * styles.css, rather than keeping copies of them. It used to keep copies. The
 * site was redesigned around it and the card carried on rendering the previous
 * headline in the previous colours in the previous fonts, which is what
 * duplicated constants do the moment one of them moves.
 *
 * Composed with sharp, already a dependency, rather than by screenshotting a
 * headless browser: `npm run og` then works from a clean `npm install` instead
 * of needing a browser nobody declared.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { cardInputs, readBrand } from "./brand.mjs";

const scripts = dirname(fileURLToPath(import.meta.url));
const web = dirname(scripts);

/* -------------------------------------------------------- the single source */

const { brand, palette, fonts: faces } = readBrand();

const { INK, SOFT, ACCENT, GROUND, RULE, ON_ACCENT } = palette;
const DISPLAY = faces.display;
const TYPE = faces.type;

/* ---------------------------------------------------------------- the fonts */

/*
 * fontconfig looks in $XDG_DATA_HOME/fonts, so putting the faces there and
 * setting the variable is the whole installation. It has to happen before
 * sharp is imported: libvips initialises fontconfig the first time it draws.
 */
const cache = join(web, ".fontcache");
const fonts = join(cache, "fonts");
mkdirSync(fonts, { recursive: true });
process.env.XDG_DATA_HOME = cache;

const wanted = `family=${DISPLAY.replace(/ /g, "+")}:wght@700&family=${TYPE.replace(/ /g, "+")}:wght@400;700`;

async function ensureFonts() {
  const stamp = join(cache, "fetched");
  // Refetch when the faces themselves change, not only when the cache is cold.
  if (existsSync(stamp) && readFileSync(stamp, "utf8").startsWith(wanted)) return;

  // Google picks a format from the User-Agent and serves the oldest it can
  // when there is nothing to go on, which is what is wanted here: fontconfig
  // reads TTF, and cannot read the WOFF a browser-shaped request would get.
  const sheet = await (await fetch(`https://fonts.googleapis.com/css2?${wanted}`)).text();
  const urls = [...new Set([...sheet.matchAll(/url\((https:\/\/[^)]+\.ttf)\)/g)].map((m) => m[1]))];
  if (urls.length === 0) {
    throw new Error("Google Fonts served no TTF — check the network, or that it still does");
  }

  for (const [index, url] of urls.entries()) {
    writeFileSync(join(fonts, `face-${index}.ttf`), Buffer.from(await (await fetch(url)).arrayBuffer()));
  }
  writeFileSync(stamp, `${wanted}\n${urls.join("\n")}`);
  console.log(`Fetched ${urls.length} font files for ${DISPLAY} and ${TYPE}`);
}

await ensureFonts();

const sharp = (await import("sharp")).default;

/**
 * Draw one string in the wanted face, and again in a family that cannot
 * exist. If fontconfig found the face the two differ. If it silently fell back
 * they are the same fallback, and the card would be wrong in a way no later
 * check would catch.
 */
async function assertFontIsUsed(name) {
  const draw = (face) =>
    sharp(
      Buffer.from(
        `<svg xmlns="http://www.w3.org/2000/svg" width="520" height="80">` +
          `<text x="8" y="56" font-family="${face}" font-weight="700" font-size="42">Hours balance</text></svg>`,
      ),
    )
      .png()
      .toBuffer();
  const [face, nonsense] = await Promise.all([draw(name), draw("NoSuchFace-9Q4Z")]);
  if (face.equals(nonsense)) {
    throw new Error(`${name} was not found by fontconfig — the card would render in a fallback`);
  }
}

await assertFontIsUsed(DISPLAY);
await assertFontIsUsed(TYPE);

/* ----------------------------------------------------------------- the card */

const W = 1200;
const H = 630;

/** Courier Prime is monospaced at 600/1000 units, so x is arithmetic. */
const MONO_SIZE = 23;
const ADVANCE = MONO_SIZE * 0.6;

const FILL = { term: INK, op: SOFT, result: ACCENT };

function equationSpans(x, y) {
  let column = 0;
  return brand.equation
    .map(([text, kind]) => {
      const at = x + column * ADVANCE;
      column += text.length + 1; // one space between every part
      const weight = kind === "result" ? 700 : 400;
      return `<text x="${at}" y="${y}" font-family="${TYPE}" font-weight="${weight}" font-size="${MONO_SIZE}" fill="${FILL[kind]}">${text}</text>`;
    })
    .join("");
}

/* Two long lines rather than the page's two, so the card is not mostly type. */
const lines = brand.headlineLines;
const headTop = 300 - (lines.length - 1) * 34;

const card = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">
  <rect width="${W}" height="${H}" fill="${GROUND}"/>
  <rect x="76" y="68" width="52" height="52" rx="12" fill="${ACCENT}"/>
  <text x="102" y="105" font-family="${DISPLAY}" font-weight="700" font-size="31" fill="${ON_ACCENT}" text-anchor="middle">h</text>
  <text x="146" y="105" font-family="${DISPLAY}" font-weight="700" font-size="31" fill="${INK}" letter-spacing="-0.6">Hours</text>
  ${lines
    .map(
      (line, index) =>
        `<text x="76" y="${headTop + index * 68}" font-family="${DISPLAY}" font-weight="700" font-size="62" fill="${INK}" letter-spacing="-1.7">${line}</text>`,
    )
    .join("")}
  <rect x="76" y="498" width="714" height="2" fill="${INK}"/>
  ${equationSpans(76, 552)}
  <rect x="0" y="${H - 1}" width="${W}" height="1" fill="${RULE}"/>
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

/*
 * What the card was made from, so CI can tell whether it still matches the
 * site. Comparing the PNG's bytes would not work, because sharp's output
 * depends on whichever libvips the machine has, but its inputs compare
 * exactly. It sits beside package.json rather than in public/, because it is a
 * record for this repository and not a file the site needs to serve.
 */
writeFileSync(join(web, "og.inputs.json"), `${JSON.stringify(cardInputs(), null, 2)}\n`);

console.log(`Wrote ${out} — ${DISPLAY} and ${TYPE}, accent ${ACCENT}`);
