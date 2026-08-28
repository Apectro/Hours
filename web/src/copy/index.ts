import { en, type Copy } from "./en";
import { de } from "./de";

/**
 * Which language this build is.
 *
 * The site is built twice, once per language, rather than switched at
 * runtime: that way each page has the right `lang` attribute, the right title
 * and description for search and for link previews, and no flash of the wrong
 * language while JavaScript starts.
 */
const LANGUAGES: Record<string, Copy> = { en, de };

const requested = import.meta.env.VITE_LANG ?? "en";
export const copy: Copy = LANGUAGES[requested] ?? en;
export const language = copy.lang;

/** Where the other language's copy of this page lives. */
export const otherLanguageHref = language === "de" ? "../" : "de/";
export type { Copy };
