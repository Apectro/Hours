/**
 * Turn the screenshots into something worth downloading.
 *
 * The captures are 1320px wide because that is what the simulator produces.
 * The page renders them at 318px (hero) and 225px (gallery), so shipping the
 * originals sends four to six times the pixels any screen asks for — 1.77MB
 * of a 1.9MB page, which on a phone over cellular is the whole experience.
 *
 * The originals live in shots-src/ and are never served. Only the resized
 * copies land in public/shots/, which is why that folder is not in git: it is
 * output, and it is rebuilt before both `dev` and `build` so the two see
 * exactly the same files.
 */
import sharp from "sharp";
import { mkdirSync, readdirSync, rmSync, statSync } from "node:fs";
import { dirname, join, parse } from "node:path";
import { fileURLToPath } from "node:url";

const web = dirname(dirname(fileURLToPath(import.meta.url)));
const source = join(web, "shots-src");
const target = join(web, "public", "shots");

/** Widths to emit, covering the largest render (318px) at 3× device pixels. */
const WIDTHS = [480, 960];

/** The single width kept as PNG, for anything that cannot read WebP. */
const FALLBACK_WIDTH = 640;

rmSync(target, { recursive: true, force: true });
mkdirSync(target, { recursive: true });

/**
 * The timesheet the page shows as evidence is a landscape PDF page, so it
 * needs its own widths and a crop: the whole page at this size would be
 * unreadable, and the part worth reading is the head and the first week.
 * Those numbers are pixels in the 1684x1190 render the capture suite writes.
 */
const EXPORT_WIDTHS = [800, 1570];
const EXPORT_CROP = { left: 60, top: 55, width: 1570, height: 520 };

async function emit(path, name, widths, fallbackWidth, crop) {
  const prepare = () => (crop ? sharp(path).extract(crop) : sharp(path));
  let smallest = 0;
  for (const width of widths) {
    const out = join(target, `${name}.${width}.webp`);
    await prepare().resize({ width }).webp({ quality: 82 }).toFile(out);
    if (width === widths[0]) smallest = statSync(out).size;
  }
  await prepare()
    .resize({ width: fallbackWidth })
    .png({ compressionLevel: 9 })
    .toFile(join(target, `${name}.${fallbackWidth}.png`));
  return smallest;
}

const files = readdirSync(source).filter((f) => f.endsWith(".png"));
let before = 0;
let smallest = 0;

for (const file of files) {
  const path = join(source, file);
  before += statSync(path).size;
  smallest += await emit(path, parse(file).name, WIDTHS, FALLBACK_WIDTH);
}

const exportDir = join(source, "exports");
const exports = readdirSync(exportDir).filter((f) => f.endsWith(".png"));
for (const file of exports) {
  const path = join(exportDir, file);
  before += statSync(path).size;
  smallest += await emit(path, parse(file).name, EXPORT_WIDTHS, 800, EXPORT_CROP);
}

const kb = (n) => `${Math.round(n / 1024)}KB`;
console.log(
  `${files.length + exports.length} images: ${kb(before)} of PNG in, ` +
    `${kb(smallest)} fetched by a phone`,
);
