<!-- 推送政策：開功能分支＋PR（預設）。scripts/install.sh 沒給 --direct-push-main 時，
     把下面每個 slot 代入規則全文裡同名的 {PUSH_POLICY:<名稱>} 那一行。另一版見 push-policy-direct.md。 -->

<!-- slot: TIER_MEDIUM -->

<!-- slot: TIER_NOTE -->
> 不確定某個動作是否不可逆、或是否影響 `main`／production／既有資料時，視為高風險。
> 其餘不確定照〈工作模式〉的判準走：正確做法不會因未決問題而改變，就去做。
> 專案若已有 PreToolUse hook 擋 push main，在這裡點名它；沒有就維持「待補」。

<!-- slot: CLOSING -->
4. 開功能分支、push 它、開 PR 進 `main`。互不依賴的 PR 連續開，不要停。
   **絕不 push `main`／`master`**。工作已經 commit 在 `main` 上才想起這條時：
   `git checkout -b <分支>` 再 `git branch -f main origin/main`，不要用 `git reset --hard`
   - **commit 在自己開的功能分支上，不要留在共用的工作分支**
