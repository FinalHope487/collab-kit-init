# 升級：搬舊內容

步驟 3 用。

## 規則檔留了 `.bak`

規則檔已整份換成新版，舊檔在 `<規則檔>.bak`。逐段看 `.bak`：

| 舊檔裡的內容 | 處理 |
|---|---|
| 本專案的驗證指令、服務埠、目錄、替身、專案工具的執行方式 | 搬進 `docs/project-rules.md` |
| 新版規則已涵蓋的通用規則（即使措辭不同） | 丟掉，以新版為準 |
| 本專案專屬、新版沒有的行為規則 | 搬進 `docs/project-rules.md`，並在回報列出，讓 user 決定要不要升成通用規則 |

搬完刪掉 `.bak`。

## 已存在的檔案是舊版 kit 格式

| 檔案 | 舊 | 改成 |
|---|---|---|
| `QUESTIONS.md` | 不符合「問一次就答得完」的條目、已答的題、選項表、註解裡的題目範本 | 決策搬進 `docs/decisions/`、教訓進 `SOP/`、待辦進 `ROADMAP.md`〈待辦項目〉；已答的題與選項表刪掉；開頭換成 `assets/QUESTIONS.md` |
| `SOP.md` | 條目內文、觸發條件、格式、退場寫在 `SOP.md` | `SOP.md` 只留〈目錄〉（每列填「放什麼／不放什麼」）；條目依症狀拆進 `SOP/<症狀分類>.md`，每檔編號從 1 起算，全專案的 `SOP #N` 引用改成 `SOP[檔名]#N`；寫法規則移到 `SOP/README.md` |
| `ROADMAP.md` | 〈已拍板的決策〉〈變更紀錄〉、逐輪〈現況〉、三欄待辦格式 | 決策搬進 `docs/decisions/`（一條一個檔，`YYYY-MM-DD-<slug>.md`）；`[later]`／`[parked]` 條目搬進 `ROADMAP/later.md`、`ROADMAP/parked.md`；〈現況〉只留最新一輪改寫成〈基線〉；待辦改四欄（具體細節／怎麼做／會改變什麼／做後回退代價）；開頭換成 `assets/ROADMAP.md` |
| 決策存放 | `docs/decisions/index.md`、`topics/` | `docs/decisions/<日期>-<slug>.md` 一條一個檔，寫法見 `docs/decisions/README.md` |
| 外部事實（配額、版本、站點現況） | 寫在 `ROADMAP.md` 或規則檔 | 搬進 `docs/environment.md`（從 `assets/environment.md` 複製） |
