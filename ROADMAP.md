# Roadmap

Forward-looking plans for Everything Settings Manager — PowerShell WPF GUI for managing voidtools Everything INI + CSV data (Filters, Bookmarks, Search History, Run History).

## Planned Features

### Settings Coverage
- Everything 1.5 alpha / beta key coverage — track new keys as they land in each alpha drop
- Grouped views for keys added since 1.4 (exclude filters, content indexing, NTFS USN journal)
- "Safe-recommended / Privacy / Performance / Power-user" preset bundles
- Diff view: show only keys that differ from factory defaults
- Import/export settings as portable `Everything.ini` + CSV bundle (zip)

### CSV Editor
- Inline validation (filter regex preview, bookmark URL check)
- Bulk-edit operations (prefix, suffix, regex replace across rows)
- Merge-from-URL for filter/bookmark curated lists (community GitHub sources)
- Search history scrubber: mass-delete matches by regex
- Run history: mark entries as pinned so they survive prunes

### Portable & Service Support
- Detect portable vs installed Everything (EXE in PortableApps path)
- Detect Everything service (client/service mode) and manage the service INI separately
- Multi-instance support (Everything can run multiple indexers) — pick which INI via dropdown
- Direct IPC test to verify Everything process responds after Apply

### Filters & Bookmarks Library
- Curated built-in presets: "Code files", "Media files", "Installers", "Archives", "Screenshots", "Documents"
- One-click add bookmark for common roots (Desktop, Downloads, this-drive-only)
- Import from user's existing Everything installation (auto-detect most recent INI)

### Automation & Distribution
- CLI mode: `EverythingSettingsManager.ps1 -ApplyPreset Recommended -Restart`
- Group-policy ADMX export for clinic / enterprise deployments
- Signed release + winget manifest
- Scheduled re-apply task to revert user drift (optional)

### UX Polish
- Change tracking pane (pre-apply diff with undo)
- Keyword search across every setting (name, key, description, default value)
- Tooltip hyperlinks to the voidtools forum thread that documents each option
- Dark / light / high-contrast theme options

## Competitive Research

- **Everything's own Tools → Options dialog**: authoritative but sprawling and modal. Our pitch is tabbed categorization, keyword search, and preset bundles.
- **NirSoft InstalledAppView / RegScanner-style tools**: precedent for "wrap a config surface in a cleaner UI". We borrow the DataGrid + quick-filter convention.
- **Everything voidtools forum**: primary source for which keys matter. Bake links into tooltips.
- **Ant Renamer / Bulk Rename Utility**: UX references for batch CSV editing operations.

## Nice-to-Haves

- Live preview of filter results against the current Everything index
- Export settings as a signed `.reg`-style script (PowerShell) for deploying to many PCs
- Before/after index-size impact estimate per toggle
- Health report: flag problematic settings (ridiculous exclude lists, stale bookmarks)
- Integration with VoidTools' own beta update feed for version-gated setting visibility
- Companion module to back up and roll back INI versions automatically

## Open-Source Research (Round 2)

### Related OSS Projects
- https://github.com/sgrottel/EverythingSearchClient — .NET Everything IPC client, no native SDK DLL
- https://github.com/ZilverZtream/anything — Everything-class indexer with content search + OCR + trigram/Bloom
- https://github.com/Flow-Launcher/Flow.Launcher — Everything plugin + launcher integration reference
- https://github.com/cboxdoerfer/fsearch — Linux Everything-style indexer, rule-semantics reference
- https://github.com/Everything-Search-Engine/Everything-Search-Pro — UI concepts + filter layout
- https://github.com/DamirAinullin/SearchEverything — Visual Studio Everything integration
- https://github.com/voidtools — official Everything source/sdk repos

### Features to Borrow
- IPC-based "live preview" of changes without writing INI until Apply (EverythingSearchClient approach)
- Full-text content-search toggle UI (ANYTHING) — Everything 1.5 supports content indexing, expose the knob cleanly
- Filter preset library (code, media, installers, office docs) with descriptions (Everything Search Pro)
- Saved-search bookmarks sync as JSON next to CSV export (FSearch)
- Plugin-style exporters (JSON / YAML / reg) so power users can version-control Everything config
- Service-mode toggle with elevation prompt — Everything runs best as service; surface the choice
- Backup rotation: keep N dated INI backups with auto-prune rather than a single .bak
- Per-index folder/exclusion list editor with live count preview
- ETW/USN-journal status panel — show whether Everything is using USN for the selected volumes
- Keyboard-first command palette over the 100+ settings (Flow Launcher pattern)

### Patterns & Architectures Worth Studying
- INI round-trip: preserve comments + ordering when writing back (common Everything-config complaint)
- Everything IPC via message-only window + WM_COPYDATA — lets settings UI talk to running service (EverythingSearchClient)
- Schema-driven settings: one source of truth mapping INI key → type → recommended value → impact tier (already partial, extend)
- CSV edit with undo/redo stack using a single JSON delta log
- Headless/CLI mode (`-Apply Recommended -Silent`) so the same tool drives MDT/Intune deployments
