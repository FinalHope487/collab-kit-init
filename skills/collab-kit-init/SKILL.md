---
name: collab-kit-init
description: 在目前專案初始化或更新「協作規則骨架」——把通用規則整份寫進規則檔（AGENTS.md，或 CLAUDE.md 以 @ 匯入的檔），把條件成立才讀的程序檔寫進 docs/procedures/，並建立專案自己維護的檔：STATE.md、DECISIONS.md、QUESTIONS.md、ROADMAP.md＋ROADMAP/later.md＋ROADMAP/parked.md、docs/spec.md、docs/plans/README.md、docs/project-rules.md、docs/testing.md、docs/cold-review.md、tools/outline.py。user 說「初始化協作規則」「裝 collab kit」「幫這個專案補上 CLAUDE.md 規則」「更新 kit 版本」「建立 QUESTIONS.md 流程」時使用這個 skill；即使 user 只說「幫這個新專案設好我的工作規則」而沒點名 collab-kit，也用它。
disable-model-invocation: true
---

# Collab Kit Init

## 誰擁有哪個檔

| 擁有者 | 檔案 | 安裝與升級時 |
|---|---|---|
| kit | 規則檔（`AGENTS.md`）、`docs/procedures/*.md`、`.collab-kit-version` | 每次整份覆寫。規則檔內容不同時舊檔留成 `.bak`。專案不改這些檔 |
| 專案 | `STATE.md`、`DECISIONS.md`、`QUESTIONS.md`、`ROADMAP.md`、`ROADMAP/`、`docs/spec.md`、`docs/plans/`、`docs/project-rules.md`、`docs/testing.md`、`docs/cold-review.md`、`tools/outline.py` | 缺才建，已存在不覆蓋 |
| 專案 | `CLAUDE.md` | 只保證它匯入規則檔與 `STATE.md` |

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
| `assets/environment.md` | 腳本不建；專案需要記外部事實時手動複製成 `docs/environment.md` |

規則全文與模板一律由 `scripts/install.sh` 複製，不要自己寫入、也不要憑記憶重打。

## 步驟 1：跑腳本

```bash
bash <本 skill 目錄>/scripts/install.sh --project <專案根目錄> [--dry-run]
```

- `CLAUDE.md` 有單獨一行 `@<相對路徑>` 匯入（只看一層）時，規則寫進被匯入的那個檔，`CLAUDE.md` 只補一行 `@STATE.md`
- 否則規則寫進 `AGENTS.md`，`CLAUDE.md` 換成 `@AGENTS.md` 與 `@STATE.md` 兩行，舊檔留成 `CLAUDE.md.bak`
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

## 步驟 4：處理 `.bak`

規則檔或 `CLAUDE.md` 留了 `.bak` 時，把 `.bak` 裡屬於本專案的內容搬進 `docs/project-rules.md`（目錄、指令、專案專屬規則），通用規則不搬。搬完告訴 user 哪些行搬到哪、`.bak` 可以刪。不自己刪 `.bak`。

## 完成後回報

- 規則檔是哪一個，有沒有留 `.bak`
- 版本戳的舊值與新值
- 哪些新建、哪些已存在、哪些被覆寫
- 步驟 2、3 各項填了什麼，有沒有開成 `QUESTIONS.md` 的題
- 步驟 4 搬了什麼
- **建立或修改的檔案裡，有哪些命中 `.gitignore`**
