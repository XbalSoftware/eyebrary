# PROJECT_STATUS.md — EYEbrary

Living status snapshot + changelog. Architectural detail lives in `CLAUDE.md`; this file
tracks **what is done, what is stable, and what is next**. Keep it current after each
meaningful implementation step.

- **App:** EYEbrary — patient-report generator for eye-care professionals
- **Platform:** SwiftUI, iPad-first (also iPhone), **iOS 17.0** deployment target
- **Version:** 1.2 (build 2) — in progress
- **Last updated:** 2026-07-21

> Note: this file supersedes the older `EYEbrary developer log : roadmap.rtf`. That log
> described the shell as `NavigationSplitView`; the app actually uses a **3-tab `TabView`**
> (New Report / Library / Settings). Detail there that has since changed has been corrected
> here.

## Since 1.0

- **Safe Zone Editor** (`SafeZoneEditorView.swift`) — added in a separate session after the
  original release. Visual, per-letterhead editor for the PDF content rectangle and
  page-number stamp position, stored as normalized `SafeZoneConfig` values and consumed by
  `PlanPDFBuilder`. Fully functional.
- Aside from the safe-zone work, the app is unchanged from its original release.

## Completed / stable systems

- **Multi-library system** — multiple independent libraries; create / rename / delete (with
  safeguards) / reorder; active-library selection; per-library sort mode.
- **Global category system** — global across libraries; stable slug IDs; `General` pinned and
  protected; add / rename (gated behind Edit) / delete (with affected-entry count + reassign
  to General) / reorder.
- **Entry management** — rich-text (RTF) entries; search (title + body); category filter;
  sort (manual / A–Z / Z–A / newest / oldest); favorites; visibility toggle; swipe-to-delete;
  manual drag reorder.
- **Batch Select** — dedicated sheet; multi-select across the whole library; persistent
  selection across search/sort changes; batch categorize / delete / export-as-single-JSON;
  "Recent Imports" grouping via `lastImportedAt`.
- **Import / export** — `.json` (array of entries) and `.eyebrarylib` (package) formats;
  Merge vs Replace; import provenance stamped permanently; "Normalize text on import" toggle;
  failed imports do not create undo snapshots.
- **Letterhead system** — import PDF letterheads (security-scoped), select active letterhead,
  swipe-to-delete with confirmation; deleting a letterhead also clears its safe-zone config.
- **PDF export** (`PlanPDFBuilder`) — letterhead compositing, safe-zone-aware layout,
  widow/orphan-aware page splitting, "Continued on next page" notes, and "Page X of Y"
  stamping.
- **Global undo/redo** — snapshot-based, bounded (50), Tier 1 structural actions only;
  `⌘Z` / `⇧⌘Z` shortcuts.
- **Current-draft autosave/restore** — restores in-progress report on relaunch; **patient
  name intentionally excluded** for privacy; restore banner; clearing the report clears the
  draft.
- **History** — last 10 cleared reports; item count + title preview + timestamp; restoring
  stashes the current in-progress report first so work isn't silently lost; patient names not
  stored.
- **Bundled default library** — `Default Library.eyebrarylib`; loaded on first seed and on
  Reset to Factory Defaults via a path that preserves authored RTF.

## Design decisions (intentional — don't "fix" without discussion)

- Libraries are independent containers; categories are **global**.
- Undo is snapshot-based and limited to **Tier 1 structural** actions; metadata toggles
  (favorite / visibility / add entry) are deliberately excluded.
- `lastImportedAt` provenance is **permanent** metadata.
- Autosaved drafts exclude the patient name; History omits patient names.
- UI philosophy: separate filtering from actions, keep the sidebar uncluttered, push complex
  workflows into focused sheets.

## Known issues / tech debt

- **Duplicated formatting logic** between `RichTextEditor` (live editing) and `AppStore`
  import normalization. Changing one without the other causes editor/PDF divergence.
  Consolidating into a shared formatter is a pending task.
- **Bundle ID** is `ca.simonreid.EYEbrary.test` — the `.test` suffix should be resolved
  before an App Store submission.

## Version 1.2 — polishing (in progress)

PDF pagination, list indentation, and a print text-size option — reworked 2026-07-21 using
the tactics proven in EYEreport's `ReportRenderer.swift`. (An earlier attempt at the
pagination/indent fixes in another session did not work and was discarded; the notes below
describe the current, rewritten implementation. **Awaiting Simon's build + visual
verification.**)

### `PlanPDFBuilder.swift` — rewritten body pagination & normalization

- **Page breaks land on TextKit line-fragment boundaries.** The old `fittingLength` binary
  search over raw character counts (which cut mid-word) is gone. `lineBreakFitLength` lays the
  remaining text into a real `NSLayoutManager`/`NSTextContainer` of the available height, so a
  cut can only land where a line break does — a mid-word page break is impossible by
  construction.
- **Page breaks prefer paragraph boundaries, with a real widow/orphan check.**
  `bestSplitLength` accepts the line-boundary fit if it already lands at a paragraph break, or
  if the paragraph being cut keeps ≥3 of its own lines on this page and sends ≥2 to the next
  (the old check measured the whole chunk, not the cut paragraph, so it almost always passed).
  Otherwise the cut paragraph moves to the next page whole. A paragraph starting at the top of
  a page that is still too tall splits at the line boundary regardless (overflow guard, with a
  forced first line so a pathologically small safe zone can't loop forever).
- **List hanging indents are rebuilt per paragraph at the print font.**
  `normalizedBodyAttributedString` applies ONE paragraph style per paragraph: authored indents
  scale from the paragraph's authored font size to the print size, and for list paragraphs
  (marker `"• "` or `^\d+\.\s` — must stay in step with `RichTextEditor.markerPrefix(in:)`)
  the wrap indent is recomputed as `firstLineHeadIndent + marker width measured at the PRINT
  font`. The old code scaled the editor-font-measured `headIndent` by the point-size ratio,
  which misaligned because system-font glyph widths are not proportional across optical sizes
  — numbers drifted visibly, bullets less so.
- **A list item split mid-text resumes at the wrap column** on the next page:
  `fixContinuationIndent` sets the tail's first paragraph `firstLineHeadIndent = headIndent`
  (same trick as EYEreport's `splitAttributedString`), applied only when the split did not
  cross a paragraph break.
- **`bodyFontSize` parameter** (default 10) — body renders at the chosen size; the entry
  header and the Patient/Date line render at `max(12, bodySize + 2)`; the report title stays
  22 pt; fixed row heights and minimum-space constants now derive from the actual line height
  so larger sizes don't clip.

### Text-size option for low-vision patients

- `AppStore.reportFontSize` (persisted, `EYEbrary.reportFontSize.v1`, default 10).
- `NewReportView`: a "Text size" menu chip beside the letterhead picker — Standard (10 pt) /
  Large (12 pt) / Extra large (14 pt) — passed to `buildPDF` on export.

### Verification checklist (after building)

1. A numbered list whose items wrap: every wrapped line should align exactly under the text
   after its number (e.g. under the "R" of "Regular"), for 1-digit and 2-digit numbers alike.
2. Indented/nested bullet lists keep their authored indent depth.
3. A multi-page report: no break mid-word; breaks land between paragraphs/list items unless a
   long paragraph genuinely spans pages (then ≥3 lines stay / ≥2 carry, continuation lines at
   the wrap column, "Continued on next page" note present, "Page X of Y" correct).
4. Export at Large / Extra large: headers, Patient/Date line, and body all scale; nothing
   clips; pagination stays clean.

## Pre-release checklist (do these last, before submitting the 1.2 update)

The app is intentionally kept on the `.test` bundle ID during development so it installs
alongside the live App Store version. Before archiving the update:

1. **Revert the bundle ID** — `PRODUCT_BUNDLE_IDENTIFIER` back to the production ID that matches
   the live App Store listing (drop the `.test` suffix). The store identifies the app by this ID.
2. **Bump the build number** — `CURRENT_PROJECT_VERSION` must exceed any build already uploaded
   (currently 2). Keep `MARKETING_VERSION` (1.2) higher than the live version.
3. **Add a privacy manifest** — no `PrivacyInfo.xcprivacy` exists yet; the app uses `UserDefaults`
   heavily (a required-reason API, `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`).
   Missing it triggers an ITMS-91053 warning at upload and can become a rejection.
4. **Add the encryption flag** — set `ITSAppUsesNonExemptEncryption` to `NO` in `Info.plist`
   (the app uses no custom cryptography) to skip the export-compliance prompt on every upload.
5. **In App Store Connect** — write "What's New" text, refresh screenshots if the UI changed
   (e.g. the safe-zone editor), and confirm the App Privacy answers still read "no data collected".
6. **Archive** for *Any iOS Device* → Product → Archive → upload from the Organizer.

## Future considerations (not scheduled)

- Expand undo coverage to discrete metadata actions with snapshot coalescing.
- System-gesture undo/redo (three-finger) via `UndoManager`; transient "Undo" banner after
  destructive actions.
- Images in entries; sound effects; wand/normalization refinement.
- Consolidate the duplicated formatter (see Tech debt).
- Reconsider per-library categories if the global taxonomy becomes limiting.
- Import duplicate handling (paused).
