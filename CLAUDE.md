# CLAUDE.md — Electracom Smart Point Reference Tool

> Working memory file for Claude. Updated as the tool evolves.
> **Current version on disk:** v18 (`Electracom_Smart_Point_Reference_v18.html`, single-file HTML, ~1,926 lines, ~571 KB). **HTML-only, no backend.** All data baked in as JS objects; state persisted to `localStorage`.
> **Status:** v18 built 14 Apr 2026 on top of v17.1. It keeps the Dylan-aligned v17.1 baseline and starts the previously deferred work: (1) a new standalone `catalog` section for subtype records, (2) browser-local manufacturer / model / notes capture via `epl10_catalogMeta`, (3) suggested point mappings driven by `EQ.standards` plus observed points, and (4) browser-local MSI sign-in replacing the old raw `epl10_admin` toggle. This means [D2], [D3], and [D4] are now started in the current build, while [D6] is only partially addressed because the app is still static HTML with no backend / SSO. See §4 gap matrix.
> **Version note:** v13 shipped Dylan's §4 written feedback except the two "ADD ON FOR LATER" / "Confirmation" items. v14 added both ([D1] subtype drill-down + [D5] auto-sync). v15 was a QOL/nav/export hardening layer. v16 fixed the font toggle (CSS `zoom`) and tender calculator (Typical/Max). v17 / v17.1 were Dylan-alignment and export-versioning correctness passes. v18 is the first pass at the previously deferred catalogue / mapping / auth work.
> **Last updated:** 14 April 2026 (post-v18 build)

---

## 1. What this tool is

A standalone HTML application used by Electracom's MSI team — and (soon) the wider business — to manage **BMS / smart-building point names** against the Google **Digital Buildings Ontology (DBO)**.

Built by Rajesh, with **Dylan** (technical / DBO subject matter) and **John** (MSI Solutions Manager / product owner) driving requirements. The longer-term vision is rollout to design engineers, commissioning engineers, software developers and solutions architects across Electracom — not just MSI.

Parallel project: **Device Qualification / Testing Tool** — *higher* priority, used on Minerva House and 334 Oxford Street. The Smart Point Reference tool is "fairly high priority" but second to device qualification.

---

## 2. Key people

| Person  | Role                                | Notes                                                                 |
|---------|-------------------------------------|-----------------------------------------------------------------------|
| Rajesh  | Developer (the user of this CLAUDE) | Building both tools. Currently mid-migration: SQLite → Postgres, Docker rewrite, nginx reverse proxy. |
| John    | MSI Solutions Manager               | Product owner. Wants admin restricted to MSI. Off Thu 16 / Fri 17 Apr. |
| Dylan   | DBO / technical expert              | Author of `Point_naming_tool_comments.docx`. Strong views on DBO structure and Builder ordering. |
| Carry   | Senior stakeholder                  | Demo target: **w/c 20 Apr 2026** (avoid the 23rd if possible — John has the operations & project managers meeting that day). |
| Tim     | Possible future contributor         | May help with the asset → DBO point mapping exercise once freed up.  |

---

## 3. v15 architecture (what we're working with)

Single HTML file. No backend. All data baked in as JS objects. Heavy use of `localStorage` for role + tender estimates + DBO sync metadata + pending queue + browser-local catalogue metadata + browser-local auth.

### 3.1 Data model

**`D` — Point library data**
- `D.p` — array of point rows. **19 columns indexed 0–18** (was 17 in v11, 18 in v13):
  - `[0]` system (`BMS_MEP`, `EMS`, `PMS`, `Access_Control`, `Fire`, `Lifts`, `Lighting`, `CCTV`)
  - `[1]` asset type — *canonicalised* by `normaliseAsset()` (e.g. all `AHU TYPE-1`/`AHU TYPE-2`/`Air Handling Unit` rows become `AHU`)
  - `[2]` asset subtype — original variant string preserved here on rollup (drives the **v14 [D1] subtype drill-down**)
  - `[3]` human readable point name
  - `[4]` point description
  - `[5]` object type (AI/AO/BI/BO/etc.)
  - `[6]` data type
  - `[7]` range min
  - `[8]` range max
  - `[9]` unit
  - `[10]` access (`R` / `R/W`)
  - `[11]` DBO point name (the name itself)
  - `[12]` DBO compliance string (literal `"NOT IN DBO"` or the field name again)
  - `[13]` available for smart?
  - `[14]` projects points used in (comma-separated string)
  - `[15]` system owner comments
  - `[16]` notes
  - `[17]` `inDbo` flag (computed: 1 if `D.f` includes the name)
  - `[18]` `compliantFlag` (computed: 1 if every underscore segment is in `sfSet`)
- `D.f` — flat list of valid DBO field names. Refreshed by `syncDBO()` (now also writes sync metadata — see §3.7).
- `D.sf` — subfield dictionary `[name, category, description]`.
- `D.di` — "do not use" / non-DBO term mapping.

**`assetSubtypes` (v14, new)** — derived index `{canonicalAssetType: [subtype1, subtype2, …]}` built once at load time from `D.p[i][2]`. Powers the [D1] subtype pill bar in the Equipment detail panel. Built around line 215.

**`EQ` — by-equipment view** — same shape as v13/v14. The latent rollup IIFE bug flagged in v14's §10 (`dst.p[pk]=(dst.p[pk]||0)+src.p[pk]` treating arrays as numbers) is **fixed in v15** (~line 349): now `dst.p[pk]=(dst.p[pk]||[]).concat(src.p[pk])` with an `Array.isArray` guard. Marked inline with `// [v15 FIX]`. Safe to regenerate `EQ.equip` from raw rows now.

**`DBO` — ontology reference** — unchanged from v13.

### 3.2 State

```js
var S = {
  page: 'welcome'|'home'|'app',
  tab: 'BMS_MEP',
  q: '', df: 'all', cf: 'all', af: 'all', pf: 'all',
  sec: null,
  sq: '', gq: '',
  bds: [''], bc, bm, bmd, bp, bag, bagd: '',  // Builder
  bfree: '',
  showAdv: false,
  selEquip: null,
  selSubtype: null,    // v14 [D1]
  hist: [],            // NEW in v15 — nav history stack (max 40), drives Back / Alt+← / Esc
  fontSz: 'md',        // NEW in v15 — 'sm'|'md'|'lg', persisted to epl10_fsz, applied via data-fsz attr
  role, guideOpen, dedup,
  scopeQty, scopeProj, scopeCost,
  editIdx, selEnt, nsFilter
};
```

Persisted in `localStorage`:
- `epl10_role` — selected role
- `epl10_a` — manually added points
- `epl10_tender` — saved tender estimates
- `epl10_pending` — pending submission queue (for [U1] flow)
- `epl10_dboSync` — v14 [D5]: `{lastSync, fieldCount, autoSchedule, intervalDays}`
- `epl10_fsz` — **NEW in v15**: font size preference (`sm`/`md`/`lg`)
- `epl10_catalogMeta` — **NEW in v18**: browser-local manufacturer / model / notes metadata for subtype catalogue rows
- `epl10_auth_users` — **NEW in v18**: browser-local MSI sign-in user store
- `epl10_auth_session` — **NEW in v18**: browser-local MSI sign-in session
- `epl10_admin` — legacy admin flag used by pre-v18 builds; superseded in v18 by browser-local sign-in
- `t` — theme

### 3.3 Sections (unchanged from v13)

| ID            | Label              | Function                                                              |
|---------------|--------------------|-----------------------------------------------------------------------|
| `library`     | Point Library      | System-tabbed table, search/filter/dedup, CSV/Excel export            |
| `equipment`   | By Equipment       | Card grid + gap analysis + **subtype drill-down (v14 [D1])**         |
| `catalog`     | Subtype Catalogue  | **NEW in v18** standalone subtype records + metadata + suggested mappings |
| `projects`    | Projects           | Per-project comparison cards                                           |
| `builder`     | Name Builder       | Free-text input + 7 dropdowns (descriptor repeatable per [B2])        |
| `lookup`      | DBO Lookup         | Two-column field/subfield search                                       |
| `validation`  | Validation         | Diagnostic counts + bad-points table                                   |
| `entities`    | Entity Types       | DBO entity browser                                                     |
| `submit`      | Review Queue       | Upload/approval workflow (admin) — from [U1]                          |
| `scope`       | Tender Calculator  | Equipment quantity → estimated point count + cost                     |
| `connections` | Connections        | DBO connection types, spatial hierarchy, units reference              |

### 3.4–3.6 — unchanged from v13

(See git history of this file for the v13 detail on roles, systems, and the `validatePoint()` bug centre.)

### 3.7 v14 DBO sync metadata + helpers

New helpers around line 571:
- `getDboSyncMeta()` — reads `epl10_dboSync` localStorage; returns `{lastSync, fieldCount, autoSchedule, intervalDays}` with sensible defaults (`autoSchedule:false`, `intervalDays:7`).
- `setDboSyncMeta(m)` — writes back.
- `dboSyncDue()` — true if auto-schedule on AND interval has elapsed.
- `dboSyncAgo()` — human-readable "2 days ago" / "1 month ago" for the file menu label.
- `toggleDboAuto()` — flips `autoSchedule` and re-renders.
- `syncDBO(silent)` — now accepts a `silent` flag (used by the auto-trigger). Stores `lastSync` + `fieldCount` after every successful sync. Toast now reports diff: `"✅ DBO synced: 1499 fields (+3 new)"` / `"(no change)"` / `"(-1)"`.

Auto-trigger lives at the bottom of the script (around line 1196): `if(dboSyncDue()){setTimeout(function(){syncDBO(true)},800)}` — runs once on initial load if scheduled.

### 3.8 v15 additions — navigation, export, and QOL layer

The v15 work is mostly a layer *around* the existing v14 guts. Landmarks, all verified by grep against `/home/claude/v15.html`:

- **Navigation history stack** (~lines 472, 482). `S.hist` is an array of `{sec, equip, subtype, tab}` snapshots capped at 40. `_push()` writes each state change through `window.history.pushState` so the browser Back button works, and `Esc` + `Alt+←` both pop the stack. `setSec()` (line 488) was rewritten in v15 to **stop clearing `selEquip`/filters across section switches** — state is preserved end-to-end, which is what the back button relies on.
- **Font size toggle** (~lines 472, 500). `S.fontSz` cycles `sm → md → lg → sm` via `cycleFont()`, persists to `localStorage.epl10_fsz`, and applies itself through `document.documentElement.setAttribute('data-fsz', ...)`. CSS selectors on `html[data-fsz="sm"]` / `="lg"` in the v15 CSS block scale the root font accordingly.
- **Breadcrumb trail** (CSS ~lines 176–182, JS ~line 501). `.crumbs` bar above each section with clickable `.crumb` items: `Home → section label → equipment → subtype`. Each crumb is a `_push()` target. Hides at ≤768 px per the responsive pass.
- **Unified export modal** (~line 521). Single entry point — pick *what* (current view / master / filtered) × *format* (CSV / Excel / JSON) × *scope* — routes through one function instead of the four scattered buttons v14 had.
- **`V15_CSV_HDRS` canonical 19-column schema** (line 728). Constant used by both CSV and Excel export paths so they stay in lockstep. The 19 columns match the in-memory `D.p` row layout described in §3.1. `importCSV` sniffs for this schema (`isV15` check: `'system'` at index 0 AND `'dbo point name'` present AND ≥17 columns) and round-trips it; otherwise it falls back to the v14 16-col shape.
- **Filter-aware exports including subtype** (~lines 729–755). `exportCSV` honours `S.selSubtype` in both the row set *and* the filename — `Electracom_v15_<tab>[_filtered].csv`. This clears the v14 §10 item: *"If Dylan/John like [the subtype drill-down], v15 should plumb it into `genPointList()` so the CSV export honours `S.selSubtype`."* Excel export (~lines 758–793) uses the same canonical headers and writes `Electracom_Master_Point_Library_v15[_filtered].xlsx`. JSON export (~line 796) stamps `version: 'v15'` and writes `Electracom_Library_v15.json`.
- **Keyboard shortcuts** (~line 572). `/` focuses the search box. `Esc` closes any open modal first, otherwise pops the history stack. `Alt+←` steps back one history entry.
- **Undo-on-delete** (~lines 934–947). The delete confirm prompt now says *"You'll have 10 seconds to undo"*; after confirmation the row goes into a pending-delete holding pen, a toast with an Undo link is shown, and `undoDel()` restores the row if clicked within the window. Real commit happens on the 10s timer.
- **DBO sync status pill in nav** (~line 1006, marked `// [v15] DBO sync status pill — surfaced in nav, click to sync`). The sync status that v14 buried in the file menu is now also surfaced as a clickable pill in the main nav, showing "DBO: 2d" / "DBO: fresh" etc. Click to sync immediately. Complements the v14 file-menu row, doesn't replace it.
- **Responsive CSS pass** (breakpoints at 1024 / 768 / 720 / 480 px, v15 additions block starts ~line 163). `welcome-grid`, `feat-grid`, `cards`, `ent-grid`, `prof-grid`, `qa-grid`, `nav-file-menu`, and `.crumbs` all reflow cleanly on tablets and phones. First time the tool has been properly usable below 1024 px — worth a site visit test on John's iPad.

### 3.11 v17.1 additions — Dylan strict-reading alignment

Same v17 file, in-place patch after Rajesh asked for full Dylan alignment with no remaining strict-reading gaps. Three targeted edits:

- **[V1] strict — zero INFO/WARNING surfaces anywhere in validation.**
  - `validatePoint()` line 720: partial-miss of DBO vocabulary (previously `info`) → `error`.
  - `validatePoint()` line 721: total-miss of DBO vocabulary (previously `warning`) → `error`.
  - `validatePoint()` line 749 ([V2] diagnostic dictionary "did you mean" suggestions): previously `info` → `error`. Known-bad terms with a suggested replacement now surface in the primary errors table alongside their fix hint.
  - Validation stats card (line 1335) drops the "Warnings" tile — always-zero now, was user-facing clutter. Stats are now Errors / Clean / Custom Points Checked.
  - After this pass: grep `sev:'warning'` and `sev:'info'` both return 0 hits. Validation render contains zero INFO/WARNING surfaces.

- **[E1] strict — "required / optional" wording removed from render.**
  - Equipment panel summary (line 1224) rewritten from `"Gap Analysis: 3/5 required, 2/4 optional, 1 extra"` to `"Coverage: 5 of 9 standard DBO points captured · 1 extra"`. The data source (`gap.req`/`gap.opt` from `EQ.standards`) is unchanged — just the user-facing wording now matches Dylan's "just keep All Points section" without losing the coverage stat.
  - Grep `required, .*optional` in render now returns 0 hits.

- **[U1] strict — live validation panel under the Submit Points form.**
  - New `uploadValidate()` function (added right before `submitPoint()`) runs `validatePoint()` on the current `#upDbo` input and renders into a `#upValidate` div. Fires on every `oninput` of the DBO name field.
  - Empty input → helper message "Enter a DBO name above — live validation will appear here."
  - No errors → green "✓ DBO-compliant" pill + ready-to-submit note.
  - Has errors → count + each error line with the existing `val-err` badge, matching the Validation section's styling so the user learns the same vocabulary before submitting.
  - The existing submit-time toast-block (line 416–417) is preserved as a backstop, but the design engineer now sees the result *while they type* — which is what Dylan asked for.

### 3.12 v18 additions — subtype catalogue, metadata, and browser-local auth

v18 is the first pass at the items that had previously sat in the deferred bucket:

- **Standalone `catalog` section** — new `S.sec === 'catalog'` render path with its own breadcrumb branch, home card, grouped-nav entry, search/filter toolbar, and "Open In Equipment" handoff.
- **Subtype catalogue data model** — `buildSubtypeCatalog()`, `getCatalogEntry()`, and `getSubtypeRows()` derive asset/subtype records from the existing point library. Rows are keyed as `asset||subtype`.
- **Browser-local manufacturer/model metadata** — `epl10_catalogMeta` stores `manufacturer`, `model`, and `notes` per subtype record. This is not a shared backend database; it is browser-local only.
- **Suggested mappings** — `getCatalogMappings()` combines `EQ.standards` with observed point names to show required, optional, and extra observed points. This is a practical suggestion layer, not a Tim/Dylan-approved exhaustive mapping exercise yet.
- **Browser-local MSI sign-in** — `epl10_auth_users` + `epl10_auth_session` replace the old raw `epl10_admin` toggle. Admin-gated actions now call `ensureAdmin(...)`. This is stronger than a trust toggle, but it is still not real SSO / backend auth.
- **Role guidance update** — Commissioning Engineer now recommends `catalog` in addition to `equipment` and `builder`.

### 3.10 v17 additions — Dylan-alignment + export version cleanup

Two targeted fixes on top of v16. Built 14 Apr 2026 from a line-by-line audit of `Point naming tool comments.docx` against the v16 HTML.

- **[V1] structural warnings promoted to errors** (validatePoint, ~lines 689–716). v16 separated errors/warnings but kept six structural checks at `warning` severity and rendered them inside a collapsible `<details>` element in the validation section. Dylan's exact words: *"Don't include INFO/WARNING parts, only the bits where the point subfields are incorrect or etc."* The six warnings were all "subfield incorrect" issues — promoted to `sev:'error'` so they appear in the primary Errors table:
  1. Hyphens in name (line 689)
  2. Starts with underscore (line 691)
  3. Ends with underscore (line 692)
  4. Doesn't end with a known point-type suffix (line 698)
  5. `_status` on an analogue measurement — Dylan [B5] (line 704)
  6. Duplicate subfield in name — Dylan [B6] (line 716)
  
  The "no DBO vocabulary match" check (line 721) is **kept as warning** because some valid points are intentionally `NOT_IN_DBO` and the user has opted out of subfield compliance for those — flagging it as an error would generate false positives. The collapsible warnings section is preserved (rarely populated now) so future soft checks have a place to land.

- **v15 export-string regressions** (5 places). v16 fixed the title tag but the export paths still carried `v15` in user-visible filenames and the JSON version field. v17 fixes:
  - `exportCSV` full-library filename (line 574): `Electracom_v15_full_library.csv` → `_v17_`
  - `exportCSV` per-tab filename (line 770): `Electracom_v15_` → `_v17_`
  - `exportXLSX` workbook filename (line 811): `Electracom_Master_Point_Library_v15` → `_v17`
  - `exportJSON` (line 814): both `version:'v15'` → `'v17'` AND `Electracom_Library_v15.json` → `_v17.json`
  - `genPointList` per-equipment CSV filename (line 991): `Electracom_v15_` → `_v17_`
  - Title tag (line 6) and nav badge (line 250 `<span class="nver">`) bumped from v16 to v17.
  
  **Not changed**: the JS constant `V15_CSV_HDRS` and the importCSV toast `'v15 schema'` — both refer to a stable internal data shape (the 19-column canonical schema), not a release version. Renaming the constant carries breakage risk for no user-visible benefit.

### 3.9 v16 additions — font toggle + tender calculator correctness

Two targeted fixes on top of v15. Neither adds new features; both fix bugs Rajesh reported after testing v15:

- **Font toggle actually works** (~lines 164–172). v15 tried to scale text by overriding `body{font-size}` and a couple of `table th/td` rules, but `body` had a hardcoded `font-size:13px` and there are **181 absolute `font-size:Npx` declarations** in inline styles throughout the render code — so the toggle had near-zero visible effect. v16 replaces the font-size CSS with CSS `zoom` on `body`: `html[data-fsz="sm"] body{zoom:0.88}` / `html[data-fsz="lg"] body{zoom:1.15}`. `zoom` scales the entire layout uniformly including all absolute px values, so every inline size scales with it. There's also a `@supports not (zoom:1)` fallback using `transform:scale()` + `transform-origin:top left` for any browser that doesn't support `zoom` (Firefox ≤125; Firefox 126+ supports it natively). The cycleFont → data-fsz → localStorage plumbing from v15 is unchanged — only the CSS that reads the attribute was rewritten.

- **Tender Calculator — typical vs max per-unit** (EQ rollup ~lines 351–370, helpers ~lines 608–637, render ~lines 1476–1556). The v15 calculator multiplied quantities by `EQ.equip[k].u`. That value is the union of all unique DBO point names ever observed across every project + every subtype for that equipment type — e.g. AHU `u=83`, Switchboard LV `u=81`. Entering "3 AHUs" returned 249 points when the realistic answer is more like 60–90. Fix:
    1. **Rollup IIFE** (~line 362) now computes two per-unit numbers for each equipment key: `eq.uTyp` = max unique DBO names seen on **any one project** (deduped per project — a realistic single-install count), and `eq.uMax` = the existing `.u` value (worst-case union, kept for the Max mode). Marked `// [v16 FIX]`.
    2. **State** (~line 484) gained `scopeMode:'typ'` (default Typical).
    3. **Helpers** (~line 608) — new `setScopeMode(m)` and `_ppu(eq)` picker; `saveTender` / `loadTender` / `exportTender` all route through `_ppu()` so the mode is persisted, restored, and written into the CSV header (`"Estimation mode","Typical (single install)"` or `"Max (worst case)"`).
    4. **Render block** (~line 1476) — new Typical / Max pill toggle in the toolbar styled as an inline-flex button group with active-state via `--ac` colour. Each row shows both numbers, e.g. `AHU (20/unit · 83 max)` in Typical mode or `AHU (83/unit · 20 typ)` in Max mode. Total card label flips to `Total Estimated Points (TYPICAL)` or `(MAX)`. Footer copy explains what each mode actually does — honest about why the numbers differ, which is the key thing for the Carry demo.
    5. **Copy rewrite** — the top-of-section intro now mentions Typical vs Max explicitly. No more "standard point counts" handwave that implied typical when the tool was returning worst-case.

- **Title tag regression** — fresh v15 upload still had `<title>…v14</title>` at line 6 (same pattern as the v14→v15 transition). Fixed to v16. Add a pre-release grep for stale version strings to the release checklist.

- **False alarm from v15 §10 backlog** — the "skip-welcome button missing" note in the v15 §10 backlog was wrong. grep found it at line 1043 of v15: `<button onclick="setRole('des')">Skip — just let me in →</button>`. It's there, just under `setRole('des')` rather than a `skipWelcome` identifier. Removed from the v17 backlog.

---

## 4. Dylan-docx ↔ HTML gap matrix (audited 14 Apr 2026 against v18)

Every Dylan-docx item below was verified by direct grep against the current HTML build. Source: `Point naming tool comments.docx` (extracted to `_docx_extract/dylan_comments.txt`, 56 lines) + the 10 Apr call.

| ID  | Dylan asks for                                              | v17 HTML location                              | Verified |
|-----|--------------------------------------------------------------|------------------------------------------------|----------|
| B1  | Aggregation + Aggregation Descriptor at start of DBO name   | `bld()` line 666: `[bag, bagd, …descs, bc, bmd, bm, bp]` | ✅ |
| B2  | Multiple descriptors allowed (e.g. `supply_air_temperature_sensor`) | `S.bds:[]` array, `addBldDesc`/`removeBldDesc` line 670–671 | ✅ |
| B3  | Measurement_descriptor before measurement                   | Builder UI line 1280–1281: `bmd` then `bm`     | ✅ |
| B4  | Strip INFO from Builder result panel                        | Line 1287–1290: only error/warning/pass classes rendered | ✅ |
| B5  | Flag `_status` on analogue point names                      | `validatePoint()` line 700–708 (now `sev:'error'` in v17) | ✅ |
| B6  | Duplicate subfield check                                    | `validatePoint()` line 710–716 (now `sev:'error'` in v17) | ✅ |
| L1  | Drop Range / access / smart / subtype from library main     | Library `<thead>` line 1195 — none of these columns present | ✅ |
| L2  | Two separate columns: In DBO + Compliant                    | Library `<thead>` line 1195: `<th>In DBO</th><th>Compliant</th>` | ✅ |
| L3  | Notes admin-only                                            | Lines 1193–1208: `var adm=isAdmin();` gates header + cell | ✅ |
| L4  | DBO Point Name cell — name only, not the purple compliance bit | Line 1204: renders `CI + r[11]` only (no compliance label inline) | ✅ |
| V1  | Validation: don't include INFO/WARNING, only subfield-incorrect | Line 1287 (Builder) + line 1338 (Validation primary errors). v17 promoted six warnings to errors; v17.1 promoted the last info + last warning too and removed the zero-valued Warnings stat card. Grep `sev:'warning'`/`sev:'info'` now returns 0 hits — see §3.10 + §3.11 | ✅ |
| E1  | By Equipment: remove Required/Optional, just keep All Points | Split tables dropped in v13; v17.1 also rewrote the coverage summary to drop the "required"/"optional" words themselves (line 1224) — see §3.11 | ✅ |
| U1  | Upload + MSI-approval workflow for design-engineer point submissions, giving "confirmation if names are correct or not" | Submit/Review section, `epl10_pending` queue, isAdmin-gated approve/reject; **v17.1 added `uploadValidate()` live validation panel** under the Submit form so the design engineer sees DBO compliance as they type — see §3.11 | ✅ |
| D1  | AHU subtype drill-down (e.g. SystemAir AHU)                 | `assetSubtypes` index ~line 215, pill bar lines 1227–1236 | ✅ |
| D5  | Auto-check for DBO field/subfield updates + confirmation    | `getDboSyncMeta`/`syncDBO`/auto-trigger ~line 1196 + sync pill line 1024–1028 | ✅ |

**v18 status on the previously deferred bucket:**
| ID  | Dylan asks for                                              | Status |
|-----|--------------------------------------------------------------|--------|
| D2  | Fan-coil-unit database with model/manufacturer metadata     | **Started in v18** via `catalog` + `epl10_catalogMeta`, but still browser-local metadata rather than a shared manufacturer DB |
| D3  | Standalone subtype page                                     | **Started in v18** via the new `catalog` section |
| D4  | Auto-mapping of every applicable DBO point to every asset type | **Started in v18** as suggested mappings from `EQ.standards` + observed points, but still not the full Tim/Dylan mapping exercise |
| D6  | Real auth (SSO etc.)                                        | **Partially addressed in v18** with browser-local MSI sign-in; still not real SSO / backend auth |

### 4.0 Original Dylan-docx item list (preserved for traceability)

This consolidates Dylan's `.docx` + the 10 Apr call transcript. All items now landed except where noted above.

### 4.1 NAME BUILDER — `S.sec === 'builder'`
- **[B1]** Field order ✅ v13 (lines 822–844)
- **[B2]** Repeatable descriptors ✅ v13
- **[B3]** Measurement_descriptor before measurement ✅ v13
- **[B4]** Remove INFO/WARNING noise ✅ v13
- **[B5]** Flag `_status` on analogue points ✅ v13
- **[B6]** Duplicate subfield check ✅ v13

### 4.2 POINT LIBRARY — `S.sec === 'library'`
- **[L1]** Drop columns ✅ v13
- **[L2]** Split In DBO / Compliant ✅ v13
- **[L3]** Notes admin-only ✅ v13
- **[L4]** DBO Point Name cell name-only ✅ v13

### 4.3 BY EQUIPMENT — `S.sec === 'equipment'`
- **[E1]** Drop required/optional split ✅ v13
- **[E2]** Per-AHU-type drill-down — **✅ now landed in v14 as [D1] (was deferred)**

### 4.4 DBO LOOKUP — `S.sec === 'lookup'`
- **[K1]** Render full list on entry ✅ v13

### 4.5 VALIDATION — `S.sec === 'validation'`
- **[V1]** Strip INFO/WARNING ✅ v13
- **[V2]** Fix diagnostic-dictionary loop ✅ v13

### 4.6 ASSET MODEL
- **[A1]** Collapse asset duplicates ✅ v13
- **[A2]** Subtype page — was "not in v12". v14 [D1] gives a drill-down inside the existing equipment detail panel rather than a whole new page, which is the lighter touch we agreed on the call.

### 4.7 GOVERNANCE
- **[G1]** Admin gating ✅ v13

### 4.8 NEW FEATURE
- **[U1]** Upload & validation workflow ✅ v13 (full submit/review queue, including admin approval)

### 4.9 Previously DEFERRED — re-evaluated for v14

- **[D1]** Per-manufacturer (SystemAir, Daikin) AHU drill-down. **✅ landed in v14** as a subtype pill bar. Implementation note below.
- **[D2]** Fan-coil-unit database with model/manufacturer metadata. **Started in v18** as browser-local subtype metadata (`epl10_catalogMeta`), but still not a shared manufacturer DB.
- **[D3]** Standalone subtype page. **Started in v18** as the new `catalog` section.
- **[D4]** Auto-mapping of every applicable DBO point to every asset type. **Started in v18** as suggested mappings, but still needs the Tim/Dylan exercise for a full approved mapping matrix.
- **[D5]** Confirmation around DBO auto-update (`syncDBO()`). **✅ landed in v14**. See §5 below for the full implementation.
- **[D6]** Real auth (proper login). **Partially addressed in v18** with browser-local MSI sign-in; still needs backend / SSO before wider rollout.

---

## 5. Implementation status

### 5.1 v14 — Dylan-docx completion

All v13 features carry over unchanged. v14 added:

### Bucket G — Previously deferred items now landed

#### [D5] DBO auto-update — confirmation, status & schedule ✅
1. **localStorage `epl10_dboSync`** stores `{lastSync, fieldCount, autoSchedule, intervalDays}`. Default `intervalDays:7`.
2. **Helpers** (~line 571): `getDboSyncMeta`, `setDboSyncMeta`, `dboSyncDue`, `dboSyncAgo`, `toggleDboAuto`.
3. **`syncDBO(silent)`** rewritten (~line 577): now accepts a silent flag, writes `lastSync` + `fieldCount` to localStorage on success, and the toast reports a diff against the previous count (`+3 new` / `no change` / `-1`).
4. **File menu** (~lines 634–637): a non-clickable status row showing `Last synced: X · Y fields`, plus a clickable `Auto-sync weekly: ON/OFF` toggle row directly under the existing Sync DBO button.
5. **Auto-trigger** at the bottom of the script (~line 1196): if `dboSyncDue()` is true on load, fire `syncDBO(true)` after 800ms so the toast doesn't compete with the welcome render.

This addresses Dylan's *"Confirmation – does the tool automatically check for DBO field and subfield updates?"* directly: the answer is now visible in the file menu (with timestamp + field count), and the user can opt in to weekly auto-sync.

#### [D1] AHU subtype drill-down ✅
1. **`assetSubtypes` index** (~line 214) built once at load: `{canonicalAssetType: [originalSubtype1, originalSubtype2, …]}`. Sourced directly from `D.p[i][2]` which `normaliseAsset` populates.
2. **`S.selSubtype`** added to state (line 375). `selEquip()` clears it on equipment change. New `selSubtype()` toggle function (line 395).
3. **Pill bar** rendered in the equipment detail panel (~lines 817–824) when `assetSubtypes[S.selEquip]` has entries. Style reuses `.ns-pill` (the Entity Types section's pill class) so it's visually consistent and needs no new CSS.
4. **Filtered table** (~lines 825–836): when `S.selSubtype` is set, the table reads from `points` directly, deduping by DBO name and filtering on `[1]===selEquip && [2]===selSubtype`. Header changes to `Points for {subtype} (N)`. When unset, falls back to the existing `upts` (gap-analysis-driven view).

This is the foundational shape Dylan wanted: pick AHU → see "AHU TYPE-1", "AHU TYPE-2", "Air Handling Unit" pills → click one → see only those points. Once project data starts carrying real manufacturer metadata (SystemAir, Daikin etc.), the same UI flips from subtype to manufacturer with no rework — the pill bar just reads from a different index field.

### 5.2 v15 — §10 backlog + QOL hardening

v14's §10 backlog is fully cleared, plus a layer of navigation / export / accessibility polish on top. Grep-verified landmarks:

#### Bucket H — v14 §10 resolutions

- **EQ.equip rollup bug** ✅ fixed at ~line 349. `// [v15 FIX] src.p[pk] is an array of point objects per project — concat, don't numeric-add`. Regenerating `EQ.equip` from raw rows is now safe.
- **Subtype drill-down export** ✅ — `S.selSubtype` is now honoured by every export path (CSV / Excel / JSON) via the shared `V15_CSV_HDRS` 19-col schema, and the filename reflects the filter state. Clears v14 §10 item 3.
- **Misnamed `.docx`** — ❌ still unresolved at the filesystem level. Rename or re-save is a housekeeping task, not a code change.

#### Bucket I — v15 QOL additions

- **Navigation history + Back button** — `S.hist` stack, `pushState` integration, Esc / Alt+← / browser back all work. `setSec()` no longer clears `selEquip`/filters between sections.
- **Breadcrumb trail** — clickable `Home → section → equipment → subtype` bar, responsive at 768 px.
- **Font size toggle** — `sm`/`md`/`lg`, persists via `epl10_fsz`, applied via `html[data-fsz=...]`.
- **Unified export modal** — single entry point replaces v14's scattered buttons. What × format × scope all routed through one place.
- **V15_CSV_HDRS 19-col canonical schema** — used by both CSV and Excel. `importCSV` sniffs for it and round-trips cleanly; falls back to the v14 16-col shape for older files.
- **Keyboard shortcuts** — `/` focuses search, `Esc` closes modal / pops history, `Alt+←` back.
- **Undo-on-delete** — 10-second window with toast undo link. Prompt text updated to mention the undo window.
- **DBO sync status pill in nav** — complements the v14 file-menu row, gives one-click access from anywhere in the tool.
- **Responsive CSS pass** — breakpoints at 1024/768/720/480 px across `welcome-grid`, `feat-grid`, `cards`, `ent-grid`, `prof-grid`, `qa-grid`, `nav-file-menu`, `.crumbs`. First time the tool is properly usable below 1024 px.

### Version cleanup
- Title tag, nav badge, xlsx/JSON export filenames, importCSV detection all bumped to v15. Title tag was stale in the initial v15 build (still said v14) — patched during this update session.

### File stats
- v13: 1,185 lines, ~523 KB
- v14: 1,229 lines, ~527 KB (+44 lines, +4 KB over v13)
- v15: 1,627 lines, ~533 KB (+398 lines, +6 KB over v14)
- v16: 1,658 lines, ~536 KB (+31 lines, +3 KB over v15)
- v17 initial pass: 1,658 lines (in-place severity flips + version-string bumps)
- v17.1 (current): 1,683 lines, ~538 KB (+25 lines for `uploadValidate()` function + live validation panel HTML + strict-reading edits)
- v18 (current working build): 1,926 lines, ~571 KB (+243 lines over v17.1 for catalogue, metadata, mapping, and browser-local auth work)
- JS parses cleanly (validated via `new Function(mainScript)` on 14 Apr v17.1 build); v15/v16/v17/v17.1 additions are grep-verifiable at the line numbers called out in §3.8, §3.9, §3.10, and §3.11.
- Severity grep after v17.1: `sev:'warning'` = 0, `sev:'info'` = 0, `sev:'error'` = 14 (all structural / subfield-incorrect checks per Dylan's [V1]).

### Things explicitly NOT touched in v15
- Anything in §4.9 [D2], [D3], [D4], [D6] — still open for a later bucket.
- Tender Calculator, Entities, Connections sections (beyond picking up the responsive grid classes).
- Role/welcome flow.
- No new Dylan-docx items — v15 is a hardening pass, not a feature pass.

### 5.4 v17 — Dylan-alignment audit + export version cleanup

Built 14 Apr 2026. Triggered by a fresh request to verify Dylan's docx items line-by-line against the actual HTML rather than trusting CLAUDE.md's ✅ marks. Found two issues; both fixed in v17.

#### Bucket K — v16 §10 resolutions

- **`exportJSON` `version:'v15'` + `Electracom_Library_v15.json`** (line 814) — third instance of the version-string regression pattern. Patched to v17.
- **`exportCSV`/`exportXLSX`/`genPointList` filename leftovers** (lines 574, 770, 811, 991) — not previously called out in the v16 §10 backlog because the audit had been title-tag-only. v17 catches all five and bumps. Updated release checklist (§10) now grep-checks export paths too, not just `<title>`.
- **Title tag + nav badge** — both bumped from v16 to v17 in the same pass.
- **[V1] Validation INFO/WARNING strict re-read** — Dylan's exact wording is *"Don't include INFO/WARNING parts, only the bits where the point subfields are incorrect or etc."* v16 stripped INFO from the Builder (Dylan [B4]) and the Validation primary table, but kept warnings in a collapsible. The six warning-severity checks are *all* "subfield incorrect" issues, so they were promoted to error in v17. See §3.10 for the per-line list.

#### Things explicitly NOT touched in v17

- All Dylan-docx items B1–B6, L1–L4, E1, U1, D1, D5 — verified-against-HTML and already correct, see §4 gap matrix.
- Anything in §4 deferred bucket [D2]/[D3]/[D4]/[D6] — still open.
- v15 navigation/export/breadcrumbs/undo-on-delete/sync pill/responsive CSS — untouched.
- v16 font toggle (CSS `zoom`) + tender calculator (Typical/Max) — untouched.
- Role/welcome flow — untouched.
- Internal `V15_CSV_HDRS` constant + `'v15 schema'` toast string — refer to a stable internal data shape, not the release version. Renaming carries breakage risk for no user-visible benefit.

### 5.3 v16 — §10 backlog + correctness fixes

v15 §10 backlog items now resolved. Scope kept deliberately tight — Rajesh reported two bugs, both fixed; no new features.

#### Bucket J — v15 §10 resolutions

- **Font S/M/L button does nothing** ✅ fixed at ~lines 164–172. Replaced the ineffective `font-size` overrides with CSS `zoom` on `body` (+ `transform:scale` fallback for browsers without `zoom` support). See §3.9 for the full explanation of why v15's approach had near-zero effect (body hardcoded to 13px + 181 absolute-px inline styles overriding).
- **Tender Calculator producing inflated numbers** ✅ fixed. v15 was multiplying quantities by `eq.u`, which is the worst-case union of all unique DBO points across every project + every subtype — e.g. 83 points/AHU when realistic is ~20–30. v16 adds `eq.uTyp` (max on any single project, computed fresh in the rollup IIFE) alongside the existing `eq.uMax`, defaults the calculator to Typical mode, and exposes a Typical/Max pill toggle. Both numbers are visible per row so the user sees exactly what they're getting. Mode persists in saved estimates and appears in CSV exports. See §3.9.
- **Title tag regression** ✅ fixed. Fresh v15 upload still said v14 at line 6 (same as v14→v15); patched to v16. Add a release-checklist grep for stale version strings.
- **skip-welcome button "missing"** — ❌ false alarm. grep on v15 line 1043 shows it exists under `setRole('des')`. Removed from backlog.

#### Things explicitly NOT touched in v16

- Anything in §4.9 [D2], [D3], [D4], [D6] — still open.
- v15's navigation, export, breadcrumbs, undo-on-delete, DBO sync pill, responsive CSS — all untouched, carried forward.
- Role/welcome flow — untouched.
- No new Dylan-docx items.
- Subtype-aware tender calculation (using `S.selSubtype` to pick a specific AHU subtype's point count rather than the rolled-up AHU). Would be nice but out of scope — the Typical/Max toggle is enough to make the numbers honest for Monday's drop. Park for v17 if John asks.

---

## 6. Delivery plan / dates

| Date           | What happens                                                              |
|----------------|---------------------------------------------------------------------------|
| Fri 10 Apr     | Call held. v14 built same day. v15 built same evening as a QOL/backlog pass on top. v16 built later same evening after Rajesh reported the font-toggle + tender-calculator bugs. Rajesh works device qualification by day, point tool by night. Not working the weekend. |
| Mon 13 Apr ~11:00 | v16 dropped to John. |
| **Tue 14 Apr** | **v17 built today** — Dylan-docx ↔ HTML gap audit. [V1] structural warnings promoted to errors; v15 export-string regressions cleaned up (5 places). John on site at 334 Oxford Street. |
| Wed 15 Apr     | John prepping for "the one test".                                         |
| Thu 16 Apr     | John on leave.                                                            |
| Fri 17 Apr     | John on leave.                                                            |
| **w/c 20 Apr** | **Internal demo to Carry.** Avoid the 23rd if possible — John has the Operations & Project Managers meeting that day. |

---

## 7. Strategic / context notes

- **The point tool is not MSI-only long-term.** Once stable, John will roll it out to design engineers, software, and ops. Wider rollout will need an "idiot's guide" — John's words on the 10 Apr call: *"this stuff comes natural to a lot of us. It's not going to come natural to a lot of these guys."*
- **Consistency across projects is the headline business case.** John: *"the sooner I can get it out to the wider project teams… it's going to be better for the business."*
- **⚠️ Scope-creep risk — 23 Apr ops/PM meeting.** John is presenting MSI tools to the wider Operations & Project Managers group and has said he'll *"open the floor"* for other tool requests. Expect new asks to land on Rajesh's queue that week. Pre-plan: before the 23rd, agree with John which tools are truly MSI-funded vs parked for later scoping. Also — John flagged that the audience is currently *"petrified"* by smart/AI language, so any new tool requests may arrive under-specified. Don't commit to scope in the meeting; capture, triage later.
- **Call-confirmed scope boundaries (10 Apr, Dylan + John):** keep generic (no FCU/AHU manufacturer database — [D2] explicitly out), collapse asset duplicates ([A1] — AHU TYPE-1/TYPE-2/"Air Handling Unit" all → AHU), admin = MSI only (adding/editing Library), non-MSI users go via the Submit queue. These are product decisions, not oversights — don't re-open without John.
- **Device Qualification Tool is the higher priority** until 334 Oxford Street is delivered.
- **Subtype drill-down (v14) is generic** — keeps the door open for SystemAir/Daikin/etc. later without committing to a manufacturer database now.
- **Asset → DBO point mapping exercise ([D4]) is Tim/Dylan's job, not Rajesh's.** John on the call: *"you wouldn't know enough about these systems and assets to be able to do it."* Waiting on Tim being freed up. Dylan will bring examples from older project schedules in the meantime.

---

## 8. File / artefact references

| File                                            | Purpose                                                  |
|-------------------------------------------------|----------------------------------------------------------|
| `Electracom_Smart_Point_Reference_v18.html`     | **Current working version** — single-file app, ~571 KB, ~1,926 lines. Adds standalone subtype catalogue, browser-local manufacturer/model metadata, suggested mappings, and browser-local MSI sign-in. |
| `Electracom_Smart_Point_Reference_v17.html`     | Previous stable Dylan-aligned version. All export filenames bumped, structural validation promoted to errors, and strict-reading gaps closed in v17.1. |
| `Electracom_Smart_Point_Reference_v16.html`     | Previous version. Font toggle + tender calculator fixed but still carried five `v15` strings into export filenames + JSON version field. v17 cleans those up. |
| `Electracom_Smart_Point_Reference_v15.html`     | Nav/QOL/export layer. Font toggle had no visible effect; tender calculator returned worst-case as "standard". |
| `Electracom_Smart_Point_Reference_v14.html`     | Dylan-docx fully aligned: [D1] subtype drill-down + [D5] DBO auto-sync landed |
| `Electracom_Smart_Point_Reference_v13.html`     | Dylan's §4 items, except the two deferred (D1/D5)        |
| `Electracom_Smart_Point_Reference_v11.html`     | Pre-Dylan-feedback version                               |
| `Electracom_Smart_Point_Reference_v8.html`      | Older (~820 KB — pre data trim)                          |
| `Electracom_Smart_Point_Reference_v7.html`      | Older                                                    |
| `Smart_Point_Reference_Overview.html`           | Overview / landing page (stub)                          |
| `Point naming tool comments.docx`               | **Dylan's written feedback — canonical issues list.** ✅ **Actually is** a real Microsoft Word 2007+ binary `.docx` (PK zip header, `[Content_Types].xml`) — confirmed via `file` 14 Apr. The earlier CLAUDE.md note claiming it was UTF-8 plain text was wrong. To read it: `unzip word/document.xml` then parse with Python ElementTree (see `_docx_extract/dylan_comments.txt` for the extracted plain text used in the v17 audit). Filename also has spaces (not underscores) — match exactly. |
| `_docx_extract/dylan_comments.txt`              | Plain-text extraction of Dylan's docx, used for the v17 gap audit. 56 lines. Regenerate with `cd _docx_extract && unzip -o "../Point naming tool comments.docx"` then run the ElementTree extractor. |
| `Master_Point_Naming_Library.xlsx`              | Master library spreadsheet                              |
| `Electracom_Master_Point_Library_v7.xlsx`       | Older spreadsheet                                       |

---

## 9. Open questions for the next call

- For the upload-and-validate workflow: does John want email notification on submission, or just an in-tool queue?
- Admin auth — v18 now has browser-local MSI sign-in. For wider rollout, does this need real auth (e.g. SSO), or is browser-local sign-in acceptable as an interim step only?
- For asset rollup `[A1]`: should historic project records keep their original `AHU TYPE-1` label *only* in the subtype column, or also in a "legacy_label" field for full traceability?
- The asset → DBO point mapping exercise — when can Dylan/Tim block out time for it?
- v14 [D1] currently drills down by *subtype string* (the original asset_type variant). Is the next step to surface a `manufacturer` column on points, or to derive it from system_owner_comments where it's mentioned? Worth a five-minute conversation with Dylan.
- v14 [D5] auto-sync defaults to OFF and weekly when enabled. Is weekly the right cadence for John, or is monthly less noisy?

---

## 10. Known issues / cleanup backlog for v19

**Resolved in v17.1** (was the strict-reading gap list flagged after the initial v17 build):
- ~~[U1] design engineer doesn't see "correct or not" feedback until submit~~ — ✅ fixed. Live `uploadValidate()` panel under the form shows DBO compliance as they type. See §3.11.
- ~~[E1] Gap Analysis summary still says "required / optional"~~ — ✅ fixed. Now reads "Coverage: N of M standard DBO points captured · Z extra". See §3.11.
- ~~[V1] one warning + one info still in `validatePoint()`; Warnings stat card always zero~~ — ✅ fixed. Both promoted to error, Warnings tile removed from stats. Grep for `sev:'warning'`/`sev:'info'` now returns 0 hits.

**Resolved in v17 initial pass** (was the v16 §10 backlog + things found in the 14 Apr Dylan-docx audit):
- ~~Five `v15` strings still in v16 export paths~~ — ✅ fixed. `exportCSV` (lines 574, 770), `exportXLSX` (line 811), `exportJSON` (line 814 — both `version` field and download filename), `genPointList` (line 991). The v16 release-checklist grep only caught `<title>`; v17 expanded the checklist to cover all `Electracom_v*` and `version:'v*'` literals.
- ~~[V1] partial: warnings still rendered in collapsible `<details>`~~ — ✅ fixed. Six structural warnings promoted to `sev:'error'` so they appear in the primary Errors table per Dylan's strict reading. See §3.10.
- ~~`Point_naming_tool_comments.docx` "actually plain text" claim was wrong~~ — ✅ corrected. It IS a real binary Word `.docx`. Note in §8 updated, with extraction recipe.

**Resolved earlier** (was the v15 §10 backlog, fixed in v16):
- ~~Font S/M/L button has no visible effect~~ — fixed in v16 with CSS `zoom` on body.
- ~~Tender Calculator using inflated per-unit counts~~ — fixed in v16 with `eq.uTyp` + Typical/Max toggle.
- ~~Title-tag regression~~ — fixed in v16 (but five OTHER export-path version strings were missed; v17 catches them).

**Resolved earlier still** (was the v14 §10 backlog, fixed in v15):
- ~~EQ.equip rollup bug~~ — fixed in v15 at ~line 349.
- ~~Subtype drill-down export~~ — all three export paths honour `S.selSubtype` in v15.

**Carry forward to v18:**
- **Hard-refresh + nav history interaction** — `S.hist` is in-memory; a mid-navigation hard reload will reset it while the browser history survives, leaving the breadcrumbs inconsistent for one click. Low priority, worth a manual test before the Carry demo.
- **Sub-480px builder layout** — the builder section has seven dropdowns; no explicit phone-sized layout test was done in v15/v16. Test on an actual phone before the Carry demo.
- **Undo-on-delete timer edge case** — if the user clicks undo after the 10s window expires the toast may still be visible briefly. Low priority; 30-second check.
- **Subtype-aware tender calculation** — the v16 Typical/Max toggle makes the numbers honest, but doesn't let the user pick "3 × AHU TYPE-1 specifically". If John asks for per-subtype sizing, the hook is `S.selSubtype` + reading from `EQ.equip[k].p[project]` rather than the rolled-up `uTyp`. Park until asked.
- **Font toggle on very wide viewports** — `zoom` is clean in Chromium/Safari/Firefox-126+. If Rajesh finds an older Firefox in the wild, the `transform:scale` fallback kicks in but can clip scrollable areas at `lg`. Flag if it comes up.
- **D2 / D3 / D4 / D6 are only partially closed in v18** — catalogue and browser-local auth now exist, but the remaining gap is a shared manufacturer DB, a reviewed full mapping matrix, and real backend / SSO auth for wider rollout.
- **Internal `V15_CSV_HDRS` constant + `'v15 schema'` toast** — both refer to a stable internal data shape, not the release version, so they're fine functionally. If we ever change the schema (e.g. add a 20th column), rename to `V18_CSV_HDRS` or better `EXPORT_HDRS` to break the version coupling.
- **Pre-release version-string grep** — now part of the release checklist: `grep -nE "v1[3-6]|version:'v1[3-6]'" *.html` should return zero hits before drop. Caught the v17 export-path leftovers; would have caught the v16 title-tag regression too if it had existed earlier.
- **`Point naming tool comments.docx` filename has spaces** — match exactly when scripting. Not a code change; just a gotcha for future automation.

---

*Claude: v18 is the current state, built 14 Apr 2026 on top of v17.1. v17.1 remains the Dylan-aligned baseline: zero INFO/WARNING surfaces in validation, no "required/optional" language in the Equipment summary, and a live validation panel under Submit. v18 adds the first pass at the deferred catalogue/auth work: a standalone `catalog` section, browser-local manufacturer/model/notes metadata, suggested mappings from standards plus observed points, and browser-local MSI sign-in in place of the old raw admin toggle. The remaining gap is that D2/D4/D6 are still not production-complete: metadata is local not shared, mappings are suggested not formally approved, and auth is still not SSO/backend. Pre-demo checks now include: (1) open `Subtype Catalogue` and confirm filtering / breadcrumb / "Open In Equipment" flow, (2) sign in as MSI admin and confirm edit gating works, (3) save catalogue metadata and verify it persists on refresh, (4) export CSV/Excel/JSON and confirm filenames all say `_v18_`, and (5) re-run the v17.1 validation checks listed above. Keep §3.12, §4, §8, and §10 current as the code evolves.*

---

*Previous context (v17 initial pass):*

*v17 has shipped on top of v16, built 14 Apr 2026. It is a Dylan-alignment + export-versioning correctness pass — not a feature pass. The audit was: extract Dylan's docx via `unzip`/ElementTree, then verify each item (B1–B6, L1–L4, E1, V1, U1, D1, D5) line-by-line against the v16 HTML rather than trusting CLAUDE.md's ✅ marks. Found two issues: (1) v16's title-tag fix didn't extend to the export paths — five user-visible `Electracom_v15_*` filename strings + the `version:'v15'` JSON field were still there; (2) Dylan's [V1] strict reading "Don't include INFO/WARNING parts, only the bits where point subfields are incorrect" was only partially honoured — INFO was stripped but six structural checks were still labelled `warning` and buried in a collapsible. Both fixed in v17. The §4 gap matrix is the new ground truth; trust it over older ✅ marks. The release checklist now includes a `grep -nE "v1[3-6]|version:'v1[3-6]'"` step that would have caught v17's leftovers (and would catch the next slip). Next focus is the **w/c 20 Apr Carry demo** (avoid the 23rd). Before drop: (a) open the Validation section and confirm the previously-warning structural checks (hyphens, _status on analogue, duplicate subfield, missing point-type suffix) now appear in the primary Errors table, (b) export CSV/Excel/JSON and confirm filenames now say `_v17_` everywhere (not `_v15_`), (c) sanity-test v16/v15 regression paths (font toggle, Typical/Max tender, back button, breadcrumbs, subtype-filtered exports, DBO sync pill, undo-on-delete), (d) test the builder section on an actual phone below 480px. Keep §3.10, §4 gap matrix, and §5.4 current as the code changes.*
