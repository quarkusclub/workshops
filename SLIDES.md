# Presenting and authoring the decks

A cheat sheet for the reveal.js decks in this repository. English only, on purpose:
it is about the tooling, not the workshop content.

## Running a deck

The decks read their code from the real project files over `fetch`, so they need an
origin. Opening the HTML from disk shows a visible load error instead of code. The JDK
you already need for the workshops ships a server, so there is nothing to install:

```bash
jwebserver -p 8000 -d "$PWD"      # from the repository root, JDK 18+
```

| Deck | URL |
| --- | --- |
| LangChain4j, Portuguese | <http://localhost:8000/langchain4j/slides/> |
| LangChain4j, English | <http://localhost:8000/langchain4j/slides/en.html> |
| Workshop hub | <http://localhost:8000/> |

## Keys while presenting

| Key | Does |
| --- | --- |
| `→` `←` `Space` | Next and previous slide |
| `S` | **Speaker view**: separate window with notes, timer and next slide |
| `F` | Fullscreen |
| `O` or `Esc` | Slide overview, arrow keys to move, `Enter` to jump |
| `B` or `.` | Black the screen, for when the room should look at you |
| `Alt` + click | Zoom into a region, click again to zoom out |
| `?` | reveal's own help overlay |

### Added by this repository

| Key | Does |
| --- | --- |
| `T` | Toggle **light and dark theme**. Light is the default, remembered per browser |
| `N` | Toggle the **notes panel** on the page itself |

Every code block also has a **copy button**, which appears on hover and hands over the
exact file content, not a transcription.

## Speaker notes without leaking them

Two mechanisms, for two different audiences.

**Presenting.** Press `S`. Notes open in a *separate browser window* with a timer and a
preview of the next slide.

> Share the **deck window**, not your whole screen. Sharing the screen shares the notes
> window too. This is the single most common way to leak presenter notes.

**Reading the published deck.** Press `N`, click the `notes` button in the footer, or add
`?notes` (or `?notas`) to the URL. This renders the current slide's notes in a side panel
on the page. It is **off by default**, so a presenter who never touches it cannot leak
anything, while an attendee browsing later gets the full commentary.

## URL parameters

| Parameter | Effect |
| --- | --- |
| `#/12` | Jump to slide 12, zero-based. Every slide has a stable hash |
| `?theme=light` / `?theme=dark` | Force a theme, overriding the remembered choice |
| `?notes` / `?notas` | Open the notes panel |
| `?print-pdf` | Switch to the print layout, see below |

These compose: `...?theme=dark&notes#/12`.

## Saving as PDF

reveal.js has a dedicated print stylesheet. Chrome or Chromium gives the best result.

1. Open the deck with `?print-pdf` appended, before the `#`:
   <http://localhost:8000/langchain4j/slides/?print-pdf>
2. `Ctrl+P` (or `Cmd+P`)
3. Destination **Save as PDF**
4. Layout **Landscape**
5. Margins **None**
6. Tick **Background graphics**, otherwise you get white slides with invisible text

Headless, without opening a browser:

```bash
chromium --headless=new --disable-gpu --no-sandbox \
  --print-to-pdf=langchain4j-pt.pdf --no-pdf-header-footer \
  --virtual-time-budget=20000 \
  "http://localhost:8000/langchain4j/slides/?print-pdf"
```

Two things worth knowing before you print:

- **Print in the light theme.** Add `?print-pdf&theme=light`. The dark theme is remapped
  to paper colours under `@media print` anyway, but being explicit avoids surprises.
- **Long code blocks print in full**, not just the part visible on screen, so a deck
  produces more PDF pages than it has slides. The LangChain4j deck is 111 slides and
  prints to about 144 pages.

Verified on this repository: 144 pages, 6.9 MB, in the light theme.

To include the speaker notes in the PDF, add `&showNotes=true`. They print on a separate
page after each slide.

## Authoring

`assets/deck.css` **is the contract**. A deck is pure composition: it declares `<section>`
elements and applies predefined classes. Never write per-deck CSS. If a deck needs a new
layout, add a reusable class to `deck.css` so every future workshop inherits it.

### Slide types

| Class | Purpose |
| --- | --- |
| `.cover` | Title slide, enables `.title-sub` and `.byline` |
| `.step` | Step divider: `.num`, `h2`, `.goal`, `.meta` chips. Drives the footer indicator |
| `.code` | Code slide. Add `.small` or `.tiny` for long files |
| `.cmd` | Commands to type: `.line` blocks, `.no-prompt` drops the `$` |
| `.checkpoint` | "You know it worked when", green, `ul` of items |
| `.gotcha` | Warning, warm accent, with a `.box` inside |
| `.answer` | One big statement plus a `.sub` line |
| `.agenda` `.duo` `.cards` `.qa` | Roadmap, two columns, three cards, numbered questions |
| `.kicker` | Mono label with a rule running to the right edge |

### Pulling in code

Never paste code into a slide. Point at the real file:

```html
<pre><code class="language-java"
      data-src="../section-1/step-01/src/main/java/.../CustomerSupportAgent.java"></code></pre>
```

| Attribute | Effect |
| --- | --- |
| `data-src` | Path to the file, relative to the deck |
| `data-region` | Extract a named region, reusing the `[start:name]` markers already in the files |
| `data-lines` | A line range, `"19-47"`, 1-based and inclusive |
| `data-line-numbers` | reveal's progressive highlight, `"3-5\|7\|all"`, arrow keys step through it |

Region marker lines are stripped automatically, in both the `--8<--` and `-8<-` spellings.

### Two invariants

1. **The language versions must stay structurally identical.** Same sections, same order,
   differing only in text. CI fails the build if the slide counts diverge.
2. **A slide never scrolls.** Only code blocks do. Content that does not fit is a content
   bug, to be fixed by splitting the slide.

To check the second one across a whole deck, measure it rather than eyeballing:

```js
// paste in the browser console with the deck open
Reveal.getSlides().forEach((sec, i) => {
  const r = sec.getBoundingClientRect();
  const bottom = Math.max(...[...sec.children].map(el => el.getBoundingClientRect().bottom));
  const footer = document.querySelector(".deck-footer").getBoundingClientRect().top;
  const over = bottom - Math.min(r.bottom, footer);
  if (over > 2) console.warn(`slide ${i} overflows by ${Math.round(over)}px`);
});
```

## Starting a new deck

1. Copy an existing `slides/` folder and delete the step sections.
2. Keep the opening block: cover, the problem, the Quarkus Club slide and "how to follow"
   are written to be reused.
3. Compose from the classes above. Do not add CSS to the deck file.
4. Add a card to `index.html`.
