<!-- 推送政策：直推 main。scripts/install.sh 給了 --direct-push-main 時，
     把下面每個 slot 代入規則全文裡同名的 {PUSH_POLICY:<名稱>} 那一行。另一版見 push-policy-pr.md。 -->

<!-- slot: TIER_MEDIUM -->
- **push `main`**——驗證綠了就直接推，不必開分支、不必開 PR。照〈留痕與收尾〉走

<!-- slot: TIER_NOTE -->
> 不確定某個動作是否不可逆、或是否影響 production／既有資料時，視為高風險。
> **push `main` 不在這一句裡**，它是中風險；會改寫遠端歷史的才是高風險。
> 其餘不確定照〈工作模式〉的判準走：正確做法不會因未決問題而改變，就去做。

<!-- slot: CLOSING -->
4. 驗證綠了直接 commit 到 `main` 並 `git push origin main`。不必開分支、不必開 PR
