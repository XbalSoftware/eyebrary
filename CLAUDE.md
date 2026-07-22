# CLAUDE.md — EYEbrary

Guidance for Claude (and any future agent) working in this repository. Read this first,
then consult `PROJECT_STATUS.md` for the feature-by-feature state of the app.

## What EYEbrary is

EYEbrary is a **SwiftUI app for eye-care professionals**. Clinicians build a reusable
**library** of documentation entries (rich text), then assemble those entries into a
**patient summary report** that exports as a polished, letterhead-branded **PDF**.

- Primary device target: **iPad** (also builds/runs on iPhone; portrait + landscape).
- Not a medical-advice tool. All generated content is authored and reviewed by the
  clinician. A launch acknowledgement and an About-screen disclaimer make this explicit —
  keep that framing intact in any user-facing copy.

## Build & run

- Open `EYEbrary.xcodeproj` in Xcode and run the `EYEbrary` target.
- **Deployment target: iOS 17.0.** Do not use APIs newer than iOS 17 without guarding them.
- Swift 5. Pure SwiftUI + UIKit interop (no third-party dependencies, no Swift Package
  Manager manifests, no CocoaPods).
- Current marketing version **1.2**, build **2** (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
  in `EYEbrary.xcodeproj/project.pbxproj`). The About screen reads these from the bundle at
  runtime — bump them in the project, not in code.
- Bundle identifier is currently `ca.simonreid.EYEbrary.test`. The `.test` suffix looks like
  a development identifier; confirm the intended production ID before an App Store build.

## Architecture

Single source of truth is **`AppStore`** (`AppStore.swift`), a `@MainActor
ObservableObject` injected via `.environmentObject(store)` at the root (`ContentView`).
There is no external database — **everything persists to `UserDefaults`** as JSON, keyed by
versioned keys (e.g. `EYEbrary.libraries.v1`).

### Data model (all `Codable`, in `AppStore.swift`)

- **`LibraryCollection`** — a named library: `entries`, `sortMode`, timestamps.
- **`LibraryEntry`** — one library item: `title`, `body` (plain-text mirror) + `bodyRTFData`
  (the authoritative rich text), `category`, `isFavorite`, `isVisible`, `order`,
  `lastImportedAt` (permanent import provenance). Custom `Codable` handles **legacy
  migration** (old `assessment`/`plan`/`isPinned`/`level` fields fold into `body`).
- **`CategoryItem`** — global category (stable string `id` slug + display `name` + `order`).
  Categories are **global across all libraries**. `"general"` is the pinned, undeletable,
  unrenamable default.
- **`PlanEntry`** — an entry copied into the in-progress report, keeping both the edited and
  `original*` text so it can be reset.
- **`SavedPlan`** — a report snapshot stored in History (max 10; **patient name is kept in
  History but never persisted in the autosaved draft** — see Privacy).
- **`SafeZoneConfig`** — per-letterhead normalized (0…1) content rectangle + page-number
  origin, used by the PDF builder.

### State flow / gotchas

- `libraries`, `activeLibraryID`, and `entries` are kept in sync through `didSet` observers
  guarded by `isSynchronizingLibraryState`. **`entries` is a working mirror of the active
  library's entries** — mutate `entries` and it writes back to the active library
  automatically. Don't bypass this by mutating `libraries[i].entries` directly unless you set
  the guard flag, or you'll cause re-entrant sync bugs.
- **Undo/redo is snapshot-based** (`UndoSnapshot` captures libraries + activeLibraryID +
  categories; bounded to 50). Call `pushUndoSnapshot()` *before* a mutation to make it
  undoable. Coverage is intentionally **"Tier 1" structural actions only** (library
  create/rename/delete/reorder, entry delete/recategorize, category rename/delete/reorder,
  import merge/replace). Metadata toggles (favorite, visibility, add entry) are deliberately
  **not** undoable — a prior attempt to add them was reverted. `⌘Z` / `⇧⌘Z` are wired through
  a hidden command layer in `ContentView`.

### Screens (three tabs, `ContentView` → `TabView`)

- **`NewReportView.swift`** — build/edit the current report, autosave/restore drafts,
  History sheet, generate & share the PDF.
- **`ManageLibraryView.swift`** — browse/search/filter/sort/reorder entries, favorites,
  swipe-to-delete, the **Batch Select** sheet (multi-select + batch categorize/delete/export),
  and `ManageEntryDetail` for editing a single entry.
- **`SettingsView.swift`** — libraries manager, global category manager, letterhead
  management, import/export, "Normalize text on import" toggle, reset to factory defaults,
  Quick Start, and `AboutView`.

### Supporting files

- **`RichTextEditor.swift`** — `UITextView`-backed rich-text editor + a "magic wand"
  formatting/normalization pass and bullet/numbered-list handling with measured hanging
  indents.
- **`PlanPDFBuilder.swift`** — renders the report to PDF with `UIGraphicsPDFRenderer`.
  Handles letterhead compositing (coordinate flip), safe-zone geometry, widow/orphan-aware
  page splitting, and a second pass that stamps "Page X of Y".
- **`SafeZoneEditorView.swift`** — the visual editor (added after 1.0 in a separate session)
  for positioning the content rectangle and page-number stamp over a letterhead preview.
- **`HistorySheet.swift`**, **`SharingHelpers.swift`** (`UIActivityViewController` wrapper +
  single-entry JSON export), **`AboutView.swift`**.
- **`Default Library.eyebrarylib`** — bundled default library package (a `.eyebrarylib` is a
  directory package: `manifest.json` + `Entries/<uuid>.rtf`). Loaded on first launch and on
  Reset to Factory Defaults via a dedicated path that **preserves authored RTF (no
  normalization)**. `Blank.pdf` is the fallback blank letterhead.

## Import / export formats

- **`.json`** — array of `LibraryEntry`. Merge (by id) or Replace.
- **`.eyebrarylib`** — a package (directory) with `manifest.json` + per-entry RTF files;
  declared as an exported UTI `com.xbalsoftware.eyebrary.library` in `Info.plist`.
- Manual imports respect the **"Normalize text on import"** setting; the bundled default
  library bypasses normalization to preserve formatting exactly.

## Conventions

- Match the surrounding SwiftUI style: `private` helpers, `// MARK:` section dividers, small
  focused subviews (often `private struct` in the same file).
- Rich text is authoritative as `bodyRTFData`; `body` is a plain-text convenience mirror. When
  you change rich text, go through `setAttributedBody(_:)` so both stay in sync.
- **Formatting logic is currently duplicated** between `RichTextEditor` (live editing) and
  `AppStore` import normalization. If you touch list/indent formatting, change both or you'll
  cause divergence between the editor and PDF output. (Consolidating into one shared formatter
  is a known future task.)
- Persist through `AppStore`'s `@Published` properties — their `didSet` handles saving. Don't
  write to `UserDefaults` directly from views.

## Privacy (do not regress)

- The autosaved in-progress **draft never stores the patient name**; a banner on restore says
  so. History likewise surfaces "patient names are not stored for privacy."
- Keep patient data out of logs, filenames, and any external calls. The app makes no network
  requests today; adding any would be a significant change to review carefully.
