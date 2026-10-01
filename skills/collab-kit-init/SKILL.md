---
name: collab-kit-init
description: 在目前專案初始化或升級「協作規則骨架」——把開頭句與八節規則寫進規則檔（CLAUDE.md，或 CLAUDE.md 以 @ 匯入的檔，例如 AGENTS.md）：決策分級、提問機制、工作模式、留痕與收尾、驗證：不接受目測、撰寫文件、累積型檔案觸發規則、委派邊界規格；並建立 QUESTIONS.md、SOP.md＋SOP/README.md、ROADMAP.md＋ROADMAP/later.md＋ROADMAP/parked.md、docs/decisions/README.md、.claude/templates/session-handoff.md、tools/outline.py。user 說「初始化協作規則」「裝 collab kit」「幫這個專案補上 CLAUDE.md 規則」「升級舊版 kit」「建立 QUESTIONS.md 流程」時使用這個 skill；即使 user 只說「幫這個新專案設好我的工作規則」而沒點名 collab-kit，也用它。
disable-model-invocation: true
---

# Collab Kit Init

在專案根目錄缺什麼建什麼，已存在的內容不覆蓋。

## 這個 skill 的資源

| 檔案 | 什麼時候讀 |
|---|---|
| `scripts/install.sh` | 步驟 1、3～6：實際寫檔的腳本。跑它，不要自己一個一個複製 |
| `assets/claude-md-rules.md` | 步驟 1：要寫進規則檔的開頭句與八節規則全文（含安裝時代入的佔位字串） |
| `assets/push-policy-pr.md`、`assets/push-policy-direct.md` | 步驟 1：推送政策兩版，腳本依 `--direct-push-main` 只代入其中一版 |
| `references/upgrade-existing.md` | 步驟 1b：專案已有舊版 kit 時，逐條改掉會打架的舊措辭 |
| `assets/QUESTIONS.md`、`assets/SOP.md`、`assets/SOP-README.md`、`assets/ROADMAP.md`、`assets/ROADMAP-later.md`、`assets/ROADMAP-parked.md`、`assets/decisions-README.md`、`assets/session-handoff.md`、`assets/outline.py` | 步驟 3～6：腳本原樣複製進專案 |
| `assets/environment.md` | 步驟 3～6：腳本不建，你原樣複製成 `docs/environment.md` |

規則全文與模板一律由 `scripts/install.sh` 複製，不要自己寫入、也不要憑記憶重打。

## 步驟 1：規則檔

**規則檔**＝`CLAUDE.md` 裡有單獨一行 `@<相對路徑>` 匯入（只看一層）時，被匯入的那個檔；
沒有就是 `CLAUDE.md`。腳本自己判斷並印出結果，`CLAUDE.md` 在有匯入時不動。

規則全文（`assets/claude-md-rules.md`）＝一句開頭句＋八個一級標題。跑腳本，它**逐一檢查開頭句與每個標題**，
不用單一標題判斷整份是否已安裝：

```bash
bash <本 skill 目錄>/scripts/install.sh --project <專案根目錄> [選項]
```

| 選項 | 作用 |
|---|---|
| `--with-delegation` | 一併裝〈委派邊界規格〉；專案會用 subagent 才給 |
| `--direct-push-main` | 推送政策改成「驗證綠了直接推 `main`，不必開分支、不必開 PR」；不給就是「絕不 push `main`／`master`，開功能分支、開 PR」。〈決策分級〉裡關於 push `main` 的那幾行跟著換 |
| `--service-ports "8000,5173"` | 〈留痕與收尾〉「推之前必須獨占工作目錄」要檢查的服務埠；不給就寫「無」 |
| `--cold-start-tokens N` | 冷啟動 agent 一次讀入超過多少 token 屬高風險；預設 `100000` |
| `--dry-run` | 只印出會做什麼（含規則檔判斷結果），不寫檔 |

推送政策與服務埠照 user 的工作方式選；不確定就先 `--dry-run`，把這兩項開成 `QUESTIONS.md` 的題。
腳本一併做完步驟 3～6，並印出每節、每個檔案的處置。

| 規則檔裡的標題 | 動作 |
|---|---|
| 開頭句「用規則檔所寫的主要語言回答問題，不是 user 的語言。」 | 缺就加在規則檔最前面（不屬於八節） |
| `# 決策分級` | 缺就附加 |
| `# 提問機制` | 缺就附加 |
| `# 工作模式` | 缺就附加（舊名 `# 長時工作模式`，見步驟 1b） |
| `# 留痕與收尾` | 缺就附加 |
| `# 驗證：不接受目測` | 缺就附加，並執行步驟 2 |
| `# 撰寫文件` | 缺就附加 |
| `# 累積型檔案觸發規則` | 缺就附加 |
| `# 委派邊界規格` | 給 `--with-delegation` 才裝；不裝就略過，並確認〈決策分級〉高風險清單有「委派」那一行 |

規則檔不存在腳本直接建立，存在則附加在末尾；既有章節不覆蓋。

## 步驟 1b：改掉既有章節裡與新規則矛盾的措辭

只在專案已經有舊版 kit 時做。已存在的章節不覆蓋，但有幾處舊措辭會與新加的章節打架，
**逐條照 `references/upgrade-existing.md` 檢查並改掉**。

## 步驟 2：偵測「本專案的驗證指令」

〈驗證：不接受目測〉末尾的清單要填實際指令，不留空殼。唯讀偵測三層：

- **內層**：`package.json` 的 `scripts.test`、`pytest.ini` / `pyproject.toml`、`Makefile`、
  `cargo test`、`go test ./...`、`*.test.js` 配 `node --test`
- **user 層**：e2e / 瀏覽器 / 子程序層級的測試（Playwright、Cypress、WebDriver、
  對真執行檔跑的整合測試）
- **真依賴**：「換掉假件跑同一套」的旗標，或需要起真服務的驗收步驟

填法：偵測到什麼寫什麼，標上實際測試項數。
**偵測不到 user 層時不留白、也不要用內層測試填**，改在 `QUESTIONS.md` 開第一題。
新增相依套件屬高風險，開成一題不安裝——選項留到問 user 的當下再給，不寫進檔案。

某一層確認過後判定不適用（例如純 CLI 專案沒有假件），寫「不適用」並寫明理由，不要留空。

**測試數字不要寫進規則檔，寫進 `ROADMAP.md`〈基線〉。**

## 步驟 3～6：其餘檔案

步驟 1 的腳本一併建立：缺就建，已存在就回報「已存在」不覆蓋。
腳本標「已存在」的檔案，**你還是要逐項檢查缺件並補上**，不要只看檔案在不在。

| 檔案 | 來源，以及已存在時要補的 |
|---|---|
| `QUESTIONS.md` | `assets/QUESTIONS.md` 全文。**已存在時**：把不符合「問一次就答得完」的條目搬走（決策進 `docs/decisions/`、教訓進 `SOP/`、待辦進 `ROADMAP.md`〈待辦項目〉），已答的題刪掉，選項表刪掉 |
| `SOP.md` | `assets/SOP.md` 全文：只有依症狀分流的〈目錄〉。**已存在時**：條目若還躺在 `SOP.md` 裡，依症狀拆進 `SOP/<症狀分類>.md`，每檔編號各自從 1 重編，並把全專案的 `SOP #N` 引用改成 `SOP[檔名]#N`；〈目錄〉每一列的「放什麼／不放什麼」兩欄都要填；觸發、格式、退場等寫法規則移到 `SOP/README.md` |
| `SOP/README.md` | `assets/SOP-README.md` 全文：觸發條件、格式、`(日期・工具/模型版本)`、引用與編號、退場與 `SOP/已退役.md` |
| `ROADMAP.md` | `assets/ROADMAP.md` 全文：五個標記、四欄條目格式（具體細節／怎麼做／會改變什麼／做後回退代價）、〈硬約束〉〈基線〉〈待辦項目〉；`[later]`／`[parked]` 條目分別放 `ROADMAP/later.md`、`ROADMAP/parked.md`（腳本建這兩檔）。**已存在時**：把 `[later]`／`[parked]` 條目搬進那兩檔、決策搬進 `docs/decisions/`（一條一個檔，檔名 `YYYY-MM-DD-<slug>.md`）、外部事實搬進 `docs/environment.md`、逐輪的〈現況〉只留最新一輪改寫成〈基線〉，其餘靠 git 歷史 |
| `docs/decisions/README.md` | `assets/decisions-README.md` 全文：一條決策一個檔、檔名 `YYYY-MM-DD-<slug>.md`、列依據與反悔成本 |
| `docs/environment.md` | `assets/environment.md` 全文（腳本不建，你複製） |
| `.claude/templates/session-handoff.md` | `assets/session-handoff.md` 全文 |
| `tools/outline.py` | `assets/outline.py` 原樣：列出原始碼（`.py`、JS/TS、C/C++）、`.css`、`.md` 各區塊的起訖行號，其他類型只印行數；〈決策分級〉「讀超過 200 行的檔案之前」那條用它 |

## 完成後回報

- 規則檔是哪一個（`CLAUDE.md` 或被匯入的檔），以及推送政策、服務埠、冷啟動上限各裝了什麼
- 哪些新建、哪些附加、哪些略過、哪些已存在
- 步驟 1b 改掉了哪幾處舊措辭
- 步驟 2 三層各偵測到什麼，有沒有哪一層開成了 `QUESTIONS.md` 的題目
- **建立或修改的檔案裡，有哪些命中 `.gitignore`**（`.claude/` 常常整個被忽略）

不詢問是否要建立——唯讀偵測後寫入新檔／附加、不覆蓋既有內容，屬可自動執行層級。
**步驟 2 若需要新增相依套件，只寫進 `QUESTIONS.md`，不安裝。**
