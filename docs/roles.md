# Roles and task types

This document lists the job titles a staff member can have, and the task types a Chief of Staff's hat can show. The lists are kept in `catalog/roles.json` and `catalog/task-types.json`. The app reads them; town-link uses `plugin/hooks/catalog.ts`, which `tools/build-plugin-catalog.py` generates from them. This file is the reference for that data.

## How roles are chosen

- CEO and Chief of Staff are fixed and are not in the catalog.
- For every subagent, Haiku picks one role ID from the catalog (`$.model.classify`). Accuracy is not critical.
- If the subagent's type is exactly a role ID (a custom agent named `golang-engineer`, for example), that role is used without a model call.
- If nothing fits, the role is `generalist`.
- The desk workers who do the main agent's own work (scene 3 in [spec.md](spec.md)) are not classified by Haiku. The role comes from the file being changed, by extension: `.ts`/`.tsx`/`.mts`/`.cts` `typescript-engineer`, `.js`/`.jsx`/`.mjs`/`.cjs` `javascript-engineer`, `.py` `python-engineer`, `.ipynb` `data-scientist`, `.go` `golang-engineer`, `.rs` `rust-engineer`, `.java` `java-engineer`, `.kt`/`.kts` `kotlin-engineer`, `.swift` `swift-engineer`, `.cs` `csharp-engineer`, `.c`/`.cc`/`.cpp`/`.h`/`.hpp` `cpp-engineer`, `.php` `php-engineer`, `.rb` `ruby-engineer`, `.css`/`.scss`/`.html`/`.vue`/`.svelte` `frontend-engineer`, `.sql` `database-engineer`, `.md`/`.mdx`/`.rst` `technical-writer`, `.tf`/`.hcl` and a `Dockerfile` or a file under `.github/workflows/` `devops-engineer`. Otherwise it comes from a file being read (same table), from web research (`research-scientist`), or from the ticket's task type (for example `debugging` → `fullstack-engineer`, `docs` → `technical-writer`), else `generalist`.

## What goes in the catalog

A role belongs in the catalog when the work can be done with a computer: reading, writing, analyzing, coding, drafting, reviewing, researching. A role does not belong when the job needs a body or a license to act in the physical world, for example pilot, driver, nurse, surgeon, chef, electrician, warehouse worker, security guard.

The list is drawn from how large companies in software, banking, legal, consulting, and finance organize their departments (front, middle, and back office in banking; engineering, product, legal, finance, people, operations in tech companies). It is meant to grow. To add a role: add a row here, add it to `catalog/roles.json` with labels for every locale, pick its department color and prop, and run `tools/build-plugin-catalog.py`.

## Role catalog

Each role has an ID (used in the protocol), an English label, and a Traditional Chinese label. The department sets the outfit color, and the bench uses it to pick who answers a page (someone from the same department comes before a neutral character).

### Software engineering 軟體工程

| ID | English | 繁體中文 |
|---|---|---|
| `frontend-engineer` | Front-end Engineer | 前端工程師 |
| `backend-engineer` | Back-end Engineer | 後端工程師 |
| `fullstack-engineer` | Full-stack Engineer | 全端工程師 |
| `typescript-engineer` | TypeScript Engineer | TypeScript 工程師 |
| `javascript-engineer` | JavaScript Engineer | JavaScript 工程師 |
| `python-engineer` | Python Engineer | Python 工程師 |
| `golang-engineer` | Golang Engineer | Golang 工程師 |
| `rust-engineer` | Rust Engineer | Rust 工程師 |
| `java-engineer` | Java Engineer | Java 工程師 |
| `kotlin-engineer` | Kotlin Engineer | Kotlin 工程師 |
| `swift-engineer` | Swift Engineer | Swift 工程師 |
| `csharp-engineer` | C# / .NET Engineer | C# / .NET 工程師 |
| `cpp-engineer` | C / C++ Engineer | C / C++ 工程師 |
| `php-engineer` | PHP Engineer | PHP 工程師 |
| `ruby-engineer` | Ruby Engineer | Ruby 工程師 |
| `ios-engineer` | iOS Engineer | iOS 工程師 |
| `android-engineer` | Android Engineer | Android 工程師 |
| `embedded-engineer` | Embedded / Firmware Engineer | 嵌入式／韌體工程師 |
| `game-developer` | Game Developer | 遊戲開發工程師 |
| `software-architect` | Software Architect | 軟體架構師 |
| `api-engineer` | API Engineer | API 工程師 |
| `database-engineer` | Database Engineer | 資料庫工程師 |
| `code-reviewer` | Code Reviewer | 程式碼審查員 |
| `qa-engineer` | QA Engineer | 品質保證工程師 |
| `test-automation-engineer` | Test Automation Engineer | 自動化測試工程師 |
| `performance-engineer` | Performance Engineer | 效能工程師 |
| `technical-writer` | Technical Writer | 技術文件工程師 |

### Infrastructure and operations 基礎架構與維運

| ID | English | 繁體中文 |
|---|---|---|
| `devops-engineer` | DevOps Engineer | DevOps 工程師 |
| `sre` | Site Reliability Engineer | 網站可靠性工程師 |
| `cloud-engineer` | Cloud Engineer | 雲端工程師 |
| `platform-engineer` | Platform Engineer | 平台工程師 |
| `release-engineer` | Release Engineer | 發佈工程師 |
| `systems-administrator` | Systems Administrator | 系統管理員 |
| `network-engineer` | Network Engineer | 網路工程師 |
| `it-support` | IT Support Specialist | IT 支援專員 |

### Data and AI 資料與 AI

| ID | English | 繁體中文 |
|---|---|---|
| `data-engineer` | Data Engineer | 資料工程師 |
| `data-scientist` | Data Scientist | 資料科學家 |
| `data-analyst` | Data Analyst | 資料分析師 |
| `bi-analyst` | BI Analyst | 商業智慧分析師 |
| `ml-engineer` | Machine Learning Engineer | 機器學習工程師 |
| `ai-engineer` | AI / LLM Engineer | AI／LLM 工程師 |
| `prompt-engineer` | Prompt Engineer | 提示工程師 |
| `statistician` | Statistician | 統計師 |
| `research-scientist` | Research Scientist | 研究科學家 |

### Information security 資訊安全

| ID | English | 繁體中文 |
|---|---|---|
| `security-engineer` | Security Engineer | 資安工程師 |
| `security-analyst` | Security Analyst | 資安分析師 |
| `penetration-tester` | Penetration Tester | 滲透測試員 |
| `privacy-engineer` | Privacy Engineer | 隱私工程師 |

### Product and design 產品與設計

| ID | English | 繁體中文 |
|---|---|---|
| `product-manager` | Product Manager | 產品經理 |
| `project-manager` | Project Manager | 專案經理 |
| `program-manager` | Program Manager | 計畫經理 |
| `ux-designer` | UX Designer | UX 設計師 |
| `ui-designer` | UI Designer | UI 設計師 |
| `ux-researcher` | UX Researcher | 使用者研究員 |
| `ux-writer` | UX Writer | UX 文案 |
| `accessibility-specialist` | Accessibility Specialist | 無障礙設計專員 |
| `graphic-designer` | Graphic Designer | 平面設計師 |

### Legal 法務

| ID | English | 繁體中文 |
|---|---|---|
| `legal-counsel` | Legal Counsel | 法務顧問 |
| `contract-specialist` | Contract Specialist | 合約專員 |
| `ip-specialist` | IP / Patent Specialist | 智慧財產／專利專員 |
| `paralegal` | Paralegal | 法務助理 |
| `legal-researcher` | Legal Researcher | 法律研究員 |
| `litigation-support` | Litigation Support Specialist | 訴訟支援專員 |
| `data-privacy-specialist` | Data Privacy Specialist | 個資保護專員 |
| `regulatory-affairs` | Regulatory Affairs Specialist | 法規事務專員 |

### Risk and compliance 風險與法遵

| ID | English | 繁體中文 |
|---|---|---|
| `compliance-officer` | Compliance Officer | 法遵專員 |
| `aml-kyc-analyst` | AML / KYC Analyst | 洗錢防制／KYC 分析師 |
| `risk-analyst` | Risk Analyst | 風險分析師 |
| `internal-auditor` | Internal Auditor | 內部稽核 |

### Finance and accounting 財務與會計

| ID | English | 繁體中文 |
|---|---|---|
| `accountant` | Accountant | 會計人員 |
| `bookkeeper` | Bookkeeper | 記帳員 |
| `financial-analyst` | Financial Analyst (FP&A) | 財務分析師 |
| `controller` | Financial Controller | 財務主管 |
| `tax-specialist` | Tax Specialist | 稅務專員 |
| `treasury-analyst` | Treasury Analyst | 資金分析師 |
| `payroll-specialist` | Payroll Specialist | 薪資專員 |

### Banking and investment 銀行與投資

| ID | English | 繁體中文 |
|---|---|---|
| `investment-banking-analyst` | Investment Banking Analyst | 投資銀行分析師 |
| `equity-research-analyst` | Equity Research Analyst | 股票研究分析師 |
| `credit-analyst` | Credit Analyst | 授信分析師 |
| `quant-analyst` | Quantitative Analyst | 量化分析師 |
| `portfolio-analyst` | Portfolio Analyst | 投資組合分析師 |
| `underwriter` | Underwriter | 核保員 |
| `actuary` | Actuary | 精算師 |

### Consulting and strategy 顧問與策略

| ID | English | 繁體中文 |
|---|---|---|
| `management-consultant` | Management Consultant | 管理顧問 |
| `strategy-analyst` | Strategy Analyst | 策略分析師 |
| `business-analyst` | Business Analyst | 商業分析師 |
| `market-research-analyst` | Market Research Analyst | 市場研究分析師 |
| `process-analyst` | Process Improvement Analyst | 流程改善分析師 |

### Marketing and communications 行銷與傳播

| ID | English | 繁體中文 |
|---|---|---|
| `marketing-manager` | Marketing Manager | 行銷經理 |
| `copywriter` | Copywriter | 文案 |
| `content-writer` | Content Writer | 內容編輯 |
| `editor` | Editor / Proofreader | 編輯／校對 |
| `translator` | Translator / Localization Specialist | 翻譯／在地化專員 |
| `seo-specialist` | SEO Specialist | SEO 專員 |
| `social-media-manager` | Social Media Manager | 社群經理 |
| `brand-strategist` | Brand Strategist | 品牌策略師 |
| `pr-specialist` | Public Relations Specialist | 公關專員 |
| `growth-marketer` | Growth Marketer | 成長行銷專員 |

### Sales and customers 業務與客戶

| ID | English | 繁體中文 |
|---|---|---|
| `solutions-engineer` | Solutions Engineer | 解決方案工程師 |
| `proposal-writer` | Proposal Writer | 提案撰寫專員 |
| `sales-operations-analyst` | Sales Operations Analyst | 業務營運分析師 |
| `customer-support` | Customer Support Specialist | 客服專員 |
| `customer-success-manager` | Customer Success Manager | 客戶成功經理 |

### People 人資

| ID | English | 繁體中文 |
|---|---|---|
| `recruiter` | Recruiter | 招募專員 |
| `hr-generalist` | HR Generalist | 人資專員 |
| `learning-specialist` | Learning & Development Specialist | 教育訓練專員 |
| `instructional-designer` | Instructional Designer | 教學設計師 |
| `compensation-analyst` | Compensation Analyst | 薪酬分析師 |

### Operations and supply chain 營運與供應鏈

| ID | English | 繁體中文 |
|---|---|---|
| `operations-analyst` | Operations Analyst | 營運分析師 |
| `procurement-specialist` | Procurement Specialist | 採購專員 |
| `supply-chain-analyst` | Supply Chain Analyst | 供應鏈分析師 |
| `logistics-planner` | Logistics Planner | 物流規劃師 |

### Healthcare and life sciences 醫療與生技

Desk work only. No clinical roles.

| ID | English | 繁體中文 |
|---|---|---|
| `medical-writer` | Medical Writer | 醫學寫作專員 |
| `clinical-data-analyst` | Clinical Data Analyst | 臨床資料分析師 |
| `medical-regulatory-specialist` | Medical Device Regulatory Specialist | 醫療器材法規專員 |

### Administration 行政

| ID | English | 繁體中文 |
|---|---|---|
| `executive-assistant` | Executive Assistant | 行政秘書 |
| `office-administrator` | Office Administrator | 行政專員 |

### Fallback

| ID | English | 繁體中文 |
|---|---|---|
| `generalist` | Generalist | 通才專員 |

## Background roles

Operators stand for background tasks, not agents: shell commands running in the background, monitors, and workflow runs. They work in each project block's server room. A background subagent is still a staff member, not an operator.

Roles are chosen by rule where possible (see [architecture.md](architecture.md)), otherwise by Haiku using only the IDs below. Each row lists its rule in `catalog/roles.json`: words in the shell command, or, for `log-monitor` and `workflow-coordinator`, the tool that starts the task (`Monitor`, `Workflow`).

### Background operations 背景作業

| ID | English | 繁體中文 | Covers | Prop and looping animation |
|---|---|---|---|---|
| `build-operator` | Build Operator | 建置作業員 | Compiles, bundles, image builds | Hard hat; watching a progress bar on a console |
| `test-runner` | Test Runner | 測試執行員 | Long test suites | Stopwatch; ticking off a checklist |
| `server-operator` | Server Operator | 伺服器值班員 | Dev servers, watchers, long-running processes | Headset; keeping watch at a server rack, with a lamp on while the server runs |
| `log-monitor` | Log Monitor | 監控員 | `Monitor` tool, tailing logs, polling | Binoculars; watching a wall of screens |
| `install-operator` | Installer | 安裝作業員 | Package installs, downloads | Box cart; unpacking boxes |
| `batch-operator` | Batch Job Operator | 批次作業員 | Scripts, data jobs, migrations | Stack of punch cards; feeding a machine |
| `deploy-operator` | Deployment Operator | 部署作業員 | Deploys, releases, publishing | Clipboard; pulling a lever, then watching a launch light |
| `workflow-coordinator` | Workflow Coordinator | 流程協調員 | `Workflow` runs that orchestrate several agents | Conductor's baton; directing at a whiteboard |
| `background-worker` | Background Worker | 背景作業員 | Fallback | Laptop; typing |

Operators share one outfit color, safety orange. The prop tells the roles apart. The subagents of a workflow run appear as staff, and they report to the workflow coordinator instead of the Chief of Staff (Phase 0 item 16).

## Fixed characters

These are not in the catalog and are not classified.

| Character | English | 繁體中文 | Where |
|---|---|---|---|
| CEO | CEO | 執行長 | CEO's desk with a telephone, executive block (the user can walk the CEO around) |
| Chief of Staff | Chief of Staff | 幕僚長 | A desk with a telephone in the project block |
| Dispatcher | Dispatcher | 調度員 | Dispatcher's desk with a radio and the board, executive block |
| Inspector | Inspector | 稽核員 | Reception desk, executive block |

## Character looks

Characters are Kenney Mini Characters (CC0, 3D). A character's look is a combination of parts:

| Part | Source |
|---|---|
| Base character | One of the 12 Kenney characters (`male-a` … `female-f`), picked at random for staff and operators from the nine not used by the CEO, the Dispatcher and the Inspector |
| Outfit color | The department color, applied to the base character's shirt swatch (see [architecture.md](architecture.md)) |
| Prop | A small model in the hand: from Kenney Furniture Kit where one exists (`laptop`, `books`, `cardboardBoxClosed`), otherwise a simple shape (clipboard, calculator, stopwatch) |
| Name tag | The localized role label, drawn as a 2D overlay |
| Model badge | Model family name, shown when the setting is on (see [spec.md](spec.md)) |

Each role in `catalog/roles.json` names its department (outfit color) and its prop. Operators share one color, safety orange, and their prop tells them apart. A neutral character on the bench wears light gray.

Fixed characters use set base characters so they are easy to spot:

| Character | Base character | Look |
|---|---|---|
| CEO | `male-d` | Black suit, red tie |
| Chief of Staff | Any base character except `male-d`, `male-c`, `female-e` | Charcoal gray outfit and a clipboard. Several Chiefs of Staff in one block have different base characters. |
| Dispatcher | `female-e` | White, with a headset |
| Inspector | `male-c` | Uniform with a cap, and a stamp |

### Animations

The Kenney characters come with these clips, which the scenes use:

| Scene action | Clip |
|---|---|
| Walking | `walk` |
| Idle on the bench | `sit` on the sofa, `idle` standing; now and then `emote-yes` (chatting) or `interact-left` |
| Typing at a desk | Part of `interact-right` and `interact-left`, switching hands |
| Writing (a hot desk with no computer, or tidying notes) | A slow part of `interact-right` |
| Working at the racks (operators) | `interact-right` / `interact-left` |
| On the phone, or waiting for approval | `holding-right` |
| Handing over a report | `interact-right`; the receiver plays `pick-up` |
| Picking up or setting down a carried desk, picking a ticket from the inbox | `pick-up` |
| CEO when the approval waits are over | `emote-yes` |

## Task types (Chief of Staff hats)

The hat label has to be short. Keep English labels to about 8 characters and Chinese labels to 2 to 4 characters.

| ID | English (hat) | 繁體中文 (hat) | Covers |
|---|---|---|---|
| `coding` | Coding | 寫程式 | New features, new code |
| `debugging` | Debug | 除錯 | Fixing bugs and errors |
| `refactoring` | Refactor | 重構 | Restructuring existing code |
| `testing` | Testing | 測試 | Writing or running tests |
| `code-review` | Review | 審查 | Reviewing code or a PR |
| `devops` | DevOps | 部署 | Builds, CI, deploys, infrastructure |
| `security` | Security | 資安 | Security review, vulnerability fixes |
| `data` | Data | 資料 | Data analysis, queries, charts |
| `research` | Research | 研究 | Looking things up, comparing options |
| `writing` | Writing | 撰寫 | Documents, emails, reports |
| `docs` | Docs | 文件 | Code documentation, READMEs |
| `translation` | Translate | 翻譯 | Translation and localization |
| `design` | Design | 設計 | UI, visuals, mockups |
| `planning` | Planning | 規劃 | Plans, specs, task breakdowns |
| `slides` | Slides | 簡報 | Presentations |
| `spreadsheet` | Sheets | 試算表 | Spreadsheets, financial models |
| `legal` | Legal | 法務 | Contracts, policies, legal questions |
| `finance` | Finance | 財務 | Accounting, budgets, financial analysis |
| `marketing` | Marketing | 行銷 | Marketing copy, campaigns |
| `question` | Q&A | 問答 | Answering a question |
| `general` | Working | 處理中 | Fallback |
