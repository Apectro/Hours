/**
 * Fail if docs/ is not what web/ currently builds.
 *
 * The site is deployed by committing its build output into docs/, because
 * Pages serves main:/docs and the privacy policy's URL is already in App Store
 * Connect. The cost of that choice is this failure mode: edit web/src, forget
 * `npm run publish`, and the live site keeps serving the old build silently.
 * Nothing errors. Nobody finds out.
 *
 * The check is on index.html rather than on every byte of output. Vite names
 * assets by the hash of their contents, so index.html holds a fingerprint of
 * the whole bundle: change one character of source and the filename it points
 * at changes with it. Comparing image bytes would be the obvious thing and the
 * wrong one — sharp's WebP output depends on the libvips the runner happens to
 * have, so it would fail on a machine difference rather than on a mistake.
 * Images are checked by name, which is what catches the real error of adding a
 * screenshot without republishing.
 */
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, parse } from "node:path";
import { fileURLToPath } from "node:url";
import { cardInputs } from "./brand.mjs";

const web = dirname(dirname(fileURLToPath(import.meta.url)));
const docs = join(web, "..", "docs");
const dist = join(web, "dist");

execFileSync("npm", ["run", "build"], { cwd: web, stdio: "inherit" });

const problems = [];

const fresh = readFileSync(join(dist, "index.html"), "utf8");
const published = existsSync(join(docs, "index.html"))
  ? readFileSync(join(docs, "index.html"), "utf8")
  : null;

if (published === null) {
  problems.push("docs/index.html is missing entirely");
} else if (fresh !== published) {
  problems.push(
    "docs/index.html is not what web/ builds today.\n" +
      "    Someone changed the site and did not run `npm run publish`.",
  );
}

/* Every asset the fresh page asks for has to actually be in docs/. */
for (const asset of [...fresh.matchAll(/(?:src|href)="\/Hours\/(assets\/[^"]+)"/g)].map((m) => m[1])) {
  if (!existsSync(join(docs, asset))) problems.push(`docs/${asset} is referenced but missing`);
}

/* And every screenshot in shots-src has to have been resized into docs/. */
const widths = ["480.webp", "960.webp", "640.png"];
const exportWidths = ["800.webp", "1570.webp", "800.png"];

const check = (dir, suffixes) => {
  for (const file of readdirSync(dir).filter((f) => f.endsWith(".png"))) {
    for (const suffix of suffixes) {
      const wanted = `${parse(file).name}.${suffix}`;
      if (!existsSync(join(docs, "shots", wanted))) {
        problems.push(`docs/shots/${wanted} is missing — run \`npm run publish\``);
      }
    }
  }
};

check(join(web, "shots-src"), widths);
check(join(web, "shots-src", "exports"), exportWidths);

if (!existsSync(join(docs, "og.png"))) problems.push("docs/og.png is missing");

/*
 * The social card is committed rather than built, so it can go stale on its
 * own. It once did: the site was redesigned and the card carried on rendering
 * the old headline in the old colours, and nothing caught it. Its bytes cannot
 * be compared — sharp's output depends on whichever libvips the machine has —
 * but the inputs it was made from are written beside it and compare exactly.
 */
const inputsPath = join(web, "og.inputs.json");
if (!existsSync(inputsPath)) {
  problems.push("web/og.inputs.json is missing — run `npm run og`");
} else {
  const recorded = readFileSync(inputsPath, "utf8").trim();
  const current = JSON.stringify(cardInputs(), null, 2);
  if (recorded !== current) {
    problems.push(
      "the social card was made from a headline, palette or typeface the site\n" +
        "    no longer uses. Run `npm run og` and commit the result.",
    );
  }
}
if (!existsSync(join(docs, "privacy", "index.html"))) {
  problems.push("docs/privacy/index.html has gone — that URL is in App Store Connect");
}

if (problems.length > 0) {
  console.error("\ndocs/ is out of date:\n");
  for (const problem of problems) console.error(`  - ${problem}`);
  console.error("\nRun `npm run publish` in web/ and commit the result.\n");
  process.exit(1);
}

console.log("docs/ matches what web/ builds.");
