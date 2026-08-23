# [Bug] "文件浏览" (Files action) does nothing on mobile — expects a host "aionui explorer column" that current DSH lacks

**dsh-pocket:** 1.12.3 (npm latest; git main 52b5c94, same as npm gitHead)
**Host DSH:** deepseek-harness b150a55 (master HEAD, "DSH Local Build" via `apps/cli web`)
**Device:** HarmonyOS 7.0.0 / API 26 phone, ArkWeb (in-app browser), narrow viewport

## Summary

On a narrow mobile viewport, tapping the **"文件浏览" (Files)** action (both the header icon
`data-mobile-nav="files"` and the drawer-footer entry `data-mobile-nav="explorer"`) produces no
visible UI at all. The click handler only toggles the frame attribute
`data-aionui-explorer-open`; the stylesheet then reveals
`[data-aionui-explorer-col]` via the rule:

```css
[data-mobile-nav="frame"][data-aionui-explorer-open] [data-aionui-explorer-col] {
  visibility: visible !important;
}
```

…but **`[data-aionui-explorer-col]` never exists in the DOM**, so nothing ever becomes visible.

## Evidence

1. **Button / handler** (from `/plugins/dsh-pocket/client.js`, hash `4e4763d1de46`, matches
   installed `node_modules/dsh-pocket/client/client.js` exactly):
   - `MobileNavToggle` (header): `toggleExplorer` = set/remove `data-aionui-explorer-open`
     on `[data-mobile-nav="frame"]`
   - `MobileDrawerFooter` (drawer "文件浏览"): `openExplorer` = set `data-aionui-explorer-open`
     + `toggleSidebar()`
2. **Runtime DOM check** (CDP `Runtime.evaluate` on the live page):
   - after clicking: `frame` has `data-aionui-explorer-open`, grid changes, but
     `document.querySelectorAll('[data-aionui-explorer-col]')` → `0` elements
   - no network requests, no `window.open`, no JS errors, no DOM insertion of any explorer content
3. **Full scan of every JS resource the page loads** (58+ scripts incl. main bundle,
   `index-*.js`, all `@deepseek-ai/dsh-client-*` plugins, dsh-pocket): the string
   `data-aionui-explorer-col` appears **only** inside dsh-pocket's own stylesheet and the
   toggle/explorer open logic — **no code anywhere renders the element**.
4. **dsh-pocket source comment** (`client/mobile/mobile-apply.tsx`, lines ~88–97) states the
   explorer column is **owned by the suite** ("dsh-web-ui compatibility: the aionui explorer
   column would render as a sheet over the whole mobile UI … the mobile stylesheet keeps the
   explorer column hidden by default and the header's Files action … opens it via the
   `data-aionui-explorer-open` marker").
5. **Host side**: `deepseek-harness` at b150a55 (current master) — repo-wide grep (source +
   node_modules) for `aionui`, `data-aionui-`, `文件浏览` finds **nothing**. The host
   column does not exist in the current release.

## Expected

Tapping Files opens the explorer (file-tree) panel — as a bottom sheet on mobile.

## Suggested fix directions

- Either the host (DSH suite) needs to provide the `[data-aionui-explorer-col]` explorer column
  (make it available on narrow viewports too), or dsh-pocket should ship its own file-tree sheet
  (self-contained) instead of relying on a possibly-absent host column.
- A version-compatibility note (min host DSH version / commit) would help: with
  dsh-pocket 1.12.3 + DSH b150a55 the feature is dead on arrival.

## Repro

1. Install dsh-pocket 1.12.3 on DSH (latest), open from a narrow phone viewport (ArkWeb or
   mobile browser; DevTools mobile emulation ≥1024px-wide emulation is fine too).
2. Tap the "文件浏览" icon in the session header (or the drawer footer entry).
3. Observe: frame attribute toggles, CSS rule exists, but no panel appears.

*(Reported from a HarmonyOS ArkWeb wrapper app; same result expected in any Chromium/Safari
narrow viewport since the missing element is host-side.)*
