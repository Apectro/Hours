import { useRef, useState } from "react";
import { appStore, languages, shotSize, timesheetProof } from "./content";
import { copy, language, otherLanguageHref } from "./copy";
import { hasGermanShots } from "./content";

/**
 * Which set of screenshots this page shows.
 *
 * The German page should show a German app. Its captures come from the same
 * test suite run with -testLanguage de, and land under shots/de/ with the same
 * base names — so until CI has produced a set, this falls back to the English
 * ones and the page is merely imperfect rather than broken.
 */
const SHOTS = language === "de" && hasGermanShots ? "/shots/de" : "/shots";

const REPO = "https://github.com/Apectro/Hours";
// Absolute: the German page sits at /de/, and one privacy policy serves both.
const PRIVACY = "/privacy/";

/**
 * One screenshot, at the several widths scripts/images.mjs writes. `sizes` has
 * to be given per use, because the browser picks a file before it has any
 * layout to measure and would otherwise assume the image fills the viewport.
 */
function Shot({
  shot,
  alt,
  sizes,
  loading,
}: {
  shot: string;
  alt: string;
  sizes: string;
  loading?: "lazy";
}) {
  return (
    <picture>
      <source
        type="image/webp"
        sizes={sizes}
        srcSet={`${SHOTS}/${shot}.480.webp 480w, ${SHOTS}/${shot}.960.webp 960w`}
      />
      <img
        src={`${SHOTS}/${shot}.640.png`}
        alt={alt}
        width={shotSize.width}
        height={shotSize.height}
        loading={loading}
      />
    </picture>
  );
}

/**
 * A ledger row: the label on the left, the entry on the right. This is the
 * page's one structural device, and it does the work that an eyebrow over
 * every section and a grid of rounded cards were doing before.
 */
function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="row">
      <div className="row-label">{label}</div>
      <div className="row-body">{children}</div>
    </div>
  );
}

/**
 * Light, dark, or whatever the machine says.
 *
 * The stylesheet has always had all three states — a bare :root, a
 * prefers-color-scheme block, and a [data-theme] block that wins over both.
 * Nothing ever stamped that attribute, so the third of those was dead code and
 * a visitor whose laptop was in dark mode had no way to read the page in
 * light. This is what stamps it.
 *
 * "Auto" removes the attribute rather than setting a value, which is the
 * difference between following the system and guessing at it once.
 */
const THEMES = [
  { value: "", label: copy.theme.auto },
  { value: "light", label: copy.theme.light },
  { value: "dark", label: copy.theme.dark },
];

function ThemeChoice() {
  const [theme, setTheme] = useState(() => {
    try {
      const saved = localStorage.getItem("hours-theme");
      return saved === "light" || saved === "dark" ? saved : "";
    } catch {
      return "";
    }
  });
  const buttons = useRef<(HTMLButtonElement | null)[]>([]);
  const index = THEMES.findIndex((option) => option.value === theme);

  const choose = (value: string) => {
    setTheme(value);
    const root = document.documentElement;
    if (value) root.dataset.theme = value;
    else delete root.dataset.theme;
    try {
      if (value) localStorage.setItem("hours-theme", value);
      else localStorage.removeItem("hours-theme");
    } catch {
      // A page that cannot remember the choice can still honour it.
    }
  };

  /* A radiogroup moves with the arrow keys and holds one tab stop. */
  const onKeyDown = (event: React.KeyboardEvent) => {
    const step = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
    let next = index;
    if (step !== 0) next = (index + step + THEMES.length) % THEMES.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = THEMES.length - 1;
    else return;
    event.preventDefault();
    choose(THEMES[next].value);
    buttons.current[next]?.focus();
  };

  return (
    <div className="theme" role="radiogroup" aria-label={copy.nav.theme}>
      {THEMES.map((option, position) => (
        <button
          key={option.label}
          ref={(node) => {
            buttons.current[position] = node;
          }}
          type="button"
          role="radio"
          aria-checked={option.value === theme}
          tabIndex={position === index ? 0 : -1}
          onClick={() => choose(option.value)}
          onKeyDown={onKeyDown}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

function Masthead() {
  return (
    <header className="masthead">
      <div className="shell masthead-inner">
        <a className="wordmark" href="#top">
          <span className="mark" aria-hidden="true">
            z
          </span>
          Zeitkonto
        </a>
        <div className="masthead-end">
          <nav aria-label={copy.nav.sections}>
            <a href="#balance">{copy.nav.balance}</a>
            <a href="#app">{copy.nav.app}</a>
            <a href="#timesheets">{copy.nav.timesheets}</a>
            <a href="#privacy">{copy.nav.privacy}</a>
            <a href="#pricing">{copy.nav.pricing}</a>
          </nav>
          <a className="lang-switch" href={otherLanguageHref} hrefLang={language === "de" ? "en" : "de"}>
            <span className="at-wide">{copy.otherLanguage}</span>
            <span className="at-narrow">{copy.otherLanguageShort}</span>
          </a>
          <ThemeChoice />
        </div>
      </div>
    </header>
  );
}

function Hero() {
  return (
    <section className="sheet hero" id="top">
      <div className="shell">
        <div className="hero-grid">
          <div>
            <h1>
              {copy.hero.headlineLines.map((line, index) => (
                <span key={line}>
                  {index > 0 ? " " : null}
                  {line}
                </span>
              ))}
            </h1>
            <p className="lede">{copy.hero.lede}</p>

            <div className="hero-actions">
              {appStore ? (
                <a className="button primary" href={appStore}>
                  {copy.hero.appStoreAction}
                </a>
              ) : null}
              <a className={`button ${appStore ? "secondary" : "primary"}`} href="#pricing">
                {copy.hero.costAction}
              </a>
              <a className="button secondary" href={REPO}>
                {copy.hero.sourceAction}
              </a>
            </div>
            <p className="hero-note">
              {appStore ? null : copy.hero.notYet}
              {copy.hero.note}
            </p>
          </div>

          <div className="hero-shot">
            <Shot
              shot="01-calendar"
              alt={copy.hero.shotAlt}
              sizes="320px"
            />
          </div>
        </div>

        <div className="equation" role="figure" aria-label={copy.equation.figureLabel}>
          <p className="equation-label">{copy.equation.label}</p>
          <p className="equation-line">
            {copy.equation.parts.map(([text, kind], index) => (
              <span key={index} className={kind}>
                {text}
              </span>
            ))}
          </p>
          <div className="equation-foot">
            <p>{copy.equation.foot}</p>
          </div>
        </div>
      </div>
    </section>
  );
}

function Balance() {
  return (
    <section className="sheet sunk" id="balance">
      <div className="shell">
        <h2>{copy.balance.heading}</h2>
        <p className="lede">{copy.balance.lede}</p>
        <div className="table-scroll">
          <table className="cases">
            <caption>{copy.balance.caption}</caption>
            <thead>
              <tr>
                <th scope="col">{copy.balance.columns.day}</th>
                <th scope="col">{copy.balance.columns.balance}</th>
                <th scope="col">{copy.balance.columns.why}</th>
              </tr>
            </thead>
            <tbody>
              {copy.balance.cases.map((row) => (
                <tr key={row.day}>
                  <td>{row.day}</td>
                  <td className={`figure ${row.sign}`}>{row.result}</td>
                  <td className="why">{row.why}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}

function HowItWorks() {
  return (
    <section className="sheet" id="app">
      <div className="shell">
        <h2>{copy.app.heading}</h2>
        <p className="lede">{copy.app.lede}</p>
        <div className="ledger">
          {copy.app.rows.map((item) => (
            <Row key={item.title} label={item.label}>
              <h3>{item.title}</h3>
              <p>{item.body}</p>
            </Row>
          ))}
        </div>
      </div>
    </section>
  );
}

function Gallery() {
  return (
    <section className="sheet sunk">
      <div className="shell">
        <h2>{copy.gallery.heading}</h2>
        <p className="lede">{copy.gallery.lede}</p>
        <div className="gallery">
          {copy.gallery.shots.map((shot) => (
            <figure key={shot.shot}>
              <Shot shot={shot.shot} alt={shot.alt} sizes="260px" loading="lazy" />
              <figcaption>
                <strong>{shot.title}</strong>
                {shot.caption}
              </figcaption>
            </figure>
          ))}
        </div>
      </div>
    </section>
  );
}

/** Shared by the markup and the preload, which have to agree to be useful. */
const PROOF_SIZES = "(max-width: 1160px) 92vw, 1040px";

const proofSrcSet = (code: string) =>
  `/shots/timesheet-${code}.800.webp 800w, /shots/timesheet-${code}.1570.webp 1570w`;

/**
 * The same export in four languages, as tabs.
 *
 * Only the selected image is in the DOM, so switching costs one request rather
 * than all four up front. Hovering or focusing a tab starts that request
 * early, which is enough to make the swap look instant without spending the
 * bytes on somebody who never touches it.
 */
function TimesheetProof() {
  const { languages: proofLanguages, width, height } = timesheetProof;
  const [selected, setSelected] = useState(0);
  const tabs = useRef<(HTMLButtonElement | null)[]>([]);
  const current = proofLanguages[selected];

  const preload = (code: string) => {
    // Give the preload the same srcset and sizes the markup uses, so the
    // browser picks the file it is about to need. Naming one width here
    // instead would fetch a second copy rather than save a request.
    const image = new Image();
    image.sizes = PROOF_SIZES;
    image.srcset = proofSrcSet(code);
  };

  /* Arrow keys move between tabs, which is what a tablist is expected to do. */
  const onKeyDown = (event: React.KeyboardEvent) => {
    const step = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
    let next = selected;
    if (step !== 0) next = (selected + step + proofLanguages.length) % proofLanguages.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = proofLanguages.length - 1;
    else return;
    event.preventDefault();
    setSelected(next);
    tabs.current[next]?.focus();
  };

  return (
    <figure className="proof">
      <div className="proof-tabs" role="tablist" aria-label={copy.timesheets.tablistLabel}>
        {proofLanguages.map((language, index) => (
          <button
            key={language.code}
            ref={(node) => {
              tabs.current[index] = node;
            }}
            type="button"
            role="tab"
            id={`tab-${language.code}`}
            aria-selected={index === selected}
            aria-controls={`panel-${language.code}`}
            tabIndex={index === selected ? 0 : -1}
            onClick={() => setSelected(index)}
            onKeyDown={onKeyDown}
            onPointerEnter={() => preload(language.code)}
            onFocus={() => preload(language.code)}
          >
            {language.label}
          </button>
        ))}
      </div>

      <div
        className="proof-frame"
        role="tabpanel"
        id={`panel-${current.code}`}
        aria-labelledby={`tab-${current.code}`}
      >
        <picture key={current.code}>
          <source type="image/webp" sizes={PROOF_SIZES} srcSet={proofSrcSet(current.code)} />
          <img
            src={`/shots/timesheet-${current.code}.800.png`}
            alt={current.alt}
            width={width}
            height={height}
            loading="lazy"
          />
        </picture>
      </div>

      <figcaption>
        <strong>
          {copy.timesheets.proofLead(copy.timesheets.proofLanguages[current.code])}
        </strong>
        {copy.timesheets.proofRest}
      </figcaption>
    </figure>
  );
}

function Timesheets() {
  return (
    <section className="sheet" id="timesheets">
      <div className="shell">
        <h2>{copy.timesheets.heading}</h2>
        <p className="lede">{copy.timesheets.lede}</p>

        <TimesheetProof />

        <div className="ledger">
          <Row label={copy.timesheets.rows.settable.label}>
            <h3>{copy.timesheets.rows.settable.title}</h3>
            <p>
              {copy.timesheets.rows.settable.bodyBefore}
              <em>{copy.timesheets.rows.settable.bodyEm}</em>
              {copy.timesheets.rows.settable.bodyAfter}
            </p>
            <ul className="languages">
              {languages.map((language) => (
                <li key={language}>{language}</li>
              ))}
            </ul>
          </Row>
          <Row label={copy.timesheets.rows.untouched.label}>
            <h3>{copy.timesheets.rows.untouched.title}</h3>
            <p>{copy.timesheets.rows.untouched.body}</p>
          </Row>
        </div>
      </div>
    </section>
  );
}

function Privacy() {
  return (
    <section className="sheet sunk" id="privacy">
      <div className="shell">
        <h2>{copy.privacy.heading}</h2>
        <p className="lede">{copy.privacy.lede}</p>
        <dl className="claims">
          {copy.privacy.claims.map((item) => (
            <div className="claim" key={item.claim}>
              <dt>{item.claim}</dt>
              <dd>{item.evidence}</dd>
            </div>
          ))}
        </dl>
      </div>
    </section>
  );
}

function Pricing() {
  return (
    <section className="sheet" id="pricing">
      <div className="shell">
        <h2>{copy.pricing.heading}</h2>
        <p className="lede">{copy.pricing.lede}</p>
        <div className="pricing">
          {copy.pricing.plans.map((plan) => (
            <article className={`plan${plan.highlight ? " highlight" : ""}`} key={plan.name}>
              <h3>{plan.name}</h3>
              <p className="price">{plan.price}</p>
              <ul>
                {plan.items.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer>
      <div className="shell footer-inner">
        <p>{copy.footer.line}</p>
        <nav aria-label={copy.nav.elsewhere}>
          <a href={PRIVACY}>{copy.footer.privacy}</a>
          <a href={REPO}>{copy.footer.source}</a>
          <a href={`${REPO}/issues`}>{copy.footer.support}</a>
        </nav>
      </div>
    </footer>
  );
}

export default function App() {
  return (
    <>
      <a className="skip" href="#main">
        {copy.skip}
      </a>
      <Masthead />
      <main id="main">
        <Hero />
        <Balance />
        <HowItWorks />
        <Gallery />
        <Timesheets />
        <Privacy />
        <Pricing />
      </main>
      <Footer />
    </>
  );
}
