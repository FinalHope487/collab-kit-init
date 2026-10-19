---
name: collab-kit-init-free
description: 在專案根目錄初始化不可逆操作防護與精簡協作寫作規範。將不可逆防護條款（付費額度、大型讀入、遺失資料、資安暴露、委派邊界規格、改資料格式）與寫作規範（簡潔祈使句、去除贅詞）寫入專案規則檔（CLAUDE.md 或其引用的規則檔），並建立 QUESTIONS.md、ROADMAP.md、docs/decisions/README.md。
disable-model-invocation: true
---

# Collab Kit Init Free

精簡版人機協作初始化套件：專注於「不可逆防護（額度消耗、資料遺失、資安暴露、委派規格）」以及「高效文字撰寫習慣」。

## 包含資源

| 檔案 | 用途 |
|---|---|
| `scripts/install.sh` | 寫檔腳本，自動偵測規則檔並注入規則全文與基本模板 |
| `assets/claude-md-rules.md` | 不可逆防護與寫作規範全文 |
| `assets/QUESTIONS.md` | 待決問題模板 |
| `assets/ROADMAP.md` | 待辦與基線記錄模板 |
| `assets/decisions-README.md` | 決策紀錄指引模板（→ `docs/decisions/README.md`） |

## 執行安裝

```bash
bash <本 skill 目錄>/scripts/install.sh --project <專案根目錄> [--dry-run]
```

- **規則檔**：若 `CLAUDE.md` 以 `@<相對路徑>` 匯入，寫入該目標檔案且保留 `CLAUDE.md`；否則寫入 `CLAUDE.md`。舊檔自動備份為 `.bak`。
- **模板檔案**：缺檔才建立，已存在則保留不覆蓋。
