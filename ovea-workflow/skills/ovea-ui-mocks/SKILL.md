---
name: ovea-ui-mocks
description: Oliver's mock-first workflow for any web UI change — a new page, flow or widget, or a change to an existing screen. Write a standalone HTML mock with fake data, get it approved, build the UI to match, get that approved, then delete the mock. Use before writing or changing frontend UI code, and whenever a mock, mockup or UI design is asked for. Not for backend, API, CLI or styling-free logic changes.
allowed-tools: Read Write Edit Bash
---

# UI mocks

Every web UI change starts as a mock the owner approves. There are two stop points: after the mock,
and after the real UI. A change that touches the contract goes mock → contract → backend → clients →
UI: the mock shows what the contract has to serve.

## The flow

1. **Mock.** A self-contained `.html` file (inline CSS and JS, no build, opens from disk) with fake
   but realistic data. Show every state the change has: empty, loading, error, long text, each
   status, a popover opened.
2. **Check it yourself before presenting.** Screenshot it with headless Chrome in light and dark
   (`--force-dark-mode`), at desktop and phone width, and look at the PNGs (Read them). Fix what's
   off first.
3. **Present and stop.** Give the file path, and the screenshots if they help. To serve it, give the
   owner the command (`! python3 -m http.server 8765 -d <mocks dir>`): auto mode blocks opening a
   port. Name anything the implementation needs that the mock doesn't show (e.g. `position:
   relative` to anchor a popover). Then wait for approval; a short "sure" approves only what it
   answers.
4. **Build to match.** The mock is the scope: the implementation adds exactly what it shows, nothing
   else.
5. **Present the real UI and stop** for the second approval.
6. **Delete the mock** once the implementation is approved. If a mock is the approved target of a
   screen built over several milestones, it stays until the screen is done.

## A new screen vs a change to an approved one

- **New screen:** a full mock of the screen.
- **Change to an approved screen: a specimen page**, never a redraw. A blank page holding only the
  parts that change (the header, a card, the composer), copied verbatim from the approved mock or
  the real UI: its CSS and markup unchanged, with the new CSS appended in one block marked as new.
  One numbered section per situation, each with a title and a one-line note of what's new; the
  first shows today's unchanged state to compare against.

## Rules

- **No new text.** Show state through the existing controls (ticked boxes, counts, colours), not new
  hints, markers, status lines or labels. Propose a new line of text as a question instead of
  drawing it in.
- **Where mocks live:** `src/frontend/mocks/` unless the repo's `CLAUDE.md` says otherwise (a repo
  may keep approved mocks, e.g. `docs/mocks/`; then don't delete them).
- **Commits:** a mock is committed only while it's the approved target; its deletion lands with the
  approved implementation.
