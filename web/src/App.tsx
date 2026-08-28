import { useRef, useState } from "react";
import {
  appStore,
  balance,
  cases,
  headlineLines,
  howItWorks,
  languages,
  plans,
  privacyClaims,
  shotSize,
  shots,
  timesheetProof,
} from "./content";

const REPO = "https://github.com/Apectro/Hours";
const PRIVACY = "privacy/";

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
        srcSet={`shots/${shot}.480.webp 480w, shots/${shot}.960.webp 960w`}
      />
      <img
        src={`shots/${shot}.640.png`}
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

function Masthead() {
  return (
    <header className="masthead">
      <div className="shell masthead-inner">
        <a className="wordmark" href="#top">
          <span className="mark" aria-hidden="true">
            h
          </span>
          Hours
        </a>
        <nav aria-label="Sections">
          <a href="#balance">The balance</a>
          <a href="#app">The app</a>
          <a href="#timesheets">Timesheets</a>
          <a href="#privacy">Privacy</a>
          <a href="#pricing">Pricing</a>
        </nav>
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
              {headlineLines.map((line, index) => (
                <span key={line}>
                  {index > 0 ? " " : null}
                  {line}
                </span>
              ))}
            </h1>
            <p className="lede">
              Tap a day, put your hours in, and the month adds itself up. When
              payroll wants a timesheet you export one, in whatever language
              they read. There's no account to make and nowhere for any of it
              to go.
            </p>

            <div className="hero-actions">
              {appStore ? (
                <a className="button primary" href={appStore}>
                  Get it on the App Store
                </a>
              ) : null}
              <a className={`button ${appStore ? "secondary" : "primary"}`} href="#pricing">
                What it costs
              </a>
              <a className="button secondary" href={REPO}>
                Read the source
              </a>
            </div>
            <p className="hero-note">
              {appStore ? null : "It isn't on the App Store yet. "}
              Recording your hours is free and stays free. Needs iOS 17.
            </p>
          </div>

          <div className="hero-shot">
            <Shot
              shot="01-calendar"
              alt="Hours on an iPhone, showing a month of days coloured by type with totals beneath"
              sizes="320px"
            />
          </div>
        </div>

        <div className="equation" role="figure" aria-label="How the balance is calculated">
          <p className="equation-label">It all comes down to one line</p>
          <p className="equation-line">
            {balance.map((part, index) => (
              <span key={index} className={part.kind}>
                {part.text}
              </span>
            ))}
          </p>
          <div className="equation-foot">
            <p>
              Each day type carries a policy saying how it counts, which is why
              the same line works whether you were at work, on leave or off
              sick. Worked time and paid absence are always reported
              separately. Adding them together is how you end up with a figure
              nobody can explain.
            </p>
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
        <h2>Six days a timesheet has to get right</h2>
        <p className="lede">
          Adding up hours is the easy part. What's hard is the days that aren't
          simply worked or not worked, and there are more of those than you'd
          think. Get one of them wrong and somebody is short a day.
        </p>
        <div className="table-scroll">
          <table className="cases">
            <caption>An eight-hour contracted day, Monday to Friday.</caption>
            <thead>
              <tr>
                <th scope="col">The day</th>
                <th scope="col">Balance</th>
                <th scope="col">Why</th>
              </tr>
            </thead>
            <tbody>
              {cases.map((row) => (
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
        <h2>A calendar first, and configurable to the bone</h2>
        <p className="lede">
          Every field sits behind a switch, and anything you switch off
          disappears instead of sitting there greyed out. An app for recording
          eight hours a day shouldn't make you scroll past nine fields you
          never use.
        </p>
        <div className="ledger">
          {howItWorks.map((item) => (
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
        <h2>What it actually looks like</h2>
        <p className="lede">
          Every one of these comes out of the app's own test suite on each
          build, so they can't quietly drift from the thing you'd install.
        </p>
        <div className="gallery">
          {shots.map((shot) => (
            <figure key={shot.shot}>
              <Shot shot={shot.shot} alt={shot.alt} sizes="200px" loading="lazy" />
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
  `shots/timesheet-${code}.800.webp 800w, shots/timesheet-${code}.1570.webp 1570w`;

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
      <div className="proof-tabs" role="tablist" aria-label="Timesheet language">
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
            src={`shots/timesheet-${current.code}.800.png`}
            alt={current.alt}
            width={width}
            height={height}
            loading="lazy"
          />
        </picture>
      </div>

      <figcaption>
        <strong>A real export, in {current.english}.</strong> Every heading,
        weekday, day type and date format is translated. The note isn't,
        because those are words you typed. These four get rendered on every
        build; the other six are covered by tests.
      </figcaption>
    </figure>
  );
}

function Timesheets() {
  return (
    <section className="sheet" id="timesheets">
      <div className="shell">
        <h2>A timesheet in the language of whoever reads it</h2>
        <p className="lede">
          Pick any range you like, a week or a month or the 3rd to the 19th,
          and export it as CSV, Excel or PDF. You choose the columns and their
          order, your name goes at the top, and you name the file. The Excel
          version keeps real durations behind the hours-and-minutes formatting,
          so the column still adds up.
        </p>

        <TimesheetProof />

        <div className="ledger">
          <Row label="Set separately">
            <h3>Ten languages</h3>
            <p>
              The file's language is its own setting, because the person
              reading a timesheet usually isn't the person who filled it in.
              Keep your phone in English and hand payroll a sheet that says{" "}
              <em>Gesamt gearbeitet</em>.
            </p>
            <ul className="languages">
              {languages.map((language) => (
                <li key={language}>{language}</li>
              ))}
            </ul>
          </Row>
          <Row label="Left alone">
            <h3>Only the app's own words</h3>
            <p>
              Column titles, the day types it ships with and the summary labels
              all get translated. A note you typed, a job you named, a day type
              you invented: those come out exactly as you wrote them.
              Translating somebody's own words would be making things up.
            </p>
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
        <h2>Every promise here, and where to check it</h2>
        <p className="lede">
          The app is a file on your phone. There's no account to make and no
          server to send anything to, and the source is public, so you don't
          have to take any of this on trust.
        </p>
        <dl className="claims">
          {privacyClaims.map((item) => (
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
        <h2>Recording is free. You pay to make documents.</h2>
        <p className="lede">
          Nothing you've recorded ever gets locked up. If a subscription lapses
          every figure is still there and the backup still writes. What you're
          paying for is turning it into a file somebody else can read.
        </p>
        <div className="pricing">
          {plans.map((plan) => (
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
        <p>
          Hours is made by one person. No company behind it, and nothing in it
          that phones home.
        </p>
        <nav aria-label="Elsewhere">
          <a href={PRIVACY}>Privacy</a>
          <a href={REPO}>Source</a>
          <a href={`${REPO}/issues`}>Support</a>
        </nav>
      </div>
    </footer>
  );
}

export default function App() {
  return (
    <>
      <a className="skip" href="#main">
        Skip to content
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
