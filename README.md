# collab-kit-init

一個 [Claude Code Skill](https://docs.claude.com/en/docs/claude-code/skills)：在專案根目錄初始化一整套人機協作規則與骨架。

手動觸發,唯讀偵測後寫入,**缺什麼建什麼、已存在的內容一律不覆蓋**。
其他專案、其他 session 不載入、不佔 token。

## 它會建立什麼

| 檔案 | 作用 |
|---|---|
| `CLAUDE.md` | 八個一級標題的規則全文:決策分級、提問機制、工作模式、留痕與收尾、驗證:不接受目測、撰寫文件、累積型檔案觸發規則、委派邊界規格 |
| `QUESTIONS.md` | 需要拍板的事寫這裡,不停下來等。只放「問一次就答得完」的問題,不放選項與已答的題 |
| `SOP.md` ＋ `SOP/` | 重複問題的處理路徑。`SOP.md` 只放依症狀分流的〈目錄〉,條目內文在 `SOP/<症狀分類>.md`,每檔編號各自從 1 起算,引用寫 `SOP[檔名]#N`。含「退場」與 `SOP/已退役.md`,讓規則能減不只能增 |
| `ROADMAP.md` | 待辦、已拍板的決策、變更紀錄 |
| `.claude/templates/session-handoff.md` | 跨輪交接摘要模板 |

除了建檔,還會:

- **偵測本專案的三層驗證指令**(內層 / 使用者層 / 真依賴),填進 `CLAUDE.md`。
  偵測不到的那一層不留白、不拿內層測試充數,改開成 `QUESTIONS.md` 的題目
- **改掉既有章節裡與新規則矛盾的舊措辭**(步驟 1b)——沒有這步,升級過的專案會同時寫著兩套打架的說法

## 檔案結構

```
skills/collab-kit-init/
├── SKILL.md                        安裝步驟(觸發時才載入的只有這一份)
├── assets/claude-md-rules.md       要附加進 CLAUDE.md 的八節規則全文
├── assets/QUESTIONS.md             ┐
├── assets/SOP.md                   ├ 原樣複製進專案的模板
├── assets/ROADMAP.md               │
├── assets/session-handoff.md       ┘
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
