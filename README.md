# collab-kit-init

一個 [Claude Code Skill](https://docs.claude.com/en/docs/claude-code/skills)：在專案根目錄初始化一整套人機協作規則與骨架。

手動觸發。其他專案、其他 session 不載入、不佔 token。

## 設計

每個檔和每個步驟都要答得出：「誰讀它，讀完會做什麼不一樣的事？」答不出來就不裝。

- **開工只先讀兩個檔**（有 `CLAUDE.md` 匯入的平台自動載入）：規則檔（不隨進度改變的規則）與 `STATE.md`（專案現況）。
- **程序條件成立才讀**：提問、驗證、改資料格式、委派、收尾、雜務各一個檔，規則檔裡只有一張觸發表。
- **一件事只有一個家**：其餘位置用路徑加編號指過去。對 user 的訊息相反，直接寫內容。
- **現行檔只寫生效中的事**：理由與沿革留在 git。
- **kit 的檔與專案的檔分開**：升級只覆寫 kit 的檔。

## 它會建立什麼

kit 擁有，每次安裝整份覆寫：

| 檔案 | 作用 |
|---|---|
| 規則檔 | 一律是 `AGENTS.md`，只讀 `AGENTS.md` 的 agent 也讀得到。內容是 `assets/claude-md-rules.md` 全文。內容不同時舊檔留成 `.bak` |
| `docs/procedures/` | `questions.md`、`verification.md`、`data-format.md`、`delegation.md`、`close-round.md`、`chores.md` |
| `.collab-kit-version` | 規則全文加程序檔的內容雜湊（12 位）。兩個專案的值相同，代表裝的是同一版 |

專案擁有，缺才建，已存在不覆蓋：

| 檔案 | 作用 |
|---|---|
| `CLAUDE.md` | 匯入 `AGENTS.md` 與 `STATE.md`。不存在就新建；已有 `@` 匯入時保留原內容，只補缺的行；完全沒有 `@` 匯入（規則寫在裡面）時換成兩行匯入並留 `.bak`，這是本表唯一會動既有檔的情況 |
| `STATE.md` | 目標、生效中的契約、下一步、停損訊號、檔案地圖、測試指令。上限 6 KiB |
| `DECISIONS.md` | 一個決定一行：日期、決定、決策者與 user 原話、反悔代價、釘住它的測試 |
| `QUESTIONS.md` | 需要拍板的事寫這裡，不停下來等。只放「問一次就答得完」的問題 |
| `ROADMAP.md`、`ROADMAP/later.md`、`ROADMAP/parked.md` | 未完成的待辦。做完就刪 |
| `docs/spec.md`、`docs/plans/README.md` | 公開契約與驗收；跨輪計畫的寫法 |
| `docs/project-rules.md` | 本專案專屬的目錄、驗證指令、替身、服務埠、工具執行方式，以及專案自己的規則 |
| `docs/testing.md`、`docs/cold-review.md` | 測試分層與推送前驗證；冷審查（獨立子代理優先，外部工具為選用） |
| `tools/outline.py` | 列出原始碼、`.css`、`.md` 各區塊的起訖行號；讀長檔時只讀要動的那一段 |

用到才建、腳本不建：`docs/troubleshooting.md`（會重複出現的症狀與查法）、`docs/environment.md`（外部事實，從 `assets/environment.md` 複製）、`docs/specs/`（子規格）、`docs/spec.proposed.md`（agent 寫的 `docs/spec.md` 修改後完整內容，由 user 自己套用）。

## 檔案結構

```
skills/collab-kit-init/
├── SKILL.md                        安裝步驟（觸發時才載入的只有這一份）
├── scripts/install.sh              實際寫檔的腳本
├── assets/claude-md-rules.md       規則全文 → 規則檔
├── assets/procedures/*.md          → docs/procedures/
├── assets/STATE.md、DECISIONS.md、QUESTIONS.md、ROADMAP.md
├── assets/ROADMAP-later.md         → ROADMAP/later.md
├── assets/ROADMAP-parked.md        → ROADMAP/parked.md
├── assets/spec.md                  → docs/spec.md
├── assets/plans-README.md          → docs/plans/README.md
├── assets/project-rules.md、testing.md、cold-review.md → docs/
├── assets/outline.py               → tools/outline.py
├── assets/hooks/                   → tools/hooks/、git pre-commit（--with-hooks 才安裝）
├── scripts/merge_hooks.py          把 hooks 區塊合併進各 agent 的設定檔（見〈選用的 hook〉）
└── assets/environment.md           需要時手動複製成 docs/environment.md
```

## 選用的 hook

預設安裝不碰 hook。`install.sh --with-hooks` 才裝，會改專案的 `.claude/settings.json`、`.codex/hooks.json` 與 git 的 `pre-commit`。兩個 agent 的保護機制刻意不同：Claude Code 有靜態權限規則，比 hook 更強；Codex 沒有等價物，只能用 hook。

| 保護 | Claude Code | Codex |
|---|---|---|
| 密鑰與憑證檔（`.env`、`*.pem`、`id_rsa` 等；`.env.example` 等範本除外） | `permissions.deny` 的 `Read(…)` 規則：Claude Code 自己執行，同時涵蓋檔案工具與 Bash 的 `cat`／`sed`／`tee`／重導向、解析 symlink，不會逾時放行 | hook：`apply_patch` 碰到就 `deny`（讀檔走 Bash，不擋） |
| 改 `AGENTS.md`、`docs/procedures/*.md`、`docs/spec.md` | `permissions.deny` 的 `Edit(/…)` 規則 | hook：從 `apply_patch` 的 patch 文字解析路徑（`collab_adapters.py`） |
| force push | `permissions.deny` 的 `Bash(git push …)` 規則；hook 再擋一次 | hook |
| push 到 `main`／預設分支 | hook（靜態規則看不出「目前分支」）：先剝掉重導向與 `-o` 等帶值選項再解析 | 同左，同一份腳本 |
| GitHub MCP 的 `push_files`、`create_or_update_file`、`delete_file`、`merge_pull_request` | `permissions.deny` 整個擋掉（看不出目標分支）；`--allow-github-mcp-writes` 可關閉 | 未涵蓋 |
| 開工讀 `STATE.md` | `CLAUDE.md` 的 `@STATE.md` | `SessionStart` hook 注入（另設 `additionalContextLimit`） |
| 文件檢查 | git `pre-commit`（與 agent 無關）：Markdown 不超過 32 KiB、`STATE.md` 不超過 6 KiB、`CLAUDE.md` 有匯入 `AGENTS.md` 與 `STATE.md`（擋 commit）；文件引用的路徑不存在（只警告） | 同左 |

- 被擋時一律 `deny`：Codex 的 `PreToolUse` 不支援 `ask`（回 `ask` 會讓工具照樣執行）。理由要 agent 用內建問答工具問 user，由 user 自己執行。
- `docs/spec.md` 被擋時，agent 改寫 `docs/spec.proposed.md`（不受擋），並在 `QUESTIONS.md` 開一題。
- 專案已明寫放行 push `main` 時加 `--allow-push-main`（force push 與檔案保護仍擋）。
- Claude 的 `permissions.deny` 規則由 `merge_hooks.py` 合併：只移除「完全等於我們寫過的規則」再接成連續一段加在最後（`!` 否定規則必須排在被排除的規則後面），使用者其他規則與設定不動；重跑冪等，使用者若刪掉我們的規則，重跑會加回來。
- 刻意不做：不用正規表示式去猜 Bash 指令會不會改檔或讀 `.env`（又誤擋又漏擋）；Claude 端交給 Claude Code 自己的權限規則。這些規則是指令文字比對，不是安全邊界（`/usr/bin/git push`、`git -C . push`、腳本內自己開檔都繞得過）。
- Claude 規則裡的 `/AGENTS.md` 這類寫法以「專案設定檔所在專案的主要工作目錄」為起點：在專案子目錄啟動 Claude 時，這些路徑對不到專案根目錄。
- `--with-hooks` 要求 `--project` 是 git 專案的頂層目錄：hook 與 `pre-commit` 都以 git 根目錄定位腳本，裝在子目錄會全部失效，預檢會中止。
- 腳本出錯一律以結束碼 1 收場，不用結束碼 2（兩邊都當成「阻擋」）。hook 只是護欄：兩邊的文件都說明 hook 逾時或出錯時工具會照常執行。
- 需要 `python3`（3.7 以上）與 POSIX `sh`；不支援 Windows 的 `commandWindows`。Codex 端的行為依官方文件模擬驗證，未經 Codex 實機測試；Claude 的規則語法依官方 permissions 文件撰寫，也未在 Claude Code 上端到端實測。

### Codex 端：裝了不一定生效

下列情況 hook 會**靜默失效**，沒有錯誤訊息，使用者會以為有護欄：

1. **專案沒有被 Codex 信任。** 專案層的 `.codex/hooks.json` 只在受信任的專案載入。
2. **hook 定義變動後要重新核准。** Codex 以 hook 定義的雜湊記錄信任，新的或變動的 hook 會被標為待審並略過，直到在 `/hooks` 核准。重跑 `install.sh --with-hooks`、改 `--allow-push-main` 都會讓雜湊改變。
3. **非互動執行（`codex exec`、CI）沒有人可以核准。** 需要先核准過，或明確用 `--dangerously-bypass-hook-trust`；否則這些 hook 不會執行。
4. **管理員可以關掉。** 設定 `[features].hooks = false`，或 `allow_managed_hooks_only = true`（只載入管理員的 hook，略過專案與使用者的 hook）。

裝完以後，在 Codex 開 `/hooks` 確認列出 collab 的 hook 且已核准。預設沙箱把 `<專案>/.git`、`.codex`、`.agents` 視為唯讀：agent 在沙箱內改不了 hook 設定，但在沙箱內 `git commit` 也需要升權。

### Codex 端：`AGENTS.md` 有 32 KiB 上限

Codex 從專案根目錄往下，把沿途每一層的 `AGENTS.md`（含 `AGENTS.override.md`）串接成一份指示，「combined size reaches the limit defined by `project_doc_max_bytes` (32 KiB by default)」就停止加入後面的檔。這個 kit 的規則檔約 9.8 KiB，所以：

- 專案子目錄自己的 `AGENTS.md` 不要太大，否則後面的內容（越靠近工作目錄越晚加入）會被截掉。
- 專案專屬的規則寫進 `docs/project-rules.md`，不要都塞進 `AGENTS.md`。
- 需要時可在 Codex 設定調高 `project_doc_max_bytes`。

## 改規則的流程

規則全文只有一份：`assets/claude-md-rules.md`。

1. 在 kit 改 `assets/claude-md-rules.md` 或 `assets/procedures/`。
2. 跑測試。
3. 對每個要更新的專案重跑 `install.sh`。比對 `.collab-kit-version` 可知哪些專案還沒更新。

不要在專案裡直接改規則檔或 `docs/procedures/`：下次安裝會被覆寫。專案專屬的規則寫進 `docs/project-rules.md`。

## 測試

```bash
bash tests/test_install.sh      # 安裝腳本；結尾會再跑一次 hook 測試
python3 tests/test_hooks.py     # 只跑 hook、pre-commit 與 --with-hooks
```

對暫存目錄真跑 `install.sh`，斷言：該建的檔都建了、規則檔與程序檔逐字等於 assets、
裝進專案的文件引用的路徑全部存在、專案擁有的既有檔不被覆蓋、程序檔與版本戳會被覆寫、重跑不重複加行、`--dry-run` 不寫檔。

## 安裝

複製 `skills/collab-kit-init/` 整個目錄（含 `assets/` 與 `scripts/`）到目標專案的
`.claude/skills/` 或 `skills/` 下，再手動觸發這個 skill。
完整步驟見 [`skills/collab-kit-init/SKILL.md`](skills/collab-kit-init/SKILL.md)。
