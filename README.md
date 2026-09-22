# Quarkus Club Workshops

Hands-on workshops from [Quarkus Club](https://quarkusclub.github.io), a Brazilian Java User
Group. Every workshop ships three things, in Portuguese and English: a **reveal.js deck** that
carries the whole path step by step, a **run sheet** for whoever is presenting, and **code that
compiles**.

**Site:** <https://quarkusclub.github.io/workshops/>

## Workshops

| Workshop | Topic | Slides | Run sheet | Code |
| --- | --- | --- | --- | --- |
| langchain4j | **Integrating Java applications with LLMs, production grade.** RAG, tools, MCP, guardrails and observability, on the free NVIDIA API | [PT](langchain4j/slides/index.html) · [EN](langchain4j/slides/en.html) | [ROTEIRO](langchain4j/ROTEIRO.md) · [RUNSHEET](langchain4j/RUNSHEET.md) | [11 projects](langchain4j/section-1/) |

## Preparing a machine

Run this before the workshop, on the machine you will use. It verifies your setup, warms the
caches that venue wifi cannot handle, and ends with a health check that reports READY or NOT READY.

```bash
# Linux / macOS
curl -fsSL https://quarkusclub.github.io/workshops/langchain4j/scripts/prepare.sh | bash
```

```powershell
# Windows PowerShell
irm https://quarkusclub.github.io/workshops/langchain4j/scripts/prepare.ps1 | iex
```

The scripts install nothing system-wide and never ask for elevation. To read before running,
download with `-o` / `-OutFile` first. They are scoped to the workshop, not to the repository:
source lives in [`langchain4j/scripts/`](langchain4j/scripts/).

## Repository layout

```
.
├── LICENSE                  Apache License 2.0
├── NOTICE                   attribution and statement of modifications
├── assets/
│   ├── deck.css             the deck theme. THIS IS THE CONTRACT
│   ├── deck.js              snippet loading, copy buttons, notes, Reveal config
│   ├── favicon.ico          the Quarkus Club mark
│   └── logo.png             the same mark at 145px
├── index.html               navigation hub, published at the Pages root
├── SLIDES.md                the deck system, for presenters
└── langchain4j/
    ├── slides/              index.html (PT) and en.html (EN), 111 slides each
    ├── scripts/             prepare.sh, prepare.ps1
    ├── ROTEIRO.md           run sheet, PT
    ├── RUNSHEET.md          run sheet, EN
    ├── section-1/           11 runnable Quarkus projects, one per step
    └── pom.xml              aggregator
```

## How the decks work

`assets/deck.css` **is the contract**. A deck is pure composition: it declares `<section>`
elements and applies predefined classes. Never write per-deck CSS. If a deck needs a new layout,
add a reusable class to `deck.css` so every future workshop inherits it.

The class vocabulary:

| Class | Purpose |
| --- | --- |
| `.cover` | Title slide, enables `.byline` |
| `.step` | Step divider: `.num`, `h2`, `.goal`, `.meta` chips. Drives the footer indicator |
| `.code` | Code slide. Add `.small` or `.tiny` for long files |
| `.cmd` | Something to type: `.line` blocks, `.no-prompt` to drop the `$` |
| `.checkpoint` | "You know it worked when", green |
| `.gotcha` | Warning, warm accent, `.box` inside |
| `.agenda` `.duo` `.cards` `.answer` `.qa` | Roadmap, two columns, three cards, big statement, question list |
| `.kicker` | Mono label with a rule to the right edge |

Two behaviours are worth knowing:

- **Code comes from the real files.** A `<code data-src="../section-1/...">` is fetched at
  runtime, optionally narrowed with `data-region` (reusing the `[start:name]` markers the written
  guide already uses) or `data-lines`. A slide therefore cannot show code that does not compile.
  This needs a web server: opening the deck from disk shows a visible load error, by design.
- **The footer step indicator is derived**, by walking back to the nearest preceding `.step`
  divider. A long step can span any number of slides without extra markup.

Copy buttons are injected into every code block automatically.

### Presenting

The decks read their code over `fetch`, so they need an origin: opening the HTML from disk
shows a visible load error instead of code. The JDK you already need for the workshop ships a
server, so there is nothing to install:

```bash
jwebserver -p 8000 -d "$PWD"     # from the repository root, JDK 18+
```

Then open <http://localhost:8000/langchain4j/slides/>. Press **S** for speaker notes,
**F** for fullscreen, **O** for the slide overview, **B** to black the screen.

That command is also the whole preview story. Pages publishes straight from the branch, so the
repository root IS the published shape: <http://localhost:8000/> is the hub, exactly as it will
be served. There is no build step and nothing to assemble.

## Working on the code

```bash
cd langchain4j
./mvnw clean verify              # builds all 11 step projects
./mvnw -pl section-1/step-01 quarkus:dev
```

Requires JDK 21+, and Docker or Podman from step 06 onward.

## Adding a workshop

1. Create `<slug>/slides/index.html` and `en.html`, composing classes from `assets/deck.css`.
2. Keep both languages structurally identical: CI fails the build if the slide counts diverge.
3. Add a card to `index.html`, with both languages in `data-lang` spans and any per-language
   link in `data-href-pt` / `data-href-en`.
4. Add the runnable projects, a run sheet in both languages, and a `NOTICE` if the workshop
   derives from someone else's work.

## Credits and licence

The langchain4j workshop is a derivative work of
[quarkusio/quarkus-workshop-langchain4j](https://github.com/quarkusio/quarkus-workshop-langchain4j),
used under the Apache License 2.0. The workshop design, the Miles of Smiles scenario, the diagrams
and most of the code are theirs. See [`NOTICE`](NOTICE) for the full statement of modifications and
[`langchain4j/UPSTREAM.md`](langchain4j/UPSTREAM.md) for the defects found while porting.

Improvements that are not specific to this translation or to NVIDIA are more useful sent upstream,
where they reach more people.

The Quarkus name and logo are trademarks of Red Hat, Inc. The marks in
[`assets/`](assets) are the official horizontal lockups from
[design.jboss.org/quarkus](https://design.jboss.org/quarkus/logo/), unmodified, used to identify the
technology this community workshop teaches.
