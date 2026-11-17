# 升級：搬舊內容

步驟 4 用。讀者：執行升級的 agent。

原則：一件事只留一個家。搬完就刪舊檔，不留副本。刪檔與覆寫既有內容前，把要刪的清單列給 user 確認。

## 規則檔或 `CLAUDE.md` 留了 `.bak`

逐段看 `.bak`：

| 舊檔裡的內容 | 處理 |
|---|---|
| 本專案的驗證指令、服務埠、目錄、替身、專案工具的執行方式 | 搬進 `docs/project-rules.md` |
| 新版規則或 `docs/procedures/` 已涵蓋的通用規則（即使措辭不同） | 丟掉，以新版為準 |
| 本專案專屬、新版沒有的行為規則 | 搬進 `docs/project-rules.md`，並在回報列出，讓 user 決定要不要升成通用規則 |
| 專案的目標、現階段、目前綁住工作的約束 | 搬進 `STATE.md` |
| `CLAUDE.md.bak` 裡除了規則以外的 `@` 匯入 | 加回 `CLAUDE.md`，排在 `@STATE.md` 之後 |

搬完刪掉 `.bak`。

## 專案被改過的 `docs/procedures/`

腳本已整份覆寫。用 `git diff docs/procedures/` 看被蓋掉的專案改動，把專案專屬的部分搬進 `docs/project-rules.md`，在回報列出。

## 舊版 kit 的檔

| 舊檔 | 內容去哪 | 舊檔 |
|---|---|---|
| `handoff.md`、`.claude/templates/session-handoff.md` | 目前狀態與下一步 → `STATE.md`。已完成清單丟掉（`git log` 已有） | 刪 |
| `ROADMAP.md`〈基線〉 | 測試入口指令 → `STATE.md`〈測試〉。SHA 與測試數字丟掉 | 刪掉該節 |
| `ROADMAP.md`〈硬約束〉 | 每條 → `STATE.md`〈生效中的契約〉一列 | 刪掉該節 |
| `ROADMAP.md` 其餘 | `[later]`／`[parked]` 條目在 `ROADMAP/later.md`、`ROADMAP/parked.md`；開頭說明換成 `assets/ROADMAP.md` 的開頭 | 留 |
| `docs/decisions/<日期>-<slug>.md` | 每份 → `DECISIONS.md` 一行：日期、決定、決策者與 user 原話、反悔代價、釘住它的測試。格式或介面規格 → `docs/spec.md` 或 `docs/specs/` | 外部有連結指向的留著，其餘搬到 `archive/docs/decisions/` |
| `docs/decisions/README.md`、`index.md`、`topics/` | 無 | 刪 |
| `SOP.md`、`SOP/` | 仍會再發生的症狀與查法 → `docs/troubleshooting.md`，附日期。其餘丟掉 | 刪 |
| `NOTES.md` | 未處理的條目 → `ROADMAP.md`〈待辦項目〉 | 刪 |
| `claude-decisions.json`、`DECISIONS.jsonl` | 無。由 kit 以外的工具寫入 | 從 git 移除，檔名加進 `.gitignore` |
| `QUESTIONS.md` | 已答的題與選項表刪掉；決策 → `DECISIONS.md`；待辦 → `ROADMAP.md`；開頭換成 `assets/QUESTIONS.md` | 留 |
| devlog、逐輪進度紀錄 | 無 | 外部有連結指向的留一行說明，其餘刪 |
| 外部事實（配額、版本、站點現況） | `docs/environment.md`（從 `assets/environment.md` 複製） | — |

## 搬完後檢查

1. `STATE.md` 不超過 6 KiB，沒有佔位字。
2. 在專案內搜尋已刪的檔名與路徑（`SOP`、`handoff.md`、`docs/decisions/`、`基線`），把每個殘留的指標改到新位置或刪掉。
3. `CLAUDE.md` 匯入規則檔與 `STATE.md`。
4. 跑專案的測試入口指令一次，確認搬檔沒有弄壞程式引用的路徑。
