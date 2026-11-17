# 交接：kit 整合後還沒做的事

寫於 2026-11-17。讀者：你，以及接手的 agent。做完一項就刪掉那一項；全部做完就刪掉這個檔。

## 現在的狀態

- kit repo 已是整合版：規則檔只放不隨進度改變的規則，專案現況在 `STATE.md`，決策在 `DECISIONS.md`（一個決定一行），程序在 `docs/procedures/`（條件成立才讀）。
- 測試：`bash tests/test_install.sh`，52 條全過。
- 已 push（2026-11-17），本機與 `origin/main` 一致。已安裝的 `~/.claude/skills/collab-kit-init` 已換成 repo 的版本，舊版備份在 `~/.claude/skills-backup/collab-kit-init-2026-11-17`。
- **安裝腳本的改動還沒經過冷審查。** 對第一個專案正式重裝之前，先用 ChatGPT 審一輪（user 2026-11-17 決定）。在那之前只跑 `--dry-run`。
- **沒有任何專案重裝過**。整合版只在測試的暫存目錄裡跑過。

## kit 本身

### 2. 還沒讓全新的 agent 用這套結構開工過

整套結構的假設是「agent 只讀 `AGENTS.md` 和 `STATE.md` 就能正確開工，需要時會自己去讀對的程序檔」。這個假設沒有驗過。

- 要做：在一個裝好的專案開全新 session，給一個要改程式的小任務，看它有沒有讀 `docs/procedures/verification.md` 和 `close-round.md`、有沒有漏做冷審查、有沒有多讀不該讀的檔。
- 壞的訊號：agent 沒讀程序檔就 commit；或一開工就把六個程序檔全讀完。

### 3. 文件檢查腳本還沒有

機器能檢查的事現在還是靠 agent 自己記得：文件裡寫到的路徑是否存在、Markdown 是否超過 32 KiB、`STATE.md` 是否超過 6 KiB、`CLAUDE.md` 是否匯入規則檔與 `STATE.md`。

- 要做：寫成 kit 的 `assets/` 裡的一支腳本，裝進每個專案的 `tools/`，並用 git 的 pre-commit hook 讓它自動跑，agent 不必記得。
- 可抄的起點：`tests/test_install.sh` 裡「裝進專案的文件引用的檔案全部存在」那一段已經是一個路徑檢查；dreamcore-explorer 的 `ROADMAP.md` 有這支腳本的規格。
- 注意：新增 hook 會改每個專案的 git 設定，裝之前要你同意。

### 4. 沒有「哪些專案還沒更新」的指令

每個專案裝完會有 `.collab-kit-version`（規則全文加程序檔的內容雜湊）。現在要比對只能一個一個看。

- 要做：一支腳本，給一串專案路徑，印出每個專案的版本戳與 kit 現在的值是否相同。

### 6. 冷審查的深度沒有動

現行規則：每一批程式改動，重複送審直到審查者說沒有阻擋後續開發的問題。另一個選項是只有動到公開契約時才重複，其餘只審一次。你沒說要改，所以維持原樣。

### 7. 拿這套規則做線上服務的風險，一項都還沒處理

- push 到 `main` 不必問，但有些專案 push 就等於發布（dreamcore-explorer 和 minecraft-dungeons-wiki 都有 GitHub Pages 的 workflow）。
- 推送前只跑和改動有關的測試。
- 資料格式改了之後，「這是不是還在原型階段、可以直接改」由 agent 自己判斷。
- 「必須先問」的清單沒有涵蓋：密鑰與環境變數的處理、對外發送訊息、刪除雲端資源。
- 外部的 ChatGPT 審查會看到 diff。
- 沒有環境區分、回滾步驟、事故處理的位置。
- 冷審查的重複次數沒有上限。

要拿它開線上服務前，先決定這幾項。

## 各專案

| 專案 | 現在的規則版本 | 狀況 | 要做 |
|---|---|---|---|
| dreamcore-explorer | 規則檔與 kit 相同；`docs/procedures/` 比 kit 舊 | 已手工改成新結構 | 見下方 |
| minecraft-dungeons-wiki、`-luna`、`-sol` | 已安裝副本的那個分岔 | `docs/spec.md` 與三份子規格有未提交的改動；同一組測試數字寫在四個地方 | 等未提交的改動 commit 後再裝。`handoff.md`、〈基線〉、8 份決策檔照 `references/upgrade-existing.md` 搬 |
| calculus-visualizer | 更舊的版本 | 文件債最重：113 份決策檔、`ROADMAP.md` 24.7 KB、`SOP` 13 個檔約 134 個標題、753 個 commit 中 178 個只動文件。CI 停用，36 個測試被跳過 | 優先處理。先只做文件搬遷，不碰程式。程式的技術債我只看過規模數字，沒讀程式 |
| probability-visualizer | 另一個舊版本 | 沒看過內容 | 先 `--dry-run` |
| Discord-Drive、ntpu-week-survival、personal-website | 最舊的版本，規則直接寫在 `CLAUDE.md` | 沒看過內容 | 先 `--dry-run`。安裝會把 `CLAUDE.md` 換成兩行匯入，舊檔留成 `CLAUDE.md.bak` |
| photo editor | 另一個舊版本 | 沒看過內容 | 先 `--dry-run` |

每個專案的做法相同：先跑 `install.sh --project <路徑> --dry-run` 看會動什麼，確認後正式跑，再照 `references/upgrade-existing.md` 搬舊檔。搬舊檔會刪檔，要你確認清單。

### dreamcore-explorer 還剩的

- `docs/procedures/` 和 kit 有三處不同：kit 把「記到 `SOP/`」改成「記到 `docs/troubleshooting.md`」；kit 拿掉了指向 `archive/README.md` 的指標；dreamcore 多兩行專案專屬的內容（房間檔的參數鍵只增不改名、文件檢查腳本的項目編號）。重裝前先把那兩行搬進 `docs/project-rules.md`，否則會被蓋掉。
- `SOP.md`、`SOP/`、`NOTES.md` 還在，沒搬。
- 光照設計的基礎還沒寫（你說可以先寫）。
- 左上角的畫質標籤：你說考慮改成「自動」。我沒查它現在是不是真的會自動調；不會的話改標籤反而誤導。
- `claude-decisions.json` 是專案外的工具寫的，寫入來源沒找到。
- `docs/final-proposal/` 的七個刪除還在你的工作目錄，沒提交，等你決定。

## 等你回答的

1. dreamcore-explorer 每次 push 到 `main` 都會自動發布到 GitHub Pages。你接受嗎？不接受的話，「push `main` 永遠放行」這條要加例外。
2. 文件檢查腳本和「哪些專案還沒更新」的腳本，由我寫還是交給 builder？這次的安裝腳本和測試是我直接改的。
3. kit 要不要 push？
