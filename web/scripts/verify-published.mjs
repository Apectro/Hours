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
import { basename, dirname, join, parse } from "node:path";
import { fileURLToPath } from "node:url";
import { CARD_LANGUAGES, cardInputs } from "./brand.mjs";

const web = dirname(dirname(fileURLToPath(import.meta.url)));
const docs = join(web, "..", "docs");
const dist = join(web, "dist");

execFileSync("npm", ["run", "build"], { cwd: web, stdio: "inherit" });

const problems = [];

/* Both languages, each with its own page and its own hashed bundle. */
const PAGES = [
  { name: "index.html", built: join(dist, "index.html"), published: join(docs, "index.html") },
  { name: "de/index.html", built: join(dist, "de", "index.html"), published: join(docs, "de", "index.html") },
];

let fresh = "";
for (const page of PAGES) {
  const built = readFileSync(page.built, "utf8");
  fresh += built;
  if (!existsSync(page.published)) {
    problems.push(`docs/${page.name} is missing entirely`);
  } else if (built !== readFileSync(page.published, "utf8")) {
    problems.push(
      `docs/${page.name} is not what web/ builds today.\n` +
        "    Someone changed the site and did not run `npm run publish`.",
    );
  }
}

/*
 * Every asset the fresh page asks for has to actually be in docs/. The paths
 * are rooted because the site has its own domain now; this pattern used to
 * carry the /Hours/ prefix, and a stale copy of it would have matched nothing
 * and quietly checked nothing at all.
 */
const referenced = [...fresh.matchAll(/(?:src|href)="\/((?:de\/)?assets\/[^"]+)"/g)].map((m) => m[1]);
if (referenced.length === 0) problems.push("no assets referenced by index.html — the check is not looking at anything");
for (const asset of referenced) {
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

for (const card of ["og.png", "og-de.png"]) {
  if (!existsSync(join(docs, card))) problems.push(`docs/${card} is missing`);
}

/*
 * The social card is committed rather than built, so it can go stale on its
 * own. It once did: the site was redesigned and the card carried on rendering
 * the old headline in the old colours, and nothing caught it. Its bytes cannot
 * be compared — sharp's output depends on whichever libvips the machine has —
 * but the inputs it was made from are written beside it and compare exactly.
 */
for (const lang of CARD_LANGUAGES) {
  const inputsPath = join(web, `og.inputs${lang === "en" ? "" : `-${lang}`}.json`);
  if (!existsSync(inputsPath)) {
    problems.push(`web/${basename(inputsPath)} is missing — run \`npm run og\``);
    continue;
  }
  if (readFileSync(inputsPath, "utf8").trim() !== JSON.stringify(cardInputs(lang), null, 2)) {
    problems.push(
      `the ${lang} social card was made from a headline, palette or typeface the\n` +
        "    site no longer uses. Run `npm run og` and commit the result.",
    );
  }
}
if (!existsSync(join(docs, "privacy", "index.html"))) {
  problems.push("docs/privacy/index.html has gone — that URL is in App Store Connect");
}

/*
 * The German policy is not a nicety. The German page links to it, and a German
 * page whose privacy link opens English is the half-translated state the
 * second language exists to prevent — on the one page where a reader is
 * entitled to their own language.
 *
 * Both are checked for the sections rather than merely for existing: a policy
 * missing a heading is a legal gap, not a formatting one, and the German page
 * is generated from the English by substitution precisely so the two cannot
 * drift. This is what says they have not.
 */
const policies = [
  ["docs/privacy/index.html", join(docs, "privacy", "index.html")],
  ["docs/privacy/de/index.html", join(docs, "privacy", "de", "index.html")],
];
const headingCounts = [];
for (const [name, path] of policies) {
  if (!existsSync(path)) {
    problems.push(`${name} has gone — the German page links it`);
    continue;
  }
  headingCounts.push([name, (readFileSync(path, "utf8").match(/<h2[\s>]/g) ?? []).length]);
}
if (headingCounts.length === 2 && headingCounts[0][1] !== headingCounts[1][1]) {
  problems.push(
    `the policies have drifted: ${headingCounts[0][0]} has ${headingCounts[0][1]} sections, ` +
      `${headingCounts[1][0]} has ${headingCounts[1][1]}`,
  );
}

/*
 * Without CNAME, Pages drops the custom domain and serves the site back at
 * apectro.github.io/Hours/ — where every rooted asset path 404s, so the page
 * would come up unstyled rather than not at all.
 */
const cname = join(docs, "CNAME");
if (!existsSync(cname)) {
  problems.push("docs/CNAME is missing — Pages would drop zeitkonto.app");
} else if (readFileSync(cname, "utf8").trim() !== "zeitkonto.app") {
  problems.push(`docs/CNAME says "${readFileSync(cname, "utf8").trim()}", not zeitkonto.app`);
}

if (problems.length > 0) {
  console.error("\ndocs/ is out of date:\n");
  for (const problem of problems) console.error(`  - ${problem}`);
  console.error("\nRun `npm run publish` in web/ and commit the result.\n");
  process.exit(1);
}

console.log("docs/ matches what web/ builds.");
