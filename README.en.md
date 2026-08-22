# DSH Harmony

A **native HarmonyOS client for DeepSeek Harness**, designed to work with the [dsh-pocket](https://github.com/shaobeichen/dsh-pocket) plugin: scan the QR code on your desktop DSH settings page and use DeepSeek Harness on your phone in real time.

> 📱 Target: HarmonyOS 7.0 (phones / foldables / tablets) · personal use, not planned for app-store release
> 🇨🇳 中文: [README.md](README.md)

## Features

- 📷 **Scan to connect**: ScanKit system scan UI (album scanning included); scan → validate → open ArkWeb
- 🔌 **dsh-pocket ready**: LAN (`http://IP:3081`) and public (cloudflared tunnel) addresses both supported
- 📱 **Adaptive layouts**: single column on narrow phones; foldable-expanded / tablet landscape automatically switches to a "side panel + Web" two-column layout
- 🧭 **Connection history**: last 20 entries, long-press to delete, one-tap reconnect; manual URL input supported
- 🛡️ **Privacy-friendly**: only connection URLs are stored; PINs/credentials never persisted; one-tap clear for web data and history
- 🔧 **Full toolchain**: CLI build / on-device smoke tests / Hypium unit tests / GitHub Actions CI

## How it works

```
DSH Harmony (ArkWeb)
   │  scan to get URL
   ▼
dsh-pocket proxy (desktop :3081) ── rewrites Host/Origin to loopback, bypassing the browser trust fence
   │  in-page 8-digit PIN auth (App not involved)
   ▼
DeepSeek Harness web (desktop :3080)
```

See the [dsh-pocket README](https://github.com/shaobeichen/dsh-pocket) for plugin installation and usage.

## Requirements

| Item | Requirement |
| --- | --- |
| OS | HarmonyOS 7.0 (exact API version per your phone's About screen) |
| Dev | DevEco Studio 6.x (SDK / hvigor / ohpm / hdc) |
| Device | A HarmonyOS phone / foldable / tablet with USB debugging enabled |

> SDK config: `targetSdkVersion = 7.0.1(25)` (HarmonyOS 7.0.1), `compatibleSdkVersion = 6.0.0(20)` (wider compatibility).

## Quick start

1. Desktop: install the dsh-pocket plugin in DSH and open the "Phone access" settings page to get the QR code
2. Phone: install DSH Harmony (build locally or download a Release HAP; `hdc install -r` or local install)
3. Open the app → tap "Scan to connect" → scan the QR on your desktop screen → the DSH UI opens
4. Next time, pick a connection from history to go straight in; public connections require the 8-digit PIN inside the page

## Local development

```bash
./scripts/dev-tools.sh          # Detect DevEco/SDK/hvigor/ohpm/hdc paths
./scripts/build.sh              # Build debug HAP (output entry/build/.../*.hap)
./scripts/build.sh release      # Release build (unsigned)
./scripts/build.sh --install    # Build and install to the connected device
./scripts/smoke.sh              # On-device smoke: install→launch→UI check→log check→uninstall
./scripts/unit-test.sh          # Unit tests (device required; or run the Test config in DevEco)
./scripts/gen-changelog.sh      # Generate a per-day CHANGELOG section
```

Toolchain paths can be overridden via environment variables (`DEVECO_HOME` / `DEVECO_SDK_HOME` / `HVIGORW` / `OHPM` / `HDC`); CI must provide them explicitly.

### Testing

- Unit tests (Hypium): `entry/src/test/` — URL validation and connection model serialization
- UI smoke (ohosTest): launch → assert home-screen elements
- On-device smoke: `scripts/smoke.sh` (uitest dumpLayout assertions + hilog error scan)

## Project layout

```
├── AppScope/              App-level config (bundleName: com.dsh.lite)
├── entry/                 Main module
│   └── src/main/ets/
│       ├── entryability/  EntryAbility (lifecycle)
│       ├── pages/         Index (entry) / WebShell (ArkWeb shell) / SettingsPage
│       ├── components/    Connection card, manual URL dialog
│       ├── common/        constants / utils / store
│       └── model/         Data models
├── entry/src/test/        Hypium unit tests
├── entry/src/ohosTest/    UI smoke tests
├── scripts/               Build / test / smoke / changelog helpers
├── .github/workflows/     CI (build + sign + release)
├── .agents/skills/        Local dev skill (coding/review standards; gitignored, private)
└── docs/                  Architecture and other docs
```

## CI (GitHub Actions)

- push / PR: ohpm install → assembleHap (debug), artifact upload
- tag `v*`: release build + signing (repository secrets) → GitHub Release
- Build env: Huawei official "HarmonyOS standalone command-line tools" (SDK bundled), auto-downloaded on ubuntu runners

**First-time CI setup — provide the toolchain URL** (either way):
1. Paste the direct link in the workflow_dispatch input box
2. Set repository variables: `CLT_URL` (direct link), `CLT_SHA256` (optional)

Get the link: sign in to [Huawei Developer download center - Command Line Tools](https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos), pick the version matching the project SDK (7.0.1(25)), copy the direct download URL.

Signing secrets: `SIGNING_KEY` (p12 base64) / `SIGNING_CERT` / `SIGNING_PROFILE` / `KEYSTORE_PASSWORD` / `KEY_PASSWORD` / `KEY_ALIAS`

## Changelog

Changes are recorded per day in [CHANGELOG.md](CHANGELOG.md); commit messages follow Conventional Commits prefixes (feat/fix/perf/docs/test/chore/refactor); use `scripts/gen-changelog.sh` to generate a day's section automatically.

## References

- [dsh-pocket](https://github.com/shaobeichen/dsh-pocket) — the server-side plugin this app pairs with
- [hongshuxifan321/dsh-mobile-app](https://github.com/hongshuxifan321/dsh-mobile-app) — a similar Android shell app (Basic Auth + Keystore storage; useful reference)
- [ohosvscode/harmony-next-pipeline](https://github.com/ohosvscode/harmony-next-pipeline) — CI build approach reference

## License

MIT
