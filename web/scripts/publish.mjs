/**
 * Build the site and put it where GitHub Pages already looks.
 *
 * Pages on this repository serves `main:/docs`, and the privacy policy at
 * zeitkonto.app/privacy/ is the URL App Store Connect holds. Changing the
 * Pages source to an Actions workflow would break that URL for as long as it
 * took somebody to notice, so the built site is copied into docs/ instead and
 * the hand-written pages there are left where they are.
 *
 * It works by keeping a short list of what is hand-written and clearing
 * everything else. The obvious way round — listing what the build produces and
 * deleting only that — was the first version, and it leaks: a file that stops
 * being an output is never named again, so it stays published forever. That
 * happened, with a build record that had moved out of public/. A keep-list
 * cannot leak, and the one thing that must never be deleted is on it and is
 * checked for afterwards.
 */
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { cpSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const web = dirname(dirname(fileURLToPath(import.meta.url)));
const docs = join(web, "..", "docs");

/** Hand-written, and never touched by a publish. Everything else is output. */
const KEEP = new Set(["privacy", "README.md", "app-store-listing.md"]);

/*
 * Resize the screenshots first. `npm run build` gets this through npm's
 * prebuild hook, but this script calls vite directly, so the hook never fired
 * and publish quietly used whatever public/shots happened to hold from the
 * last build somebody ran by hand. A German set generated after the last
 * build was therefore never published, and nothing said so.
 */
execFileSync("node", ["scripts/images.mjs"], { cwd: web, stdio: "inherit" });

// Both languages: English at the root, German into dist/de.
execFileSync("npx", ["vite", "build"], { cwd: web, stdio: "inherit" });
execFileSync("npx", ["vite", "build"], {
  cwd: web,
  stdio: "inherit",
  env: { ...process.env, VITE_LANG: "de" },
});

mkdirSync(docs, { recursive: true });
const removed = [];
for (const name of readdirSync(docs)) {
  if (KEEP.has(name)) continue;
  rmSync(join(docs, name), { recursive: true, force: true });
  removed.push(name);
}

cpSync(join(web, "dist"), docs, { recursive: true });

// Pages runs Jekyll unless told not to, which would skip any file whose name
// begins with an underscore. Vite emits none today; this covers a future one.
writeFileSync(join(docs, ".nojekyll"), "");

/* The whole point of publishing this way. Fail loudly rather than quietly. */
if (!existsSync(join(docs, "privacy", "index.html"))) {
  throw new Error("docs/privacy/index.html is gone — that URL is in App Store Connect");
}

console.log(`Published into docs/ (cleared ${removed.length}, kept ${[...KEEP].join(", ")})`);
