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

Small polishing steps to be defined and worked through this session. Log each item here as it
lands:

- _(to be filled in as we go)_

## Future considerations (not scheduled)

- Expand undo coverage to discrete metadata actions with snapshot coalescing.
- System-gesture undo/redo (three-finger) via `UndoManager`; transient "Undo" banner after
  destructive actions.
- Images in entries; sound effects; wand/normalization refinement.
- Consolidate the duplicated formatter (see Tech debt).
- Reconsider per-library categories if the global taxonomy becomes limiting.
- Import duplicate handling (paused).
