# 程序：動過檔案之後、收尾與 push

觸發：動過檔案，要 commit 或 push。只讀不寫的工作不套用。
讀者：agent。

## commit

- 驗證綠了就 commit，不攢著。沒綠的不 commit：留在工作目錄，寫進 `ROADMAP.md`〈待辦項目〉標 `[now]`
- commit 一律遵循 Conventional Commits 格式，明確寫出改動範疇與動機。跑過測試就把指令與通過數寫進 commit message
- 一輪拆成多個 commit 時，每個 commit 後看 `git log --stat -1`，確認內容與 message 相符再做下一個；push 前全部確認完。git 指令之間用 `&&` 串接，前一步失敗就停
- 一個 commit 對應一個可單獨回退的決定或一批元件

## 冷審查（只在這一批有程式碼改動時）

一批任務的程式碼改動全部做完、push 前，對整批 diff 做一整輪完整冷審查，冷審查定義為「交給一個全新、不帶先前上下文的審查者審查」，一次的定義為「送出冷審查+取回結果一次」，一整輪完整冷審查的定義為「重複送出冷審查+取回結果多次直到冷審查能夠宣稱『沒有任何直接阻擋後續開發的潛在問題』(「阻擋後續開發」與「建議項」的定義見 docs/cold-review.md〈名詞定義〉)」。以上規定照 `docs/cold-review.md`（審查者的選擇與備援見該檔）；合約＝本輪的交接文件與本輪在 `DECISIONS.md` 新增的行。只動文件或測試的批次不審。報的每一條先對照程式碼確認，真缺陷照 `docs/procedures/verification.md`〈缺陷修復〉先寫重現測試再修

## 紀錄：條件成立才做

| 條件 | 動作 |
|---|---|
| 目標、契約、下一步或停損訊號變了 | 改 `STATE.md` |
| user 做了決定，或 agent 偏離既有規格、推翻已拍板的決定 | `DECISIONS.md` 加一行：日期、決定、user 原話、反悔代價 |
| 有項目做完或新發現 | `ROADMAP.md`：做完的刪掉，新的加上 |
| 有新的不可逆待決問題，或 user 答了題 | 照 `docs/procedures/questions.md` |
| 碰到會重複出現的錯誤或環境坑 | 記到 `docs/troubleshooting.md`（不存在就建） |
| 任務跨多輪 | 寫交接摘要與目前進度 |

沒有條件成立就不寫任何紀錄。不寫 devlog、不寫基線：`git log` 就是紀錄。
整理 `ROADMAP.md`、`QUESTIONS.md` 之類與任務無關的事不在這裡做，見 `docs/procedures/chores.md`。

## push

推到目前分支：`git push origin <目前分支>`。推 `main` 或預設分支前，先看 `docs/project-rules.md` 有沒有明寫放行；沒有就先問 user。force push 屬〈必須先問 user〉，未經同意不執行。推之前：

- 推之前 `git status` 只有自己的改動，確認沒有他人未提交的半成品或衝突
- 只推綠的：
  - **應測範圍**：push 前最多只允許跑跟改動有關的測試，無關的不跑（改到核心公共模組跑改動相關全套但不盲目跑全體測試，若必須跑任意全套測試需要寫明理由）
  - **免寫自動化測試範圍（UI、手感、POC）或純動文件**：確認無破壞既有測試，附本機執行狀態／log 即放行
- `git remote -v` 是空的：不得自行設 remote，把「設 remote 後 push」寫進回報第 4 項〈未做的部分〉
