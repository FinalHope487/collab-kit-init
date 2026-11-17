# 現況

最後更新：<日期>。只寫現在生效的事。理由與沿革在 git 與 `DECISIONS.md`。上限 6 KiB。

## 目標

- 產品：<一句話>
- 現階段：<這個階段要交出什麼>
- 只有 user 能驗收。

## 生效中的契約

| 契約 | 內容 |
|---|---|

公開契約與驗收條件在 `docs/spec.md`。

## 下一步

- <下一個動作；跨輪計畫連到 `docs/plans/`>

## 停損訊號

| 訊號 | 動作 |
|---|---|
| 這一輪讓原本好的東西變差 | 回退這一輪，不往上疊 |
| 同類問題連續出現、修一處壞一處 | 停手，重新審視那個契約 |

## 檔案地圖

「人」＝user 會讀也可能改，用中文自然語言寫。「agent」＝只有 agent 讀，用結構化寫法。

| 檔案 | 讀者 | 何時讀 |
|---|---|---|
| `AGENTS.md`、`STATE.md` | 人、agent | 每次開工自動載入 |
| `DECISIONS.md` | 人、agent | 對某個決定有疑問時 |
| `ROADMAP.md`、`ROADMAP/` | 人、agent | 選工作時 |
| `QUESTIONS.md` | 人、agent | 有待決問題時 |
| `docs/spec.md`、`docs/plans/` | 人、agent | 動到公開契約或接手跨輪計畫時 |
| `docs/procedures/` | agent | `AGENTS.md`〈程序〉的觸發條件成立時 |
| `docs/project-rules.md`、`docs/testing.md`、`docs/codex-collaboration.md` | agent | 要跑驗證、審查或委派時 |

## 測試

<入口指令>
