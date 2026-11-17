# collab-kit-init

一個 [Claude Code Skill](https://docs.claude.com/en/docs/claude-code/skills)：在專案根目錄初始化一整套人機協作規則與骨架。

手動觸發。其他專案、其他 session 不載入、不佔 token。

## 設計

每個檔和每個步驟都要答得出：「誰讀它，讀完會做什麼不一樣的事？」答不出來就不裝。

- **開工只自動載入兩個檔**：規則檔（不隨進度改變的規則）與 `STATE.md`（專案現況）。
- **程序條件成立才讀**：提問、驗證、改資料格式、委派、收尾、雜務各一個檔，規則檔裡只有一張觸發表。
- **一件事只有一個家**：其餘位置用路徑加編號指過去。對 user 的訊息相反，直接寫內容。
- **現行檔只寫生效中的事**：理由與沿革留在 git。
- **kit 的檔與專案的檔分開**：升級只覆寫 kit 的檔。

## 它會建立什麼

kit 擁有，每次安裝整份覆寫：

| 檔案 | 作用 |
|---|---|
| 規則檔 | `CLAUDE.md` 以單獨一行 `@<相對路徑>` 匯入的檔；沒有匯入就是 `AGENTS.md`。內容是 `assets/claude-md-rules.md` 全文。內容不同時舊檔留成 `.bak` |
| `docs/procedures/` | `questions.md`、`verification.md`、`data-format.md`、`delegation.md`、`close-round.md`、`chores.md` |
| `.collab-kit-version` | 規則全文加程序檔的內容雜湊（12 位）。兩個專案的值相同，代表裝的是同一版 |

專案擁有，缺才建，已存在不覆蓋：

| 檔案 | 作用 |
|---|---|
| `CLAUDE.md` | 匯入規則檔與 `STATE.md`。已存在且有匯入時只補一行 `@STATE.md` |
| `STATE.md` | 目標、生效中的契約、下一步、停損訊號、檔案地圖、測試指令。上限 6 KiB |
| `DECISIONS.md` | 一個決定一行：日期、決定、決策者與 user 原話、反悔代價、釘住它的測試 |
| `QUESTIONS.md` | 需要拍板的事寫這裡，不停下來等。只放「問一次就答得完」的問題 |
| `ROADMAP.md`、`ROADMAP/later.md`、`ROADMAP/parked.md` | 未完成的待辦。做完就刪 |
| `docs/spec.md`、`docs/plans/README.md` | 公開契約與驗收；跨輪計畫的寫法 |
| `docs/project-rules.md` | 本專案專屬的目錄、驗證指令、替身、服務埠、工具執行方式，以及專案自己的規則 |
| `docs/testing.md`、`docs/codex-collaboration.md` | 測試分層與推送前驗證；冷審查、救援、授權與額度 |
| `tools/outline.py` | 列出原始碼、`.css`、`.md` 各區塊的起訖行號；讀長檔時只讀要動的那一段 |

用到才建、腳本不建：`docs/troubleshooting.md`（會重複出現的症狀與查法）、`docs/environment.md`（外部事實，從 `assets/environment.md` 複製）、`docs/specs/`（子規格）。

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
├── assets/project-rules.md、testing.md、codex-collaboration.md → docs/
├── assets/outline.py               → tools/outline.py
├── assets/environment.md           需要時手動複製成 docs/environment.md
└── references/upgrade-existing.md  專案已有舊版 kit 檔案時怎麼搬
```

## 改規則的流程

規則全文的來源是 `../dreamcore-explorer/AGENTS.md`，測試會比對兩者逐字相同。

1. 在 kit 改 `assets/claude-md-rules.md` 或 `assets/procedures/`。
2. 跑測試。
3. 對每個要更新的專案重跑 `install.sh`。比對 `.collab-kit-version` 可知哪些專案還沒更新。

不要在專案裡直接改規則檔或 `docs/procedures/`：下次安裝會被覆寫。專案專屬的規則寫進 `docs/project-rules.md`。

## 測試

```bash
bash tests/test_install.sh
```

對暫存目錄真跑 `install.sh`，斷言：該建的檔都建了、不再安裝的檔沒建、規則檔與程序檔逐字等於 assets、
裝進專案的文件引用的路徑全部存在、專案擁有的既有檔不被覆蓋、程序檔與版本戳會被覆寫、重跑不重複加行、`--dry-run` 不寫檔。
規則全文的來源專案（預設 `../dreamcore-explorer/AGENTS.md`，可用 `SOURCE_AGENTS` 指定）存在時，再比對兩者逐字相同。

## 安裝

複製 `skills/collab-kit-init/` 整個目錄（含 `assets/`、`scripts/` 與 `references/`）到目標專案的
`.claude/skills/` 或 `skills/` 下，再手動觸發這個 skill。
完整步驟見 [`skills/collab-kit-init/SKILL.md`](skills/collab-kit-init/SKILL.md)。

未完成的工作與已知缺口見 [`HANDOFF.md`](HANDOFF.md)。
