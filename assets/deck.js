/*
 * Everything the workshop decks need at runtime, shared by every language and
 * every future workshop: code snippets, copy buttons, the step indicator, the
 * notes panel, and one Reveal configuration.
 *
 * Keeping all of it here (rather than inline per deck) is what stops the PT and
 * EN decks drifting apart in behaviour.
 *
 * SNIPPETS
 * Pulls code into slides from the real project files, so a deck can never show
 * code that does not compile.
 *
 * Usage on a <code> element:
 *   data-src     path to the file, relative to the deck
 *   data-region  named region to extract (optional)
 *   data-lines   line range "12-30" (optional, 1-based, inclusive)
 *   data-dedent  strip common leading indentation (default: on)
 *
 * Regions reuse the markers already present in the project files for the
 * written guide, e.g.  #--8<-- [start:pgvector] ... #--8<-- [end:pgvector]
 * so both outputs read the same source with the same convention.
 *
 * Everything is loaded BEFORE Reveal.initialize, so the highlight plugin sees
 * the final text and no re-highlighting dance is needed.
 *
 * fetch() needs a real origin: serving over file:// will fail every snippet.
 * That failure is rendered into the slide on purpose, because an empty code
 * block discovered in front of a room is far worse than a loud error.
 */
(function (global) {
  "use strict";

  function extractRegion(text, region) {
    const lines = text.split("\n");
    const start = new RegExp("\\[start:" + region + "\\]");
    const end = new RegExp("\\[end:" + region + "\\]");
    const out = [];
    let capturing = false;
    for (const line of lines) {
      if (!capturing && start.test(line)) { capturing = true; continue; }
      if (capturing && end.test(line)) { capturing = false; continue; }
      if (capturing) out.push(line);
    }
    if (!out.length) throw new Error('region "' + region + '" not found');
    return out.join("\n");
  }

  function sliceLines(text, spec) {
    const m = /^(\d+)\s*-\s*(\d+)$/.exec(spec.trim());
    if (!m) throw new Error('bad data-lines "' + spec + '"');
    return text.split("\n").slice(Number(m[1]) - 1, Number(m[2])).join("\n");
  }

  // Region markers are scaffolding for the tooling, never something a slide
  // should display. Both spellings appear in this codebase: `--8<--` in
  // properties and Java, `-8<-` inside XML comments. Stripping them here means a snippet can span several regions
  // (or a plain line range crossing them) and still read as clean source.
  function stripMarkers(text) {
    return text
      .split("\n")
      .filter((line) => !/-{1,2}8<-{1,2}/.test(line))
      .join("\n");
  }

  function dedent(text) {
    const lines = text.split("\n").filter((l) => l.trim().length);
    if (!lines.length) return text;
    const indent = Math.min(...lines.map((l) => l.match(/^[ \t]*/)[0].length));
    if (!indent) return text;
    return text.split("\n").map((l) => l.slice(indent)).join("\n");
  }

  async function loadOne(el) {
    const src = el.getAttribute("data-src");
    el.classList.add("loading");
    try {
      const res = await fetch(src, { cache: "no-cache" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      let text = await res.text();

      const region = el.getAttribute("data-region");
      if (region) text = extractRegion(text, region);

      const lines = el.getAttribute("data-lines");
      if (lines) text = sliceLines(text, lines);

      text = stripMarkers(text);
      if (el.getAttribute("data-dedent") !== "false") text = dedent(text);

      el.textContent = text.replace(/\s+$/, "");
      el.classList.remove("loading");
    } catch (err) {
      el.classList.remove("loading");
      el.classList.add("failed");
      el.textContent =
        "could not load\n  " + src + "\n\n" + err.message +
        "\n\nThis deck reads code from the real project files, which needs a\n" +
        "web server. Opening the file directly from disk will not work.\n\n" +
        "From the repository root:\n  python3 -m http.server 8000";
      console.error("snippet failed:", src, err);
    }
  }


  /* ------------------------------------------------------------------- tabs
   * Two shells for one command, where writing both out would cost a slide.
   * Panels stay in the DOM so their code blocks keep their copy buttons and
   * their highlighting; only visibility moves.
   *
   * Two things here are not decoration:
   *
   * Each panel is stamped with its tab's label. On screen nothing reads it, but
   * the print stylesheet unfolds every panel and needs to say which shell each
   * one belongs to. Doing it here means a deck never has to repeat the label.
   *
   * Space is handled explicitly. Space is the activation key for a button, but
   * reveal.js binds it to "next slide" on document and calls preventDefault(),
   * which kills the synthetic click the button would otherwise get. Focusing a
   * tab and pressing Space therefore jumped the slide and left the tab alone.
   * Handling it on the button, before it bubbles, gives the key back.
   */
  global.initTabs = function () {
    document.querySelectorAll(".tabs").forEach(function (group) {
      const buttons = group.querySelectorAll(".tab-btn");
      const panels = group.querySelectorAll(".tab-panel");

      function select(i) {
        buttons.forEach(function (b, j) {
          b.setAttribute("aria-selected", String(i === j));
        });
        panels.forEach(function (p, j) {
          p.hidden = i !== j;
        });
      }

      buttons.forEach(function (btn, i) {
        const panel = panels[i];
        if (panel && !panel.dataset.tabLabel) {
          panel.dataset.tabLabel = btn.textContent.trim();
        }

        btn.addEventListener("click", function (ev) {
          ev.stopPropagation();
          select(i);
        });

        btn.addEventListener("keydown", function (ev) {
          if (ev.key !== " " && ev.key !== "Spacebar") return;
          ev.preventDefault();
          ev.stopPropagation();
          select(i);
        });
      });
    });
  };

  /* ------------------------------------------------------------ copy button
   * Every code block gets one, whether the code was fetched or written inline.
   *
   * The button lives inside <pre> as a sibling of <code>, never inside <code>,
   * so its own label can never end up in what the attendee pastes.
   *
   * navigator.clipboard needs a secure context. GitHub Pages and localhost
   * qualify; a plain http:// host on the venue LAN does not, so there is a
   * execCommand fallback, and a visible failure state if even that is refused.
   */
  const LABELS = {
    pt: { copy: "copiar", done: "copiado", fail: "falhou" },
    en: { copy: "copy", done: "copied", fail: "failed" },
  };

  function labels() {
    const lang = (document.documentElement.lang || "en").slice(0, 2);
    return LABELS[lang] || LABELS.en;
  }

  async function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.cssText = "position:absolute;left:-9999px;top:0";
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand("copy");
    document.body.removeChild(ta);
    if (!ok) throw new Error("execCommand refused");
  }

  global.addCopyButtons = function () {
    const L = labels();
    document.querySelectorAll("pre > code").forEach(function (code) {
      const pre = code.parentElement;
      if (pre.querySelector(".copy-btn")) return;

      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "copy-btn";
      btn.textContent = L.copy;
      btn.setAttribute("aria-label", L.copy);

      btn.addEventListener("click", async function (ev) {
        // reveal.js binds keys and clicks for navigation; keep this one local
        ev.stopPropagation();
        try {
          await copyText(code.textContent);
          btn.textContent = L.done;
          btn.classList.add("done");
        } catch (err) {
          btn.textContent = L.fail;
          btn.classList.add("failed");
          console.error("copy failed:", err);
        }
        setTimeout(function () {
          btn.textContent = L.copy;
          btn.classList.remove("done", "failed");
        }, 1600);
      });

      pre.appendChild(btn);
    });
  };

  global.loadSnippets = function () {
    return Promise.all(
      Array.from(document.querySelectorAll("code[data-src]")).map(loadOne)
    );
  };
})(window);

/* ========================================================================
 * STEP INDICATOR
 * Derived, not declared: walks back to the nearest preceding .step divider,
 * so a long step can span any number of slides with no extra markup.
 * ====================================================================== */
(function (global) {
  "use strict";

  function currentStep(slide) {
    const slides = Reveal.getSlides();
    for (let i = slides.indexOf(slide); i >= 0; i--) {
      if (slides[i].classList.contains("step")) {
        const num = slides[i].querySelector(".num");
        const title = slides[i].querySelector("h2");
        if (!num || !title) return "";
        return num.textContent.trim() + " \u00b7 " + title.textContent.trim();
      }
    }
    return "";
  }

  global.initStepIndicator = function () {
    const el = document.getElementById("stepIndicator");
    if (!el) return;
    const paint = () => { el.textContent = currentStep(Reveal.getCurrentSlide()); };
    Reveal.on("ready", paint);
    Reveal.on("slidechanged", paint);
  };
})(window);

/* ========================================================================
 * NOTES PANEL
 *
 * Speaker notes serve two audiences with opposite needs. The presenter wants
 * them on a second screen (reveal's own speaker view, key S, in a separate
 * window) and absolutely NOT in the shared window. Someone reading the deck on
 * the published site later wants them right there on the page.
 *
 * So: off by default, which keeps screen sharing safe, and opt-in through the
 * N key, the footer button, or ?notes / ?notas in the URL.
 *
 * The panel is fixed and outside the slide, never inside it: slides do not
 * scroll, and injecting notes into one would push its content out of the box.
 * ====================================================================== */
(function (global) {
  "use strict";

  const LABELS = {
    pt: { show: "notas", hide: "ocultar notas", empty: "Sem notas neste slide." },
    en: { show: "notes", hide: "hide notes", empty: "No notes on this slide." },
  };

  function labels() {
    const lang = (document.documentElement.lang || "en").slice(0, 2);
    return LABELS[lang] || LABELS.en;
  }

  global.initNotes = function () {
    const L = labels();

    const panel = document.createElement("aside");
    panel.className = "notes-panel";
    panel.hidden = true;
    document.body.appendChild(panel);

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "notes-toggle";
    btn.textContent = L.show;
    const footer = document.querySelector(".deck-footer");
    if (footer) footer.appendChild(btn);

    let on = /[?&](notes|notas)\b/.test(location.search);

    function paint() {
      if (!on) return;
      const slide = Reveal.getCurrentSlide();
      const notes = slide ? slide.querySelector("aside.notes") : null;
      panel.innerHTML = "";
      const body = document.createElement("div");
      body.className = "notes-body";
      if (notes && notes.textContent.trim()) {
        body.textContent = notes.textContent.trim();
      } else {
        body.textContent = L.empty;
        body.classList.add("empty");
      }
      panel.appendChild(body);
    }

    function apply() {
      panel.hidden = !on;
      document.body.classList.toggle("notes-open", on);
      btn.textContent = on ? L.hide : L.show;
      btn.classList.toggle("on", on);
      paint();
      // the slide area just changed size, so reveal has to rescale
      if (global.Reveal && Reveal.layout) Reveal.layout();
    }

    btn.addEventListener("click", function (ev) {
      ev.stopPropagation();
      on = !on;
      apply();
    });

    // N toggles, but never while typing into something
    document.addEventListener("keydown", function (ev) {
      if (ev.key !== "n" && ev.key !== "N") return;
      if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
      const t = ev.target;
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return;
      on = !on;
      apply();
    });

    Reveal.on("ready", apply);
    Reveal.on("slidechanged", paint);
  };
})(window);

/* ========================================================================
 * THEME
 * Light by default: a workshop happens in a lit room. The choice is
 * remembered per browser and applied before first paint by a tiny inline
 * script in the deck, so a remembered dark theme never flashes light.
 * ====================================================================== */
(function (global) {
  "use strict";

  const KEY = "qc-theme";
  const LABELS = { pt: { light: "escuro", dark: "claro" },
                   en: { light: "dark", dark: "light" } };

  function labels() {
    const lang = (document.documentElement.lang || "en").slice(0, 2);
    return LABELS[lang] || LABELS.en;
  }

  global.initTheme = function () {
    const root = document.documentElement;
    const L = labels();

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "theme-toggle";
    const footer = document.querySelector(".deck-footer");
    if (footer) footer.appendChild(btn);

    function current() {
      return root.getAttribute("data-theme") === "dark" ? "dark" : "light";
    }

    function apply(theme) {
      if (theme === "dark") root.setAttribute("data-theme", "dark");
      else root.removeAttribute("data-theme");
      try { localStorage.setItem(KEY, theme); } catch (e) {}
      // the button offers the OTHER theme, so it reads as an action
      btn.textContent = theme === "dark" ? L.dark : L.light;
      btn.setAttribute("aria-label", btn.textContent);
    }

    btn.addEventListener("click", function (ev) {
      ev.stopPropagation();
      apply(current() === "dark" ? "light" : "dark");
    });

    document.addEventListener("keydown", function (ev) {
      if (ev.key !== "t" && ev.key !== "T") return;
      if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
      const el = ev.target;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) return;
      apply(current() === "dark" ? "light" : "dark");
    });

    // ?theme=dark / ?theme=light wins over the remembered choice, so a link can
    // carry a theme (and so the deck can be screenshotted in either one).
    const forced = new URLSearchParams(location.search).get("theme");
    apply(forced === "dark" || forced === "light" ? forced : current());
  };
})(window);

/* ========================================================================
 * ONE ENTRY POINT
 * Snippets load before Reveal starts, so the highlight plugin sees final text.
 * The Reveal configuration lives here so every deck shares it exactly.
 * ====================================================================== */
(function (global) {
  "use strict";

  global.initDeck = function (overrides) {
    return loadSnippets().then(function () {
      Reveal.initialize(Object.assign({
        width: 1280,
        height: 720,
        margin: 0.04,
        // Vertical centring is flexbox in deck.css, not reveal. With center:true
        // the section height collapses and a tall code block escapes the slide.
        center: false,
        hash: true,
        slideNumber: "c/t",
        transition: "fade",
        transitionSpeed: "fast",
        plugins: [RevealNotes, RevealHighlight],
      }, overrides || {}));

      Reveal.on("ready", addCopyButtons);
      initTabs();
      initStepIndicator();
      initTheme();
      initNotes();
      return Reveal;
    });
  };
})(window);
