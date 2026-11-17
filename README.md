# collab-kit-init

一個 [Claude Code Skill](https://docs.claude.com/en/docs/claude-code/skills)：在專案根目錄初始化一整套人機協作規則與骨架。

手動觸發。規則檔整份換成規則全文（內容不同時舊檔留成 `.bak`）；其餘檔案缺什麼建什麼，已存在的不覆蓋。
其他專案、其他 session 不載入、不佔 token。

## 它會建立什麼

| 檔案 | 作用 |
|---|---|
| 規則檔 | `CLAUDE.md`；`CLAUDE.md` 若以單獨一行 `@<相對路徑>` 匯入別的檔（例 `@AGENTS.md`），就寫進被匯入的檔，`CLAUDE.md` 不動。內容是 `assets/claude-md-rules.md` 全文，不含任何專案專屬內容 |
| `docs/project-rules.md` | 本專案專屬的目錄、驗證指令、替身、服務埠、工具執行方式。腳本只建開頭註解，由 agent 偵測後填入 |
| `QUESTIONS.md` | 需要拍板的事寫這裡，不停下來等。只放「問一次就答得完」的問題 |
| `NOTES.md` | 開發者記錄實際使用時遇到的問題；處理完就刪條目 |
| `SOP.md` | 只放依症狀分流的〈目錄〉，條目內文在 `SOP/<症狀分類>.md` |
| `SOP/README.md` | SOP 寫法：觸發條件、格式、引用 `SOP[檔名]#N`、退場 |
| `SOP/已退役.md` | 退場的 SOP 條目 |
| `ROADMAP.md`、`ROADMAP/later.md`、`ROADMAP/parked.md` | 標記、四欄待辦格式、〈硬約束〉〈基線〉〈待辦項目〉 |
| `docs/decisions/README.md` | 決策寫法：一條決策一個檔，`YYYY-MM-DD-<slug>.md` |
| `.claude/templates/session-handoff.md`、`handoff.md` | 交接摘要模板，與夜間時段寫入的交接檔 |
| `tools/outline.py` | 列出原始碼、`.css`、`.md` 各區塊的起訖行號；讀長檔時只讀要動的那一段 |
| `claude-decisions.json`、`DECISIONS.jsonl` | 決策記錄檔（`[]` 與空檔），由 hook 寫入 |

`docs/environment.md`（外部事實）腳本不建，需要時從 `assets/environment.md` 複製。

## 檔案結構

```
skills/collab-kit-init/
├── SKILL.md                        安裝步驟（觸發時才載入的只有這一份）
├── scripts/install.sh              實際寫檔的腳本：判斷規則檔、整份寫入、缺檔才建
├── assets/claude-md-rules.md       規則全文
├── assets/project-rules.md         → docs/project-rules.md
├── assets/QUESTIONS.md、NOTES.md、SOP.md、ROADMAP.md
├── assets/SOP-README.md            → SOP/README.md
├── assets/SOP-retired.md           → SOP/已退役.md
├── assets/ROADMAP-later.md         → ROADMAP/later.md
├── assets/ROADMAP-parked.md        → ROADMAP/parked.md
├── assets/decisions-README.md      → docs/decisions/README.md
├── assets/session-handoff.md       → .claude/templates/session-handoff.md 與 handoff.md
├── assets/outline.py               → tools/outline.py
├── assets/claude-decisions.json、DECISIONS.jsonl
├── assets/environment.md           需要時手動複製成 docs/environment.md
└── references/upgrade-existing.md  規則檔留了 .bak 或已有舊版 kit 檔案時怎麼搬
```

## 測試

```bash
bash tests/test_install.sh
```

對暫存目錄真跑 `install.sh`，斷言每個檔都建了、規則檔逐字等於規則全文、規則全文引用的檔案全部存在、
既有檔不被覆蓋、`--dry-run` 不寫檔。規則全文的來源專案（預設 `../calculus-visualizer/AGENTS.md`，
可用 `SOURCE_AGENTS` 指定）存在時，再比對兩者逐字相同。

## 安裝

複製 `skills/collab-kit-init/` 整個目錄（含 `assets/` 與 `references/`）到目標專案的
`.claude/skills/` 或 `skills/` 下，再手動觸發這個 skill。
完整步驟見 [`skills/collab-kit-init/SKILL.md`](skills/collab-kit-init/SKILL.md)。
