/**
 * Build the site and put it where GitHub Pages already looks.
 *
 * Pages on this repository serves `main:/docs`, and the privacy policy at
 * /Hours/privacy/ is the URL App Store Connect holds. Changing the Pages
 * source to an Actions workflow would break that URL for as long as it took
 * somebody to notice, so the built site is copied into docs/ instead and the
 * hand-written pages there are left exactly where they are.
 *
 * Only the files the build itself produces are removed before copying, so a
 * stale asset from a previous build cannot survive and nothing written by
 * hand can be deleted.
 */
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const web = dirname(dirname(fileURLToPath(import.meta.url)));
const docs = join(web, "..", "docs");

/** Everything the build owns in docs/. Nothing else is ever touched. */
const built = ["index.html", "assets", "shots", "icon.svg", ".nojekyll"];

execFileSync("npx", ["vite", "build"], { cwd: web, stdio: "inherit" });

for (const name of built) {
  const path = join(docs, name);
  if (existsSync(path)) rmSync(path, { recursive: true, force: true });
}

cpSync(join(web, "dist"), docs, { recursive: true });

// Pages runs Jekyll unless told not to, which would skip any file whose name
// begins with an underscore. Vite does not emit one today; this makes sure a
// future one is still served.
writeFileSync(join(docs, ".nojekyll"), "");

console.log(`Copied the built site into docs/ — ${built.join(", ")}`);
