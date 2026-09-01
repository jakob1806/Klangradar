"use client";

import Image from "next/image";
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import styles from "./portal-mockup.module.css";

const variants = [
  { name: "Editorial Desk", component: EditorialDesk },
  { name: "Studio Console", component: StudioConsole },
  { name: "Season Board", component: SeasonBoard },
] as const;

const events = [
  { day: "04", month: "SEP", title: "Mahler: 3. Symphonie", venue: "Isarphilharmonie", time: "20:00", state: "Veröffentlicht" },
  { day: "12", month: "SEP", title: "Bartók und Schostakowitsch", venue: "Herkulessaal", time: "19:30", state: "Entwurf" },
  { day: "19", month: "SEP", title: "Kammerkonzert der Akademie", venue: "Prinzregententheater", time: "18:00", state: "Unvollständig" },
];

export function OrganizerPortalMockup({ initialVariant = 0 }: { initialVariant?: number }) {
  const [current, setCurrent] = useState(initialVariant);
  const pickerRef = useRef<HTMLElement>(null);
  const highlightRef = useRef<HTMLSpanElement>(null);
  const itemRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const ActiveVariant = variants[current].component;

  const moveHighlight = useCallback(() => {
    const item = itemRefs.current[current];
    const highlight = highlightRef.current;
    if (!item || !highlight) return;
    highlight.style.width = `${item.offsetWidth}px`;
    highlight.style.transform = `translateX(${item.offsetLeft}px)`;
  }, [current]);

  const choose = useCallback((index: number) => {
    if (index < 0 || index >= variants.length) return;
    setCurrent(index);
    const url = new URL(window.location.href);
    url.searchParams.set("v", String(index + 1));
    window.history.replaceState(null, "", url);
  }, []);

  useLayoutEffect(() => {
    moveHighlight();
    const readyTimer = window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => pickerRef.current?.setAttribute("data-ready", ""));
    });
    return () => window.cancelAnimationFrame(readyTimer);
  }, [moveHighlight]);

  useEffect(() => {
    const onResize = () => moveHighlight();
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement;
      if (/^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName) || target.isContentEditable) return;
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      const number = Number.parseInt(event.key, 10);
      if (number >= 1 && number <= variants.length) choose(number - 1);
      else if (event.key === "ArrowRight") choose((current + 1) % variants.length);
      else if (event.key === "ArrowLeft") choose((current - 1 + variants.length) % variants.length);
    };
    window.addEventListener("resize", onResize);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      window.removeEventListener("resize", onResize);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [choose, current, moveHighlight]);

  return (
    <>
      <div className={styles.stage} key={current}>
        <ActiveVariant />
      </div>
      <nav ref={pickerRef} className="proto-picker" aria-label="Prototype variants">
        <span ref={highlightRef} className="proto-picker-highlight" aria-hidden="true" />
        {variants.map((variant, index) => (
          <button
            key={variant.name}
            ref={(node) => { itemRefs.current[index] = node; }}
            className="proto-picker-item"
            data-active={index === current ? "" : undefined}
            aria-current={index === current ? "true" : undefined}
            onClick={() => choose(index)}
          >
            {variant.name}
          </button>
        ))}
      </nav>
    </>
  );
}

function Brand({ inverse = false }: { inverse?: boolean }) {
  return (
    <div className={`${styles.brand} ${inverse ? styles.brandInverse : ""}`}>
      <span className={styles.brandMark}><Image src="/app-logo.svg" alt="" width={34} height={34} /></span>
      <span><strong>Klangradar</strong><small>für Veranstalter</small></span>
    </div>
  );
}

function EventRows({ compact = false }: { compact?: boolean }) {
  return (
    <div className={`${styles.eventRows} ${compact ? styles.eventRowsCompact : ""}`}>
      {events.map((event) => (
        <article className={styles.eventRow} key={event.title}>
          <time><strong>{event.day}</strong><span>{event.month}</span></time>
          <div className={styles.eventIdentity}><strong>{event.title}</strong><span>{event.venue} · {event.time}</span></div>
          <span className={`${styles.eventState} ${event.state === "Veröffentlicht" ? styles.statePublished : ""}`}>{event.state}</span>
          <button aria-label={`${event.title} bearbeiten`}>Bearbeiten</button>
        </article>
      ))}
    </div>
  );
}

function EditorialDesk() {
  return (
    <main className={`${styles.portal} ${styles.editorial}`}>
      <header className={styles.editorialHeader}>
        <Brand />
        <nav><a data-active>Übersicht</a><a>Veranstaltungen</a><a>Serien</a><a>Bibliothek</a><a>Auswertung</a></nav>
        <button className={styles.accountButton}>JL</button>
      </header>
      <section className={styles.editorialHero}>
        <div>
          <p className={styles.kicker}>Sonntag, 31. August</p>
          <h1>Guten Morgen,<br />Jakob.</h1>
        </div>
        <div className={styles.editorialHeroActions}>
          <p>Drei Veranstaltungen brauchen vor der Veröffentlichung noch deine Aufmerksamkeit.</p>
          <button className={styles.primaryAction}>Neue Veranstaltung</button>
        </div>
      </section>
      <section className={styles.editorialStatus}>
        <div><span>Nächster Termin</span><strong>in 4 Tagen</strong><small>Mahler: 3. Symphonie</small></div>
        <div><span>September</span><strong>8 Termine</strong><small>6 veröffentlicht, 2 Entwürfe</small></div>
        <div><span>Profilqualität</span><strong>92 Prozent</strong><small>Biografie und Pressefoto vollständig</small></div>
        <div className={styles.editorialAlert}><span>Zu erledigen</span><strong>3 Hinweise</strong><small>Programmdetails und Bildrechte prüfen</small></div>
      </section>
      <section className={styles.editorialContent}>
        <div className={styles.sectionHeading}><div><p className={styles.kicker}>Spielzeit 2026/27</p><h2>Die nächsten Veranstaltungen</h2></div><a>Alle 18 ansehen</a></div>
        <EventRows />
      </section>
    </main>
  );
}

function StudioConsole() {
  return (
    <main className={`${styles.portal} ${styles.console}`}>
      <aside className={styles.consoleSidebar}>
        <Brand inverse />
        <nav>
          <div><span>Arbeitsbereich</span><a data-active>Übersicht</a><a>Veranstaltungen <small>18</small></a><a>Serien</a><a>Bibliothek</a></div>
          <div><span>Veröffentlichen</span><a>Marketing</a><a>Push & Promote</a><a>Auswertung</a></div>
          <div><span>Organisation</span><a>Profile</a><a>Team</a><a>Finanzen</a></div>
        </nav>
        <div className={styles.consoleAccount}><b>JL</b><span>Jakob Liess<small>Veranstalter</small></span><button>•••</button></div>
      </aside>
      <div className={styles.consoleMain}>
        <header><div><p className={styles.kicker}>Symphonieorchester des Bayerischen Rundfunks</p><h1>Übersicht</h1></div><div><button className={styles.secondaryAction}>Vorschau</button><button className={styles.primaryAction}>Veranstaltung anlegen</button></div></header>
        <section className={styles.consoleMetrics}>
          <div><span>Kommende Termine</span><strong>18</strong><small>bis 28. Februar 2027</small></div>
          <div><span>Entwürfe</span><strong>2</strong><small>zuletzt gestern bearbeitet</small></div>
          <div><span>Aufrufe im August</span><strong>12.840</strong><small className={styles.positive}>+ 8,4 % zum Juli</small></div>
        </section>
        <section className={styles.consoleGrid}>
          <div className={styles.consoleEvents}><div className={styles.sectionHeading}><div><p className={styles.kicker}>Termine</p><h2>Als Nächstes</h2></div><a>Kalender öffnen</a></div><EventRows compact /></div>
          <aside className={styles.taskPanel}><div className={styles.sectionHeading}><div><p className={styles.kicker}>Arbeitsliste</p><h2>Offene Punkte</h2></div><span>3</span></div>
            <label><input type="checkbox" /><span><b>Programmdetails ergänzen</b><small>Kammerkonzert der Akademie</small></span></label>
            <label><input type="checkbox" /><span><b>Bildrechte bestätigen</b><small>Bartók und Schostakowitsch</small></span></label>
            <label><input type="checkbox" /><span><b>Vorverkaufslink prüfen</b><small>Mahler: 3. Symphonie</small></span></label>
          </aside>
        </section>
      </div>
    </main>
  );
}

function SeasonBoard() {
  return (
    <main className={`${styles.portal} ${styles.season}`}>
      <header className={styles.seasonHeader}><Brand /><div className={styles.seasonContext}><span>Organisation</span><strong>Symphonieorchester des BR</strong></div><nav><a data-active>Kalender</a><a>Inhalte</a><a>Reichweite</a></nav><button className={styles.primaryAction}>+ Neuer Termin</button></header>
      <section className={styles.seasonIntro}><div><p className={styles.kicker}>Spielzeit 2026/27</p><h1>September</h1></div><div className={styles.monthControls}><button>←</button><span>Heute</span><button>→</button></div></section>
      <section className={styles.seasonBoard}>
        <div className={styles.calendarRail}><span>MO<br /><b>31</b></span><span>DI<br /><b>01</b></span><span>MI<br /><b>02</b></span><span>DO<br /><b>03</b></span><span data-active>FR<br /><b>04</b></span><span>SA<br /><b>05</b></span><span>SO<br /><b>06</b></span></div>
        <article className={styles.featuredEvent}><div className={styles.featuredDate}><span>Freitag</span><strong>04</strong><small>September · 20:00</small></div><div className={styles.featuredCopy}><span className={styles.eventState}>Veröffentlicht</span><h2>Mahler:<br />3. Symphonie</h2><p>Sir Simon Rattle · Magdalena Kožená<br />Isarphilharmonie im Gasteig HP8</p><div><button className={styles.primaryAction}>Bearbeiten</button><button className={styles.secondaryAction}>Vorschau</button></div></div><div className={styles.poster}><span>GUSTAV</span><b>MAHLER</b><i>III</i><small>SYMPHONIE</small></div></article>
        <div className={styles.seasonFooter}><div><strong>3</strong><span>Termine in dieser Woche</span></div><div><strong>2</strong><span>Entwürfe brauchen Details</span></div><a>Zur vollständigen Spielzeit →</a></div>
      </section>
    </main>
  );
}
