---
name: collab-kit-init
description: 在目前專案初始化或升級「協作規則骨架」——把規則全文整份寫進規則檔（CLAUDE.md，或 CLAUDE.md 以 @ 匯入的檔，例如 AGENTS.md），並建立規則引用到的每個檔：QUESTIONS.md、NOTES.md、SOP.md＋SOP/README.md＋SOP/已退役.md、ROADMAP.md＋ROADMAP/later.md＋ROADMAP/parked.md、docs/decisions/README.md、docs/project-rules.md、.claude/templates/session-handoff.md、handoff.md、tools/outline.py、claude-decisions.json、DECISIONS.jsonl。user 說「初始化協作規則」「裝 collab kit」「幫這個專案補上 CLAUDE.md 規則」「升級舊版 kit」「建立 QUESTIONS.md 流程」時使用這個 skill；即使 user 只說「幫這個新專案設好我的工作規則」而沒點名 collab-kit，也用它。
disable-model-invocation: true
---

# Collab Kit Init

## 這個 skill 的資源

| 檔案 | 用途 |
|---|---|
| `scripts/install.sh` | 實際寫檔的腳本。跑它，不要自己一個一個複製 |
| `assets/claude-md-rules.md` | 規則全文，整份寫進規則檔；不含任何專案專屬內容 |
| `assets/project-rules.md` | `docs/project-rules.md` 的模板：只有開頭註解寫明放什麼、不放什麼 |
| `assets/` 其餘檔案 | 腳本原樣複製進專案的模板 |
| `assets/environment.md` | 腳本不建；專案需要記外部事實時手動複製成 `docs/environment.md` |
| `references/upgrade-existing.md` | 步驟 3：規則檔留了 `.bak`、或專案已有舊版 kit 檔案時用 |

規則全文與模板一律由 `scripts/install.sh` 複製，不要自己寫入、也不要憑記憶重打。

## 步驟 1：跑腳本

```bash
bash <本 skill 目錄>/scripts/install.sh --project <專案根目錄> [--dry-run]
```

- **規則檔**＝`CLAUDE.md` 裡有單獨一行 `@<相對路徑>` 匯入（只看一層）時，被匯入的那個檔；沒有就是 `CLAUDE.md`。
  有匯入時 `CLAUDE.md` 不動
- 規則檔整份換成 `assets/claude-md-rules.md`。內容不同時，舊檔留成 `<規則檔>.bak`
- 其餘檔案缺就建，已存在不覆蓋
- `--dry-run` 只印出會做什麼

## 步驟 2：填 `docs/project-rules.md`

這個檔只有開頭註解時，唯讀偵測後寫進去：

- **目錄**：Python 目錄（`pyproject.toml` 所在）、前端目錄
- **驗證指令**：內層（`package.json` 的 `scripts.test`、`pytest.ini`／`pyproject.toml`、`Makefile`、`cargo test`、`go test ./...`）、
  user 層（Playwright、Cypress、WebDriver、對真執行檔跑的整合測試）、真依賴與替身
- **開發服務埠**：推送前要確認沒人佔的埠
- **專案專屬工具**：例如 `tools/outline.py` 在本專案的執行方式

偵測到什麼寫什麼。偵測不到 user 層時不用內層測試填，在 `QUESTIONS.md` 開一題。
確認不適用的層寫「不適用」加理由。測試數字寫進 `ROADMAP.md`〈基線〉，不寫這裡。
需要新增相依套件時只開題，不安裝。

## 步驟 3：搬舊內容

規則檔留了 `.bak`，或腳本標「已存在」的檔案是舊版 kit 格式時，照 `references/upgrade-existing.md` 處理。

## 完成後回報

- 規則檔是哪一個，有沒有留 `.bak`
- 哪些新建、哪些已存在
- 步驟 2 各項偵測到什麼，有沒有開成 `QUESTIONS.md` 的題
- 步驟 3 搬了什麼
- **建立或修改的檔案裡，有哪些命中 `.gitignore`**（`.claude/` 常常整個被忽略）
