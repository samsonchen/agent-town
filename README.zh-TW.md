# Agent-Town for Claude Code

看 Claude Code 的 agent 怎麼工作：一個 Claude Code plugin 加上一個 macOS 選單列 app（現在也有 Windows 版），把你的 session、subagent、背景工作和待核准的操作畫成一間小小的 3D 辦公室。（與其他名為 agent-town 的專案無關。）

[網站（英文）](https://samsonchen.github.io/agent-town-claude-code/) · [English](README.md)

agent-town 在 macOS 和 Windows 上把 Claude Code 的工作畫成一間小辦公室，從上往下看，裡面是 3D 角色。俯視的畫面受到 Gather Town 的啟發。你是執行長。每個 Claude Code session 是一位幕僚長，各自帶著自己的職員。你可以看著他們接你的工單、找職員來做事、在背景跑工作、等你核准，最後打電話回報。

## 1. agent-town 是什麼

### 為什麼做這個

在 Claude Code 裡，有些工作要做很久。你輸入 prompt，Claude Code 開始讀檔案、跑指令、叫出 subagent，然後你就等。我想知道兩件事：

- Claude Code 現在在做什麼？
- 做完了沒？

一開始的想法很小：長時間的工作做完時，放一個聲音。這解決了「做完了沒」。

做聲音的時候，我發現 Claude Code 其實一直在說它在做什麼：呼叫哪個工具、開了哪個 subagent、哪個背景工作在跑、什麼時候在等核准、什麼時候在整理筆記。聲音只用到最後一件事。既然每件事都能被聽到，也就能被看到，所以聲音後來變成了一間辦公室。

### 由什麼組成

- **town-link**：一個 Claude Code plugin。它觀察 Claude Code 在做什麼，透過本機連線把簡短的事件訊息傳給你電腦上的 app。它不會改變 Claude Code 的任何行為。
- **agent-town app**：在 macOS 上是選單列 app，用 RealityKit 畫出辦公室，並播放聲音；在 Windows 上是用 Godot 做的系統匣 app，畫出同樣的辦公室。

除了每個工作幾個簡短的請求，沒有任何資料離開你的電腦：town-link 用你自己的 Claude 方案或 API key 請 Haiku 為工作取一個標題、判斷工作類型，並為職員選職稱。詳見 [town-link 讀取和傳送什麼](docs/privacy.md)（英文）。

### 它不是什麼

- 它不是衡量生產力的儀表板。它顯示正在發生什麼，不評斷做得好不好。
- 它不控制 Claude Code。你一樣在終端機或 Claude 桌面 app 裡工作，agent-town 只負責看。
- 它還沒做完。請看[已知問題](docs/known-issues.md)和 [roadmap](docs/roadmap.md)（英文）。

![agent-town 運作中：執行長辦公室裡有執行長、稽核員和調度員；下方的專案區塊有兩位幕僚長、職員的桌子、機房和休息區](docs/images/agent-town.gif)

## 2. 安裝

兩個部分都要裝：Claude Code 裡的 plugin，和 Mac 或 Windows 電腦上的 app。

### town-link plugin

town-link 是用 Claude Code 的 mod（帶 hooks 模組的 plugin）做的，所以需要能執行 mod 的 Claude Code 版本：v2.1.287 以上。在 Claude Code session 裡輸入：

```
/plugin marketplace add samsonchen/agent-town-claude-code
```

```
/plugin install town-link@agent-town-claude-code
```

或在終端機執行：

```bash
claude plugin marketplace add samsonchen/agent-town-claude-code
```

```bash
claude plugin install town-link@agent-town-claude-code
```

裝完後重新啟動 Claude Code。在 session 裡，`/town` 會顯示已安裝的 town-link 版本，以及 plugin 有沒有連上 app，`/town on` 或 `/town off` 可以替所有 session 開啟或關閉傳送。

這個 marketplace 不會自動更新。更新方式：

```bash
claude plugin marketplace update agent-town-claude-code
```

```bash
claude plugin update town-link@agent-town-claude-code
```

**在 Claude 桌面 app 裡**：同一台 Mac 上的 Code 分頁、終端機和 VS Code 擴充功能共用你這個使用者安裝的 plugin，所以在任一處裝一次就夠了。要從 Code 分頁安裝，按 prompt 輸入框旁的 **+**，選 **Add plugins**，加入 marketplace `samsonchen/agent-town-claude-code`，再安裝 town-link。這只對在你 Mac 上執行的 Code 分頁 session 有用（見[支援的環境](docs/known-issues.md#where-it-works-claude-desktop-cowork-and-others)，英文）。

和所有帶 hooks 模組的 plugin 一樣，town-link 以你的使用者權限執行。它只負責觀察，見 [town-link 讀取和傳送什麼](docs/privacy.md)（英文）。

### macOS 上的 App

需要 macOS 15 以上。用 [Homebrew](https://brew.sh)：

```bash
brew tap samsonchen/agent-town-claude-code https://github.com/samsonchen/agent-town-claude-code
```

```bash
brew install --cask samsonchen/agent-town-claude-code/agent-town
```

或從 [Releases](https://github.com/samsonchen/agent-town-claude-code/releases) 下載 `AgentTown-<版本>.dmg`，打開後把 AgentTown 拖進「應用程式」。

App 有 Developer ID 簽章並經過 Apple 公證，可以像一般 app 一樣直接打開。

App 會以一棟小建築的圖示出現在選單列，Dock 裡沒有圖示。開始工作前先打開它：town-link 只在 app 執行時傳送事件。要讓它開機時自動啟動，打開「設定」→「登入時開啟」。

更新：`brew upgrade --cask agent-town`，或下載新的 `.dmg`。

Plugin 和 app 各有自己的版本號，分開更新。`/town` 顯示 plugin 的版本，「關於 agent-town」顯示 app 的版本。兩者的版本號不需要相同，重要的是它們之間的通訊協定，雙方都會檢查。如果哪天無法一起使用，`/town` 會告訴你。

App 每天會到 GitHub 檢查一次有沒有新版的 app 和 town-link（「設定」→「更新」；不會送出任何關於你的資料）。有新版時，選單列圖示會出現一個圓點，選單會說是哪一個有新版，「更新」視窗會依你的安裝方式列出要執行的指令。Claude Code 的 session 會沿用它啟動時的 town-link，所以更新 plugin 後要重新啟動 session。

### Windows 上的 App

需要 Windows 11（x64）。安裝程式也允許 Windows 10，但 app 沒有在 Windows 10 上測試過。從 [Releases](https://github.com/samsonchen/agent-town-claude-code/releases) 找最新的 **agent-town for Windows**（標籤 `windows-v<版本>`），下載 `agent-town-setup-<版本>.exe` 並執行。它只安裝給你自己的帳號，不需要系統管理員權限，並會加到「開始」選單。

安裝程式還沒有程式碼簽章，所以第一次執行時 Windows 會顯示「Windows 已保護您的電腦」：按 **其他資訊**，再按 **仍要執行**。見[程式碼簽章政策（Code signing policy，英文）](https://samsonchen.github.io/agent-town-claude-code/code-signing-policy.html)。

App 在系統匣（通知區域）裡，工作列上沒有按鈕；關掉辦公室視窗只是把它藏起來。Windows 11 一開始會把新的系統匣圖示放在隱藏的圖示裡（**^** 箭頭）；把它拖出來就會一直看得到。要讓它登入時自動啟動，打開「設定」→「登入時開啟」。

更新：執行新版的安裝程式，它會取代已安裝的 app，並保留你的設定。「設定」→「更新」每天會檢查一次有沒有新的 Windows 版本，跟 Mac 一樣。移除：「設定」→「應用程式」→「已安裝的應用程式」→ agent-town →「解除安裝」。

Claude Code 要直接在 Windows 上執行（終端機、Desktop app 的 Code 分頁或 VS Code）。在 WSL 裡的 session 連不到 app。

## 3. 辦公室

視窗裡是一棟從上往下看的辦公大樓。最上面是執行長辦公室，你（執行長）和稽核員、調度員坐在一起。下面每個在 Claude Code 開著的專案各有一個區塊：區塊裡的幕僚長（就是那個 session）接你的工單，為每個 subagent 從休息區呼叫職員，派作業員到機房跑背景工作，Claude Code 要你核准時等你回覆，做完再打電話回報。派發工作、工作完成、需要你核准時，都會有提示音。

在筆電螢幕上，「設定」有「精簡檢視」（辦公室以一半大小顯示）和「隱藏閒置的專案區塊」，視窗也可以縮小，畫面會自動捲到有人在走動的地方。

## 4. 更多說明（英文）

以下文件目前只有英文版：

- [辦公室導覽與設定](docs/office.md)
- [已知問題與支援的環境](docs/known-issues.md)：哪些場景可能不顯示，以及哪些 Claude 使用方式可以用（終端機、桌面 app 的 Code 分頁、VS Code；雲端 session 和 Cowork 不行）
- [town-link 讀取和傳送什麼](docs/privacy.md)：事件只傳到你自己電腦上的 app，另外每個工作用你自己的方案向 Haiku 發幾個簡短請求，沒有別的
- [開發 agent-town](docs/development.md)：從原始碼執行、檢查、試跑修改、發行
- [所有文件](docs/README.md)

如果辦公室裡有什麼看起來不對，或你想要一個還沒有的場景，歡迎在 GitHub 開 issue。

## 授權

Apache 2.0，見 [LICENSE](LICENSE)。3D 模型是 Kenney 的 CC0 素材，見 [assets/LICENSES.md](assets/LICENSES.md)。
