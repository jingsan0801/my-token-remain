<div align="center">

# TokenRemain

**AI 编码工具的剩余额度，常驻 Mac 菜单栏。**<br/>
凭证只留在本机：只读、不刷新、不上传。

<p>
  <img alt="macOS 14+ · Universal" src="https://img.shields.io/badge/macOS_14%2B-Universal-000?logo=apple&logoColor=white" />
  <a href="LICENSE"><img alt="Apache-2.0 许可" src="https://img.shields.io/badge/license-Apache--2.0-8A94A6" /></a>
</p>

<a href="CHANGELOG.md">更新记录</a> ·
<a href="README.en.md">English</a>

</div>

<br/>

<p align="center"><sub>Claude Code、Codex、Cursor、Grok、GLM 等 21+ 家工具的剩余额度与重置倒计时，一屏看完。</sub></p>

> [!NOTE]
> 这是个人自用 fork(MyTokenRemain):移除了自动更新(Sparkle)、作者服务器链路、Token 用量/成本统计、趋势页以及 iPhone/Apple Watch 跨设备同步,只保留 macOS 额度监控;另新增了可选的 WebDAV 配置同步。差异明细见[更新记录](CHANGELOG.md)。

## 功能

### 🧭 额度：撑不撑得到重置，一眼就知道

- **21+ 家工具并排展示**：每个官方额度窗口都带进度条、重置倒计时和更新时间。
- **多账号**：同一工具的多个账号分行显示；「账号管理」页可按应用开关监控、启停账号、重命名、更新凭证，同套餐账号可选合并查看。
- **随处可见**：菜单栏胶囊、跨空间浮窗、Dock 图标双仪表（两款应用自选），macOS 26 上使用 Liquid Glass。

### 🔐 隐私：凭证从不离开你的 Mac

- **只读本机已有凭证**：无需注册账号，无遥测，不刷新第三方 token，不上传凭证。
- **可选 WebDAV 配置同步**(fork 自有):把账号配置与密钥以明文 JSON 写到你自己的 WebDAV 服务器(如坚果云),方便多 Mac 复制配置;默认关闭。
- **低能耗**：后台 CPU 比 v1.2.2 降低 95%（[测试方法](docs/performance-v1.2.3.md)）；界面支持简体中文、繁體中文、English、日本語、한국어 等多种语言。


## 快速上手

1. **安装**：本 fork 不发布 DMG，从源码构建（见 [CONTRIBUTING.md](CONTRIBUTING.md)）：`USAGEDOCK_INSTALL_DIR="$HOME/Applications" bash ./script/build_and_run.sh`。
2. **选择工具**：欢迎页会扫描本机已安装的 AI 工具，勾选要追踪的即可。凭证沿用各工具自己的登录，无需在 TokenRemain 里再登录；Codex 可沿用官方桌面 App 的登录。
3. **补充密钥**：Z.ai、OpenRouter 等需要 API Key 的服务，直接在对应额度卡里粘贴，或在「数据来源」页的「API Key 设置」中填写。密钥只存本机钥匙串。
4. **按需调整**：在「设置 › 刷新与同步」调整额度刷新频率（1–30 分钟或仅手动）；在「设置 › 通用」选择 Dock 图标显示的两款应用；在「账号管理」页管理多账号。

> [!NOTE]
> Claude 额度需要可读取的 Claude Code 登录，或在「数据来源」中手动配置 claude.ai 会话（见[常见问题](#常见问题)）；仅登录 Claude 桌面 App 不保证能续期 Code 凭证。

## 支持接入的应用

🟢 **自动** = 登录对应工具即接入 · 🔑 **API Key** = 粘贴一次密钥，仅存 macOS 钥匙串

| 应用 | 接入 | 读取内容 |
| :-- | :-: | :-- |
| <img src="site/assets/providers/claude-code.svg" width="16" alt="" /> **Claude Code** | 🟢 | 5 小时 / 7 天窗口；第三方 `ANTHROPIC_BASE_URL` 标注实际 API |
| <img src="site/assets/providers/codex.svg" width="16" alt="" /> **Codex** | 🟢 | 5 小时 / 7 天窗口、重置卡；自定义 `base_url` 标注实际 API |
| <img src="site/assets/providers/cursor.svg" width="16" alt="" /> **Cursor** | 🟢 | 月度账期额度，Cursor 模型与其他模型分池显示 |
| <img src="site/assets/providers/grok.svg" width="16" alt="" /> **Grok**（xAI） | 🟢 | 周池剩余额度 |
| <img src="site/assets/providers/copilot.svg" width="16" alt="" /> **GitHub Copilot** | 🟢 | 月度 Credits |
| <img src="site/assets/providers/devin.svg" width="16" alt="" /> **Devin** | 🟢 | 日 / 周配额 |
| <img src="site/assets/providers/windsurf.png" width="16" alt="" /> **Windsurf** | 🟢 | 日 / 周配额 |
| <img src="site/assets/providers/antigravity.svg" width="16" alt="" /> **Antigravity** | 🟢 | 配额池 |
| <img src="site/assets/providers/opencode.svg" width="16" alt="" /> **OpenCode** | 🟢 | 套餐本地估算；第三方 provider 标注实际 API |
| <img src="site/assets/providers/zai.svg" width="16" alt="" /> **Z.ai / 智谱** | 🔑 | Coding Plan 额度；macOS 国内站另支持普通 API Key 的人民币余额（中国 → API 余额） |
| <img src="site/assets/providers/openrouter.svg" width="16" alt="" /> **OpenRouter** | 🔑 | Key 限额、Credits 与账户余额 |

<details>
<summary><b>另外 11 家扩展 Provider</b></summary>
<br/>

| 应用 | 接入方式 | | 应用 | 接入方式 |
| :-- | :-- | :-- | :-- | :-- |
| <img src="site/assets/providers/deepseek.svg" width="16" alt="" /> **DeepSeek** | API Key | | <img src="site/assets/providers/qoder.svg" width="16" alt="" /> **Qoder** | Cookie |
| <img src="site/assets/providers/kimi.svg" width="16" alt="" /> **Kimi** | API Key / Cookie | | <img src="site/assets/providers/kiro.svg" width="16" alt="" /> **Kiro** | `kiro-cli /usage` 解析 |
| <img src="site/assets/providers/minimax.svg" width="16" alt="" /> **MiniMax** | API Key | | <img src="site/assets/providers/volcengine.svg" width="16" alt="" /> **火山引擎** | AK:SK 签名 |
| <img src="site/assets/providers/mimo.svg" width="16" alt="" /> **MiMo Code** | Cookie | | <img src="site/assets/providers/ollama.svg" width="16" alt="" /> **Ollama** | session Cookie |
| <img src="site/assets/providers/zai.svg" width="16" alt="" /> **GLM Team** | API Key + Org + Project | | **第三方 API** | New API / 自定义余额接口 |
| <img src="Sources/UsageDock/Resources/ProviderIcons/bailian.svg" width="16" alt="" /> **阿里云百炼 Token Plan** | 控制台 Cookie | | | |

**Cookie 型服务怎么接入**：在浏览器登录对应网站后，从开发者工具复制请求里的 Cookie，粘贴到该服务的额度卡即可（也可用 `QODER_COOKIE`、`MIMO_COOKIE`、`OLLAMA_COOKIE` 环境变量提供）。Cookie 与 API Key 一样只存本机钥匙串；TokenRemain 从不读取浏览器自身的 Cookie 存储。Cookie 等同于登录凭证，请勿分享；退出网站登录后它会失效，需要重新粘贴。

</details>

## 隐私

```
你机器上已有的凭证 ──只读──▶ 各服务商官方 API ──▶ 本地渲染并缓存
```

每一条都附有可核对的源码或测试：

- **只读凭证，绝不刷新**：只读各工具自己维护的 token，从不写回、不争用 refresh token；后台读取关闭钥匙串交互，不会弹出授权窗。 <sub>🔍 [契约脚本](script/verify_keychain_read_contract.sh) · [测试](Tests/UsageDockTests/KeychainReadTests.swift#L45) · [源码](Sources/UsageDock/Services/ClaudeOAuthUsageService.swift#L9)</sub>
- **手动密钥只进本机钥匙串**：粘贴的 API Key 存入 macOS 钥匙串，且禁止同步到 iCloud 钥匙串。 <sub>🔍 [源码](Sources/UsageDock/Services/KeychainSecretStore.swift#L176) · [测试](Tests/UsageDockTests/AppOwnedKeychainTests.swift#L15)</sub>
- **无账号、无遥测、无凭证中转**：额度查询直连各服务商官方 API；依赖只有 Sparkle 之外的标准库与本仓库代码，没有任何分析 SDK。 <sub>🔍 [依赖清单](Package.swift)</sub>

**其他联网行为**（均不携带凭证）：服务状态读取 `status.openai.com`、`status.claude.com` 的公开接口；开启 WebDAV 同步时只连接你自己配置的服务器。

细节见[隐私政策](https://mytokenremain.jingsan.wang/privacy.html)。

## 常见问题

<details>
<summary><b>卡片提示「未检测到登录」</b></summary>
<br/>

TokenRemain 从不刷新 token，只读取工具自己保存的登录状态。到对应工具里重新登录并正常使用一次，数据会自动恢复；Antigravity 等工具需要先打开使用一次，凭证才会写到本机。

</details>

<details>
<summary><b>没有安装 Claude Code CLI，怎么看 Claude 额度？</b></summary>
<br/>

在「数据来源」的 Claude 行粘贴你自己的 claude.ai `sessionKey` 或 Cookie。验证成功后只保存在本机钥匙串、不参与 iCloud 钥匙串同步；TokenRemain 不会导入浏览器 Cookie，也不会刷新第三方凭证。配置后默认 Claude 额度明确来自该网页账号，独立 CLI 账号仍使用各自凭证；移除 Cookie 即恢复本地 OAuth。多个组织无法唯一匹配时需要填写目标组织 UUID。

该网页接口不是公开接口，访问质询、会话过期或网络失败都可能导致暂时无法读取，此时卡片保留上一次的额度和原更新时间。

</details>

<details>
<summary><b>Claude 显示「用量读取超时」或「无法连接 Claude 服务」</b></summary>
<br/>

此时卡片显示的是最近一次成功的缓存，网络恢复后自动重试，不会要求你重新登录。官方 API 走系统代理；凭证过期需要借助 Claude Code CLI 续期时，TokenRemain 会依次尝试 App 环境变量、Claude Code `settings.json` 的 `env`、系统代理（含 PAC）和登录 shell 导出的代理变量，选第一条能连通 `api.anthropic.com` 的。仍无法恢复时，可在终端运行一次 `claude` 并执行 `/usage`。

</details>


<details>
<summary><b>顶部预警和卡片上的百分比不一致</b></summary>
<br/>

预警取所有窗口中最紧缺的一个（通常是 7 天窗口），卡片头行显示的是 5 小时窗口，两者不是同一个窗口。

</details>



<details>
<summary><b>卡片标注了「第三方 API」</b></summary>
<br/>

Claude Code 设置了 `ANTHROPIC_BASE_URL`，或 Codex 配置了自定义 `base_url` 时，额度来自实际提供服务的 API，卡片会注明来源。如果你用的是官方登录却被这样标注，请[提交 issue](https://github.com/jingsan0801/my-token-remain/issues) 并附上脱敏后的配置。

</details>

<details>
<summary><b>如何彻底卸载</b></summary>
<br/>

退出 TokenRemain 并删除 App 后，可清理本地偏好与缓存：

```bash
defaults delete com.jamesli.usagedock
rm -rf ~/Library/Caches/com.jamesli.usagedock ~/Library/Application\ Support/com.jamesli.usagedock
```

手动粘贴的密钥可在「钥匙串访问」中搜索 `com.jamesli.usagedock` 删除。

</details>

还有问题？请[提交 issue](https://github.com/jingsan0801/my-token-remain/issues) 或查看[支持页](https://mytokenremain.jingsan.wang/support.html)。

## 参与开发

欢迎提交 issue 与 PR。构建、测试、目录结构与代码约定见 [CONTRIBUTING.md](CONTRIBUTING.md)；安全问题请按 [SECURITY.md](SECURITY.md) 私下报告，不要公开提交 issue。

## 致谢

- [token-monitor](https://github.com/Javis603/token-monitor)（MIT）：扩展 Provider 的额度读取逻辑移植自此项目，桌面浮窗与偏好设计也受其启发。
- [OpenUsage](https://github.com/robinebers/openusage)（MIT）：Claude 限额 API 直查的 provider 设计参考。

第三方版权与许可声明见 [NOTICE](NOTICE)。

## 许可

源代码与源文档采用 [Apache License 2.0](LICENSE)；TokenRemain 名称、Logo、图标、机器人形象与原创设计素材不在授权范围内，详见[品牌与素材许可说明](ASSET-LICENSE.md)。

<sub>TokenRemain 是独立应用，与 Anthropic、OpenAI、Anysphere、xAI、GitHub、智谱 AI 或任何服务商均无隶属、背书或赞助关系；服务名称与标识仅用于标示你可选择接入的服务。发布者与支持联系人：Dongheng Li · jamescarstin520@gmail.com · © 2026</sub>
