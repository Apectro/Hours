import { useRef, useState } from "react";
import {
  appStore,
  balance,
  cases,
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
 * One screenshot, at the several widths scripts/images.mjs writes. `sizes`
 * has to be given per use, because the browser picks a file before it has any
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
    <section className="hero" id="top">
      <div className="shell hero-grid">
        <div>
          <p className="eyebrow">A work-hours calendar for iPhone</p>
          <h1>Your hours, on your phone, and nowhere else.</h1>
          <p className="lede">
            Record what you worked on a calendar, see where your balance stands,
            and hand payroll a timesheet in their language. No account, no
            server, nothing collected.
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
            {appStore ? null : "Not on the App Store yet. "}
            Free to record your hours, and that part stays free. Requires iOS 17.
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

      <div className="shell">
        <div className="equation" role="figure" aria-label="How the balance is calculated">
          <p className="equation-label">The balance is one line</p>
          <p className="equation-line">
            {balance.map((part, index) => (
              <span key={index} className={part.kind}>
                {part.text}
              </span>
            ))}
          </p>
          <div className="equation-foot">
            <p>
              Every day type carries a policy saying how it counts, so the same
              line is right in every case — and worked time and paid absence are
              always reported apart, never added together.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}

function Balance() {
  return (
    <section className="tinted" id="balance">
      <div className="shell">
        <div className="section-head">
          <p className="eyebrow">Why the line matters</p>
          <h2>Six days a timesheet has to get right</h2>
          <p>
            Anything can add up hours. The difficulty is the days that are not
            simply worked or not worked — and every one of these is a way to lose
            somebody a day if the app decides it carelessly.
          </p>
        </div>
        <div className="table-scroll">
          <table className="cases">
            <caption>
              An eight-hour contracted day, Monday to Friday.
            </caption>
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
    <section id="app">
      <div className="shell">
        <div className="section-head">
          <p className="eyebrow">What it is</p>
          <h2>A calendar first, and configurable to the bone</h2>
          <p>
            Every field is behind a switch, and anything you switch off
            disappears rather than sitting greyed out. An app for recording eight
            hours a day should not make you scroll past nine fields you never
            use.
          </p>
        </div>
        <div className="cards">
          {howItWorks.map((item) => (
            <article className="card" key={item.title}>
              <span className="tag">{item.tag}</span>
              <h3>{item.title}</h3>
              <p>{item.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function Gallery() {
  return (
    <section className="tinted">
      <div className="shell">
        <div className="section-head">
          <p className="eyebrow">On the phone</p>
          <h2>Five screens, all of them real</h2>
          <p>
            These are captured from the app by its own test suite on every
            build, so they cannot drift from what you would actually see.
          </p>
        </div>
        <div className="gallery">
          {shots.map((shot) => (
            <figure key={shot.shot}>
              <Shot shot={shot.shot} alt={shot.alt} sizes="225px" loading="lazy" />
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
 * Only the selected image is in the DOM, so switching costs one request
 * rather than all four up front; hovering or focusing a tab starts that
 * request early, which is enough to make the swap look instant without
 * spending the bytes on somebody who never touches it.
 */
function TimesheetProof() {
  const { languages, width, height } = timesheetProof;
  const [selected, setSelected] = useState(0);
  const tabs = useRef<(HTMLButtonElement | null)[]>([]);
  const current = languages[selected];

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
    const step =
      event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
    let next = selected;
    if (step !== 0) next = (selected + step + languages.length) % languages.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = languages.length - 1;
    else return;
    event.preventDefault();
    setSelected(next);
    tabs.current[next]?.focus();
  };

  return (
    <figure className="proof">
      <div className="proof-tabs" role="tablist" aria-label="Timesheet language">
        {languages.map((language, index) => (
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
        weekday, day type and date format is translated — and the note is not,
        because those are the words you typed. These four are rendered on every
        build; the other six are covered by tests.
      </figcaption>
    </figure>
  );
}

function Timesheets() {
  return (
    <section id="timesheets">
      <div className="shell">
        <div className="section-head">
          <p className="eyebrow">What you hand over</p>
          <h2>A timesheet in the language of whoever reads it</h2>
          <p>
            Export a day, a week, a month, a year or any range you choose, as
            CSV, Excel or PDF. Columns are yours to pick and reorder, your name
            goes on it, and you name the file. The Excel file holds real
            durations behind an hours-and-minutes format, so a column of hours
            can still be summed.
          </p>
        </div>
        <TimesheetProof />

        <div className="cards">
          <article className="card">
            <span className="tag">Independent of the app</span>
            <h3>Ten languages</h3>
            <p>
              The file's language is its own setting: the person reading a
              timesheet is often not the person who recorded it. Keep the phone in
              English and hand payroll a sheet that says <em>Gesamt gearbeitet</em>.
            </p>
            <ul className="languages">
              {languages.map((language) => (
                <li key={language}>{language}</li>
              ))}
            </ul>
          </article>
          <article className="card">
            <span className="tag">Yours stays yours</span>
            <h3>Only the app's own words</h3>
            <p>
              Column titles, the day types it ships with and the summary labels
              are translated. A note you typed, a job you named, a day type you
              invented — those come out exactly as you wrote them, because
              translating somebody's own words would be a fabrication.
            </p>
          </article>
        </div>
      </div>
    </section>
  );
}

function Privacy() {
  return (
    <section className="tinted" id="privacy">
      <div className="shell">
        <div className="section-head">
          <p className="eyebrow">Privacy</p>
          <h2>Claims you can check, next to what makes them true</h2>
          <p>
            The app is a file on your phone. There is no account to make and no
            server to send anything to, and the source is public, so none of this
            has to be taken on trust.
          </p>
        </div>
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
    <section id="pricing">
      <div className="shell">
        <div className="section-head">
          <p className="eyebrow">What it costs</p>
          <h2>Free to record. Pay only to produce.</h2>
          <p>
            Nothing you have recorded is ever held behind a payment. If a
            subscription lapses every figure is still there and the backup still
            writes — what is paid for is making documents out of it.
          </p>
        </div>
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
          Hours is made by one person. There is no company behind it and no
          analytics in it.
        </p>
        <nav aria-label="Elsewhere">
          <a href={PRIVACY}>Privacy policy</a>
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
      <Masthead />
      <main>
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
