---
name: collab-kit-init
description: 在目前專案初始化或升級「協作規則骨架」——把八節規則寫進 CLAUDE.md（決策分級、提問機制、工作模式、留痕與收尾、驗證：不接受目測、撰寫文件、累積型檔案觸發規則、委派邊界規格），並建立 QUESTIONS.md、SOP.md、ROADMAP.md、.claude/templates/session-handoff.md。使用者說「初始化協作規則」「裝 collab kit」「幫這個專案補上 CLAUDE.md 規則」「升級舊版 kit」「建立 QUESTIONS.md 流程」時使用這個 skill；即使他們只說「幫這個新專案設好我的工作規則」而沒點名 collab-kit，也用它。
disable-model-invocation: true
---

# Collab Kit Init

在專案根目錄缺什麼建什麼，已存在的內容不覆蓋。

## 這個 skill 的資源

| 檔案 | 什麼時候讀 |
|---|---|
| `assets/claude-md-rules.md` | 步驟 1：要附加進 `CLAUDE.md` 的八節規則全文 |
| `references/upgrade-existing.md` | 步驟 1b：專案已有舊版 kit 時，逐條改掉會打架的舊措辭 |
| `assets/QUESTIONS.md`、`assets/SOP.md`、`assets/ROADMAP.md`、`assets/session-handoff.md` | 步驟 3～6：原樣複製進專案 |

規則全文與模板一律直接複製檔案，不要憑記憶重打。

## 步驟 1：`CLAUDE.md`

規則全文（`assets/claude-md-rules.md`）由八個一級標題組成。**逐一檢查每個標題**，
不要用單一標題判斷整份是否已安裝。

| 標題 | 動作 |
|---|---|
| `# 決策分級` | 缺就附加 |
| `# 提問機制` | 缺就附加 |
| `# 工作模式` | 缺就附加（舊名 `# 長時工作模式`，見步驟 1b） |
| `# 留痕與收尾` | 缺就附加 |
| `# 驗證：不接受目測` | 缺就附加，並執行步驟 2 |
| `# 撰寫文件` | 缺就附加 |
| `# 累積型檔案觸發規則` | 缺就附加；已存在但沒有 `QUESTIONS.md` 那兩行就補進去 |
| `# 委派邊界規格` | 專案會用 subagent 才裝；不用就略過，並確認〈決策分級〉高風險清單有「委派」那一行 |

檔案不存在直接建立，存在則附加在末尾。

## 步驟 1b：改掉既有章節裡與新規則矛盾的措辭

只在專案已經有舊版 kit 時做。已存在的章節不覆蓋，但有幾處舊措辭會與新加的章節打架，
**逐條照 `references/upgrade-existing.md` 檢查並改掉**。

## 步驟 2：偵測「本專案的驗證指令」

〈驗證：不接受目測〉末尾的清單要填實際指令，不留空殼。唯讀偵測三層：

- **內層**：`package.json` 的 `scripts.test`、`pytest.ini` / `pyproject.toml`、`Makefile`、
  `cargo test`、`go test ./...`、`*.test.js` 配 `node --test`
- **使用者層**：e2e / 瀏覽器 / 子程序層級的測試（Playwright、Cypress、WebDriver、
  對真執行檔跑的整合測試）
- **真依賴**：「換掉假件跑同一套」的旗標，或需要起真服務的驗收步驟

填法：偵測到什麼寫什麼，標上實際測試項數。
**偵測不到使用者層時不留白、也不要用內層測試填**，改在 `QUESTIONS.md` 開第一題。
新增相依套件屬高風險，只出選項不安裝。

某一層確認過後判定不適用（例如純 CLI 專案沒有假件），寫「不適用」並寫明理由，不要留空。

**測試數字不要寫進 `CLAUDE.md`，寫進 `ROADMAP.md`。**

## 步驟 3～6：其餘檔案

缺就建立。**已存在的也要逐項檢查缺件並補上**，不要只看檔案在不在。

| 檔案 | 來源，以及已存在時要補的 |
|---|---|
| `QUESTIONS.md` | `assets/QUESTIONS.md` 全文 |
| `SOP.md` | `assets/SOP.md` 全文。**已存在時逐節檢查**：常缺「退場」與「已退役」；每條開頭要有 `(日期・工具/模型版本)` |
| `ROADMAP.md` | `assets/ROADMAP.md` 全文 |
| `.claude/templates/session-handoff.md` | `assets/session-handoff.md` 全文 |

## 完成後回報

- 哪些新建、哪些附加、哪些略過
- 步驟 1b 改掉了哪幾處舊措辭
- 步驟 2 三層各偵測到什麼，有沒有哪一層開成了 `QUESTIONS.md` 的題目
- **建立或修改的檔案裡，有哪些命中 `.gitignore`**（`.claude/` 常常整個被忽略）

不詢問是否要建立——唯讀偵測後寫入新檔／附加、不覆蓋既有內容，屬可自動執行層級。
**步驟 2 若需要新增相依套件，只寫進 `QUESTIONS.md`，不安裝。**
