---
name: collab-kit-init
description: 在目前專案初始化或更新「協作規則骨架」——把通用規則整份寫進 AGENTS.md，把條件成立才讀的程序檔寫進 docs/procedures/，並建立專案自己維護的檔：STATE.md、DECISIONS.md、QUESTIONS.md、ROADMAP.md＋ROADMAP/later.md＋ROADMAP/parked.md、docs/spec.md、docs/plans/README.md、docs/project-rules.md、docs/testing.md、docs/cold-review.md、tools/outline.py。user 說「初始化協作規則」「裝 hook」「裝 collab kit」「幫這個專案補上 CLAUDE.md 規則」「更新 kit 版本」「建立 QUESTIONS.md 流程」時使用這個 skill；即使 user 只說「幫這個新專案設好我的工作規則」而沒點名 collab-kit，也用它。
disable-model-invocation: true
---

# Collab Kit Init

## 誰擁有哪個檔

| 擁有者 | 檔案 | 安裝與升級時 |
|---|---|---|
| kit | 規則檔（`AGENTS.md`）、`docs/procedures/*.md`、`.collab-kit-version` | 每次整份覆寫。規則檔內容不同時舊檔留成 `.bak`。專案不改這些檔 |
| 專案 | `STATE.md`、`DECISIONS.md`、`QUESTIONS.md`、`ROADMAP.md`、`ROADMAP/`、`docs/spec.md`、`docs/plans/`、`docs/project-rules.md`、`docs/testing.md`、`docs/cold-review.md`、`tools/outline.py` | 缺才建，已存在不覆蓋 |
| 專案 | `CLAUDE.md` | 只保證它匯入 `AGENTS.md` 與 `STATE.md`。不存在就新建；已有 `@` 匯入時保留原內容、只補缺的行；完全沒有 `@` 匯入時換成兩行匯入並留 `.bak` |

專案專屬的規則寫進 `docs/project-rules.md`，不寫進規則檔或 `docs/procedures/`：那兩處下次升級會被覆寫。

## 這個 skill 的資源

| 檔案 | 用途 |
|---|---|
| `scripts/install.sh` | 實際寫檔的腳本。跑它，不要自己一個一個複製 |
| `assets/claude-md-rules.md` | 規則全文：不隨專案進度改變的規則，加一張程序觸發表 |
| `assets/procedures/` | 六個程序檔：提問、驗證、改資料格式、委派、收尾與推送、雜務 |
| `assets/STATE.md` | 專案現況的模板：目標、生效中的契約、下一步、停損訊號、檔案地圖、測試指令 |
| `assets/DECISIONS.md` | 決策表的模板：一個決定一行 |
| `assets/spec.md`、`assets/plans-README.md` | `docs/spec.md` 與 `docs/plans/README.md` 的模板 |
| `assets/project-rules.md`、`assets/testing.md`、`assets/cold-review.md` | 專案自己填值的模板 |
| `assets/hooks/` | 選用的 hook（`--with-hooks` 才安裝）：`collab_hook.py` 共用核心、`collab_adapters.py` 兩個 agent 的輸入差異、`doc_check.py` 與 `pre-commit` 文件檢查 |
| `scripts/merge_hooks.py` | 把 hook 設定冪等合併進各 agent 的設定檔（見步驟 5） |
| `assets/environment.md` | 腳本不建；專案需要記外部事實時手動複製成 `docs/environment.md` |

規則全文與模板一律由 `scripts/install.sh` 複製，不要自己寫入、也不要憑記憶重打。

## 步驟 1：跑腳本

```bash
bash <本 skill 目錄>/scripts/install.sh --project <專案根目錄> [--dry-run]
```

- 規則一律寫進 `AGENTS.md`，內容不同時舊檔留成 `AGENTS.md.bak`
- 預檢：`CLAUDE.md` 或 `AGENTS.md` 是 symlink、兩者是同一個檔（硬連結）、任何要寫的檔是目錄或斷掉的 symlink 時，腳本中止（結束碼 3），不寫任何東西（含 `--dry-run`）。把問題清單轉給 user 處理。`.bak` 已存在時不覆蓋，改用 `.bak.1`、`.bak.2`
- `CLAUDE.md` 不存在：新建成 `@AGENTS.md` 與 `@STATE.md` 兩行
- `CLAUDE.md` 已有單獨一行 `@<路徑>` 匯入：保留原內容，只補缺的 `@AGENTS.md`、`@STATE.md`。原本匯入的其他檔不動；其中若有舊版規則全文，回報會提醒手動移除
- `CLAUDE.md` 沒有任何 `@` 匯入（規則直接寫在裡面）：換成兩行匯入，舊檔留成 `CLAUDE.md.bak`
- `.collab-kit-version` 是規則全文加程序檔的內容雜湊。腳本回報印出舊值與新值
- `--dry-run` 只印出會做什麼

## 步驟 2：填 `STATE.md`

這個檔還是模板（含 `<` 開頭的佔位字）時，照已知事實填：

- **目標**：從 README、`docs/spec.md`、user 在對話中的說法取得。取不到就在 `QUESTIONS.md` 開一題，不猜
- **生效中的契約**：只寫現在綁住工作的約束。沒有就留空表
- **下一步**、**測試**：填得出來才填
- 上限 6 KiB。不寫沿革、不寫測試數字

## 步驟 3：填 `docs/project-rules.md`

這個檔只有開頭註解時，唯讀偵測後寫進去：

- **目錄**：Python 目錄（`pyproject.toml` 所在）、前端目錄
- **驗證指令**：內層（`package.json` 的 `scripts.test`、`pytest.ini`／`pyproject.toml`、`Makefile`、`cargo test`、`go test ./...`）、
  user 層（Playwright、Cypress、WebDriver、對真執行檔跑的整合測試）、真依賴與替身
- **開發服務埠**：推送前要確認沒人佔的埠
- **專案專屬工具**：例如 `tools/outline.py` 在本專案的執行方式

偵測到什麼寫什麼。偵測不到 user 層時不用內層測試填，在 `QUESTIONS.md` 開一題。
確認不適用的層寫「不適用」加理由。測試數字不寫進任何檔，寫在 commit message。
需要新增相依套件時只開題，不安裝。
授權類內容（push `main` 放行、外部工具、額度上限）不偵測、不推論，只在 user 明示後才寫入。

## 步驟 4：處理 `.bak` 與被覆寫的程序檔

規則檔或 `CLAUDE.md` 留了 `.bak` 時，逐段看 `.bak`：

- 本專案的目錄、指令、專案專屬規則 → 搬進 `docs/project-rules.md`。通用規則不搬
- 專案的目標、現階段、目前綁住工作的約束 → 搬進 `STATE.md`
- `CLAUDE.md.bak` 裡除了規則以外的 `@` 匯入 → 加回 `CLAUDE.md`，排在 `@STATE.md` 之後
- 授權類內容（push `main` 放行、外部工具、額度上限）一律不搬，列出哪些行沒搬，由 user 決定是否寫入

搬完告訴 user 哪些行搬到哪、`.bak` 可以刪。不自己刪 `.bak`。

專案若改過 `docs/procedures/`：腳本已整份覆寫。用 `git diff docs/procedures/` 看被蓋掉的專案改動（改動必須曾經提交過才找得回），把專案專屬的部分搬進 `docs/project-rules.md`，在回報列出。

## 步驟 5：選用的 hook（只在 user 要求時）

預設安裝不碰 hook。裝 hook 會改專案的 `.claude/settings.json`、`.codex/hooks.json` 與 git 的 `pre-commit`，**user 沒有明確要求就不要加 `--with-hooks`**。

```bash
bash <本 skill 目錄>/scripts/install.sh --project <專案根目錄> --with-hooks [--allow-push-main] [--dry-run]
```

- 安裝內容：`tools/hooks/`（共用核心、兩個 agent 的差異轉接、文件檢查）；兩份設定的 hooks 區塊（冪等合併，舊檔留 `.bak`，其他設定不動）；git `pre-commit`（已有別人的 hook 就不覆蓋）
- hook 做什麼：`SessionStart` 把 `STATE.md` 注入上下文（只裝給 Codex，Claude 已由 `CLAUDE.md` 載入）；`PreToolUse` 的 Bash 只擋 push 到 `main`／預設分支與 force push；檔案工具擋改 `AGENTS.md`、`docs/procedures/*.md`、`docs/spec.md` 與碰 `.env`、金鑰憑證檔（Bash 讀 `.env`、改受保護檔不擋）；`pre-commit` 檢查 Markdown 不超過 32 KiB、`STATE.md` 不超過 6 KiB、`CLAUDE.md` 有匯入（擋 commit），文件引用的路徑不存在只警告
- 專案已在 `docs/project-rules.md` 明寫放行 push `main` 時加 `--allow-push-main`（force push 與檔案工具的保護仍擋）。這是 user 在安裝時的明示決定，不要自己判斷
- 被擋時 hook 一律回 deny（Codex 不支援 ask），理由要 agent 用內建問答工具問 user，由 user 自己執行。改 `docs/spec.md` 被擋時，agent 改寫 `docs/spec.proposed.md` 並在 `QUESTIONS.md` 開一題，由 user 自己套用
- 預檢（`--project` 不是 git 頂層目錄、symlink、硬連結、目錄、斷掉的 symlink、git hooks 目錄不是目錄、既有設定檔不是可合併的 JSON）有問題時中止，結束碼 3，不寫任何東西
- 裝完告訴 user：Codex 要開 `/hooks` 核准這些 hook 才會執行（專案未受信任、hook 定義變動、`codex exec` 非互動、管理員關閉時會靜默失效，見 README〈Codex 端：裝了不一定生效〉）；Claude Code 要接受專案信任對話框。hook 只是護欄，兩邊逾時或出錯時工具都會照常執行；Codex 端行為未經實機驗證。

## 完成後回報

- `AGENTS.md`、`CLAUDE.md` 各自有沒有留 `.bak`（含 `.bak.N`）；`CLAUDE.md` 是補行，還是整份換成兩行；腳本「注意」行列出的其他匯入檔（原文轉給 user，請 user 手動移除其中的舊規則全文）
- 版本戳的舊值與新值
- 哪些新建、哪些已存在、哪些被覆寫
- 步驟 2、3 各項填了什麼，有沒有開成 `QUESTIONS.md` 的題
- 步驟 4：哪些行搬到哪、哪些授權行沒搬、`git diff docs/procedures/` 找回了什麼、`.bak` 可以刪
- **建立或修改的檔案裡，有哪些命中 `.gitignore`**
