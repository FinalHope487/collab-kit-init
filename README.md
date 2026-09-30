# collab-kit-init

一個 [Claude Code Skill](https://docs.claude.com/en/docs/claude-code/skills)：在專案根目錄初始化一整套人機協作規則與骨架。

手動觸發,唯讀偵測後寫入,**缺什麼建什麼、已存在的內容一律不覆蓋**。
其他專案、其他 session 不載入、不佔 token。

## 它會建立什麼

| 檔案 | 作用 |
|---|---|
| 規則檔 | `CLAUDE.md`;`CLAUDE.md` 若以單獨一行 `@<相對路徑>` 匯入別的檔(例 `@AGENTS.md`),就寫進被匯入的檔,`CLAUDE.md` 不動。內容是一句開頭句(用規則檔的主要語言回答)加八個一級標題的規則全文:決策分級、提問機制、工作模式、留痕與收尾、驗證:不接受目測、撰寫文件、累積型檔案觸發規則、委派邊界規格。推送政策(預設開分支開 PR／`--direct-push-main` 直推 main)、服務埠、冷啟動 token 上限於安裝時代入 |
| `QUESTIONS.md` | 需要拍板的事寫這裡,不停下來等。只放「問一次就答得完」的問題,不放選項與已答的題 |
| `SOP.md` | 只放依症狀分流的〈目錄〉,條目內文在 `SOP/<症狀分類>.md` |
| `SOP/README.md` | SOP 寫法:觸發條件、格式、`(日期・工具/模型版本)`、引用 `SOP[檔名]#N` 與每檔各自從 1 起算的編號、退場與 `SOP/已退役.md` |
| `ROADMAP.md` | 五個標記、四欄待辦格式(具體細節/怎麼做/會改變什麼/做後回退代價),節:〈硬約束〉〈基線〉〈待辦項目〉〈範圍〉。決策不放這裡 |
| `docs/decisions/README.md` | 決策寫法:一條決策一個檔,檔名 `YYYY-MM-DD-<slug>.md`,每檔 ≤30 行,含決策/依據/反悔成本。只放問過 user 的決策 |
| `docs/environment.md` | 外部事實(配額、版本、站點現況),每列附驗證指令與驗證日期,超過 90 天要重驗。腳本不建,需要時從 `assets/environment.md` 複製 |
| `.claude/templates/session-handoff.md` | 跨輪交接摘要模板 |
| `tools/outline.py` | 列出 Python 檔各函式與類別的起訖行號,讀長檔時只讀要動的那一段 |

除了建檔,還會:

- **偵測本專案的三層驗證指令**(內層 / 使用者層 / 真依賴),填進 `CLAUDE.md`。
  偵測不到的那一層不留白、不拿內層測試充數,改開成 `QUESTIONS.md` 的題目
- **改掉既有章節裡與新規則矛盾的舊措辭**(步驟 1b)——沒有這步,升級過的專案會同時寫著兩套打架的說法

## 檔案結構

```
skills/collab-kit-init/
├── SKILL.md                        安裝步驟(觸發時才載入的只有這一份)
├── scripts/install.sh              實際寫檔的腳本:判斷規則檔、逐節附加、缺檔才建
├── assets/claude-md-rules.md       要寫進規則檔的開頭句與八節規則全文(含安裝時代入的佔位字串)
├── assets/push-policy-pr.md        ┐ 推送政策兩版,依 --direct-push-main 只代入其中一版
├── assets/push-policy-direct.md    ┘
├── assets/QUESTIONS.md             ┐
├── assets/SOP.md                   │
├── assets/SOP-README.md            │ 原樣複製進專案的模板
├── assets/ROADMAP.md               │ (SOP-README.md → SOP/README.md、
├── assets/decisions-README.md      │  decisions-README.md → docs/decisions/README.md、
├── assets/session-handoff.md       │  outline.py → tools/outline.py)
├── assets/outline.py               ┘
├── assets/environment.md           需要時手動複製成 docs/environment.md
└── references/upgrade-existing.md  升級舊版 kit 時要改掉的舊措辭
```

規則全文與模板放在 `assets/`,是為了讓安裝時直接複製檔案而不是憑記憶重打——重打就是內容漂移的來源。

## 實測

4 個固定任務 × 3 次 = 12 run,每輪由獨立第三方覆核(自己跑測試、自己看 diff、手打 CLI,
對「這條測試釘住了 X」的宣稱一律做 mutation check)。結果 11 PASS / 1 FAIL,人工介入 0、假完成 0。

## 安裝

複製 `skills/collab-kit-init/` 整個目錄(含 `assets/` 與 `references/`)到目標專案的
`.claude/skills/` 或 `skills/` 下,再手動觸發這個 skill。
完整規則見 [`skills/collab-kit-init/SKILL.md`](skills/collab-kit-init/SKILL.md)。
