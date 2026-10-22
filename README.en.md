<div align="center">

<a href="https://tokenremain.com"><img src="site/assets/mascot.gif" width="112" alt="TokenRemain mascot animation: remaining quota draining from 100% to 0%, expression changing along the way" /></a>

# TokenRemain

**Your AI coding quota, always in the Mac menu bar.**<br/>
Credentials never leave your machine: read-only, never refreshed, never uploaded.

<p>
  <img alt="macOS 14+ · Universal" src="https://img.shields.io/badge/macOS_14%2B-Universal-000?logo=apple&logoColor=white" />
  <a href="LICENSE"><img alt="Apache-2.0 license" src="https://img.shields.io/badge/license-Apache--2.0-8A94A6" /></a>
</p>

<a href="CHANGELOG.md">Changelog</a> ·
<a href="README.md">简体中文</a>

</div>

<br/>

<p align="center">
  <img src="site/assets/dash-overview.webp" width="77%" alt="Dashboard overview: lowest remaining quota, official quota progress and risk notes" />
  <img src="site/assets/popover.webp" width="19%" alt="Menu bar popover listing remaining quota per app" />
</p>
<p align="center"><sub>Remaining quota and reset countdowns for Claude Code, Codex, Cursor, Grok, GLM and 21+ tools — on one screen.</sub></p>

> [!NOTE]
> This is a personal fork (MyTokenRemain): automatic updates (Sparkle), the author's server pipeline, token-usage/cost statistics and the Trends page are removed — quota monitoring only — with an optional self-hosted WebDAV config sync added. See the [changelog](CHANGELOG.md) for the delta.

## Features

### 🧭 Quota — know whether you'll make it to reset

- **21+ tools side by side**: every official quota window with a progress bar, reset countdown and freshness.
- **Multiple accounts**: each account of the same tool gets its own row; the Account Management page toggles monitoring per app, enables or pauses accounts, renames them and updates credentials, with an opt-in combined view for same-plan accounts.
- **Wherever you look**: menu bar capsules, a floating window across Spaces, two meters on the Dock icon (you pick the apps), and Liquid Glass on macOS 26.

### 🔐 Privacy — credentials never leave your Mac

- **Reads what's already there**: no account to create, no telemetry, never refreshes third-party tokens, never uploads credentials.
- **Optional encrypted sync**: off by default; when on, only an allowlisted snapshot is encrypted into your own iCloud for iPhone, Apple Watch and Home Screen widgets.
- **Optional WebDAV config sync** (fork-only): writes account configuration and keys as plaintext JSON to your own WebDAV server to copy settings between Macs; off by default.
- **Light on energy**: background CPU down 95% vs v1.2.2 ([method](docs/performance-v1.2.3.md)); interface in English, 简体中文, 繁體中文, 日本語, 한국어 and more.

## Screenshots

<p align="center">
  <img src="site/assets/dash-limits.webp" width="80%" alt="Limits page: official windows per provider with reset countdowns" />
</p>
<p align="center"><sub><b>Limits</b> · remaining quota, reset time and freshness for every window.</sub></p>

<details>
<summary><b>More screenshots</b>: iPhone, Apple Watch and widgets</summary>
<br/>

<p align="center">
  <img src="site/assets/phone-overview.jpg" width="24%" alt="iPhone overview page, aggregating up to 16 Macs" />
  <img src="site/assets/watch-overview.png" width="16%" alt="Apple Watch overview" />
</p>
<p align="center">
  <img src="site/assets/widget-s.png" width="30%" alt="Small iPhone Home Screen widget" />
  <img src="site/assets/widget-m.png" width="60%" alt="Medium iPhone Home Screen widget" />
</p>

The iPhone app is in [public TestFlight beta](https://testflight.apple.com/join/DU3DrnhG). Data is published one-way and encrypted by the Mac; the mobile client source is outside this repository's open-source scope.

</details>

## Quick start

1. **Install**: this fork ships no DMG — build from source (see [CONTRIBUTING.md](CONTRIBUTING.md)): `USAGEDOCK_INSTALL_DIR="$HOME/Applications" bash ./script/build_and_run.sh`.
2. **Pick your tools**: the welcome screen scans your Mac for installed AI tools — tick the ones to track. TokenRemain reuses each tool's own sign-in, so there's nothing to log into; Codex can reuse the official desktop app's sign-in.
3. **Add keys if needed**: for services that need an API key (Z.ai, OpenRouter, …), paste it straight into that service's quota card, or under "API key settings" on the Data Sources page. Keys stay in your Mac's Keychain.
4. **Tune it**: set the quota refresh interval (1–30 minutes or manual) in Settings › Refresh & Sync; choose the Dock icon's two apps in Settings › General; manage multiple accounts on the Account Management page.

> [!NOTE]
> Claude quota needs a readable Claude Code sign-in, or a claude.ai session configured on the Data Sources page (see the [FAQ](#faq)); signing in to the Claude desktop app alone doesn't guarantee the Code credential stays renewed.

## Supported services

🟢 **Auto** = connected as soon as the tool is signed in · 🔑 **API key** = paste once, stored only in the macOS Keychain

| Service | Connect | What it reads |
| :-- | :-: | :-- |
| <img src="site/assets/providers/claude-code.svg" width="16" alt="" /> **Claude Code** | 🟢 | 5-hour / 7-day windows; third-party `ANTHROPIC_BASE_URL` attributed to its real API |
| <img src="site/assets/providers/codex.svg" width="16" alt="" /> **Codex** | 🟢 | 5-hour / 7-day windows and reset cards; custom `base_url` attributed to its real API |
| <img src="site/assets/providers/cursor.svg" width="16" alt="" /> **Cursor** | 🟢 | Monthly billing-cycle quota, with Cursor and other models as separate pools |
| <img src="site/assets/providers/grok.svg" width="16" alt="" /> **Grok** (xAI) | 🟢 | Weekly pool remaining |
| <img src="site/assets/providers/copilot.svg" width="16" alt="" /> **GitHub Copilot** | 🟢 | Monthly credits |
| <img src="site/assets/providers/devin.svg" width="16" alt="" /> **Devin** | 🟢 | Daily / weekly quotas |
| <img src="site/assets/providers/windsurf.png" width="16" alt="" /> **Windsurf** | 🟢 | Daily / weekly quotas |
| <img src="site/assets/providers/antigravity.svg" width="16" alt="" /> **Antigravity** | 🟢 | Quota pools |
| <img src="site/assets/providers/opencode.svg" width="16" alt="" /> **OpenCode** | 🟢 | Local plan estimate; third-party providers attributed to their real API |
| <img src="site/assets/providers/zai.svg" width="16" alt="" /> **Z.ai / BigModel** | 🔑 | Coding Plan quotas; prepaid CNY API balance on macOS (China → API Balance) |
| <img src="site/assets/providers/openrouter.svg" width="16" alt="" /> **OpenRouter** | 🔑 | Key limits, credits and account balance |

<details>
<summary><b>11 more extended providers</b></summary>
<br/>

| Service | Connection | | Service | Connection |
| :-- | :-- | :-- | :-- | :-- |
| <img src="site/assets/providers/deepseek.svg" width="16" alt="" /> **DeepSeek** | API key | | <img src="site/assets/providers/qoder.svg" width="16" alt="" /> **Qoder** | Cookie |
| <img src="site/assets/providers/kimi.svg" width="16" alt="" /> **Kimi** | API key / cookie | | <img src="site/assets/providers/kiro.svg" width="16" alt="" /> **Kiro** | `kiro-cli /usage` parsing |
| <img src="site/assets/providers/minimax.svg" width="16" alt="" /> **MiniMax** | API key | | <img src="site/assets/providers/volcengine.svg" width="16" alt="" /> **Volcengine** | AK:SK signing |
| <img src="site/assets/providers/mimo.svg" width="16" alt="" /> **MiMo Code** | Cookie | | <img src="site/assets/providers/ollama.svg" width="16" alt="" /> **Ollama** | Session cookie |
| <img src="site/assets/providers/zai.svg" width="16" alt="" /> **GLM Team** | API key + org + project | | **Third-party APIs** | New API / custom balance endpoint |
| <img src="Sources/UsageDock/Resources/ProviderIcons/bailian.svg" width="16" alt="" /> **Alibaba Token Plan** | Console cookie | | | |

**How cookie-based services connect:** sign in to the service's website, copy the request Cookie from your browser's developer tools and paste it into that service's quota card (or provide it via `QODER_COOKIE`, `MIMO_COOKIE` or `OLLAMA_COOKIE`). Cookies are stored only in your Mac's Keychain, like API keys; TokenRemain never reads your browser's own cookie store. A cookie is a sign-in credential — never share it; signing out of the website invalidates it, so paste a fresh one afterwards.

</details>

## Privacy

```
Credentials already on your machine ──read-only──▶ Official provider APIs ──▶ Rendered & cached locally
```

Every claim links to the code or test that backs it:

- **Read-only credentials, never refreshed** — Reads the tokens your tools already maintain, never writes back, never competes for refresh tokens; background reads disable Keychain UI, so no system prompt appears. <sub>🔍 [contract script](script/verify_keychain_read_contract.sh) · [tests](Tests/UsageDockTests/KeychainReadTests.swift#L45) · [source](Sources/UsageDock/Services/ClaudeOAuthUsageService.swift#L9)</sub>
- **Pasted keys stay in the local Keychain** — API keys go into the macOS Keychain and are barred from syncing to iCloud Keychain. <sub>🔍 [source](Sources/UsageDock/Services/KeychainSecretStore.swift#L176) · [tests](Tests/UsageDockTests/AppOwnedKeychainTests.swift#L15)</sub>
- **No account, no telemetry, no credential relay** — Quota queries go straight to each provider's official API; the only dependency is this repo's sync package, with no analytics SDK. <sub>🔍 [dependencies](Package.swift)</sub>
- **Sync is off by default and end-to-end encrypted** — When enabled, only an allowlisted display snapshot is AES-GCM encrypted on your Mac, then written to your own private iCloud database. <sub>🔍 [off-by-default test](Tests/UsageDockTests/CrossDeviceSyncDefaultsTests.swift#L8) · [field allowlist](Sources/UsageDock/Sync/MobileSnapshotRedactor.swift#L7) · [encryption](Packages/TokenRemainSyncKit/Sources/TokenRemainSyncKit/EncryptedSyncEnvelope.swift#L66)</sub>

**Other network activity** (never carries credentials): service status reads the public endpoints of `status.openai.com` and `status.claude.com`; WebDAV sync, when enabled, contacts only the server you configure; direct LAN sync listens on TCP 47831 and accepts only paired devices.

Details in the [privacy policy](https://tokenremain.com/privacy).

## FAQ

<details>
<summary><b>A card says "Login not detected"</b></summary>
<br/>

TokenRemain never refreshes tokens; it only reads the sign-in state each tool saves. Sign in again in that tool and use it once, and the data comes back automatically. Some tools, such as Antigravity, need to be opened and used once before their credentials are written to disk.

</details>

<details>
<summary><b>How do I see Claude quota without the Claude Code CLI?</b></summary>
<br/>

Paste your own claude.ai `sessionKey` or Cookie into the Claude row on the Data Sources page. Once verified it's stored only in your Mac's Keychain and excluded from iCloud Keychain sync; TokenRemain never imports browser cookies or refreshes third-party credentials. The default Claude quota then comes explicitly from that web account, while separate CLI accounts keep their own credentials; removing the cookie returns to local OAuth. If several organizations can't be matched uniquely, enter the target organization UUID.

The web endpoint isn't a public API: an access challenge, an expired session or a network failure can make it temporarily unreadable, in which case the card keeps the last quota with its original timestamp.

</details>

<details>
<summary><b>Claude shows "usage read timed out" or "Claude is unreachable"</b></summary>
<br/>

The card is showing the last good cached snapshot; TokenRemain retries once the network is back and never asks you to sign in over a network failure. The official API follows the system proxy. When an expired credential has to be renewed through the Claude Code CLI, TokenRemain tries, in order: the app's environment variables, the `env` block of Claude Code's `settings.json`, the system proxy (including PAC) and proxy variables exported by your login shell — and uses the first one that reaches `api.anthropic.com`. If it still doesn't recover, run `claude` in a terminal and execute `/usage` once.

</details>


<details>
<summary><b>The top alert and the card show different percentages</b></summary>
<br/>

The alert reflects the tightest of all windows (usually the 7-day one), while the card header shows the 5-hour window — they're not the same window.

</details>



<details>
<summary><b>A card is labeled "third-party API"</b></summary>
<br/>

When Claude Code has `ANTHROPIC_BASE_URL` set, or Codex has a custom `base_url`, the quota comes from the API actually serving you, and the card names it. If you use the official sign-in and still see this label, please [open an issue](https://github.com/Carstin520/token-remain/issues) with your redacted configuration.

</details>

<details>
<summary><b>How do I uninstall completely?</b></summary>
<br/>

Quit TokenRemain and delete the app, then remove local preferences and caches:

```bash
defaults delete com.jamesli.usagedock
rm -rf ~/Library/Caches/com.jamesli.usagedock ~/Library/Application\ Support/com.jamesli.usagedock
```

Pasted keys can be removed in Keychain Access by searching for `com.jamesli.usagedock`. If you enabled sync and want the iCloud data cleared, [contact support](https://tokenremain.com/support).

</details>

Still stuck? [Open an issue](https://github.com/Carstin520/token-remain/issues) or visit the [support page](https://tokenremain.com/support).

## Contributing

Issues and pull requests are welcome. Build steps, tests, repository layout and conventions are in [CONTRIBUTING.md](CONTRIBUTING.md); please report security issues privately as described in [SECURITY.md](SECURITY.md), not in a public issue.

## Acknowledgments

- [token-monitor](https://github.com/Javis603/token-monitor) (MIT) — the extended providers' quota readers are ported from this project, which also inspired the floating window and preferences.
- [OpenUsage](https://github.com/robinebers/openusage) (MIT) — reference for the direct Claude quota API provider design.

Third-party copyright and license notices are in [NOTICE](NOTICE).

## License

Source code and source documentation are available under the [Apache License 2.0](LICENSE); the TokenRemain name, logos, icons, robot character and original design assets are not included — see the [brand and asset licensing terms](ASSET-LICENSE.md).

<sub>TokenRemain is an independent app, not affiliated with, endorsed by, or sponsored by Anthropic, OpenAI, Anysphere, xAI, GitHub, Zhipu AI, or any other provider; service names and marks appear only to identify the services you can choose to connect. Publisher and support contact: Dongheng Li · jamescarstin520@gmail.com · © 2026</sub>
