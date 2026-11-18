#!/usr/bin/env bash
# install.sh 的驗收：對暫存目錄真跑腳本，斷言建出的檔案與內容。
# 用法: bash tests/test_install.sh
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$KIT/skills/collab-kit-init/scripts/install.sh"
ASSETS="$KIT/skills/collab-kit-init/assets"
RULES_SRC="$ASSETS/claude-md-rules.md"

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
same() { cmp -s <(tr -d '\r' < "$1") <(tr -d '\r' < "$2"); }
TWO_IMPORTS="$(printf '@AGENTS.md\n@STATE.md')"
claude_is_two_imports() { [ "$(tr -d '\r' < "$1/CLAUDE.md")" = "$TWO_IMPORTS" ]; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 安裝後要存在的檔
FILES=(
  CLAUDE.md AGENTS.md STATE.md DECISIONS.md QUESTIONS.md
  ROADMAP.md ROADMAP/later.md ROADMAP/parked.md
  docs/spec.md docs/plans/README.md
  docs/project-rules.md docs/testing.md docs/cold-review.md
  tools/outline.py .collab-kit-version
)

echo "== 全新專案 =="
P="$WORK/fresh"; mkdir -p "$P"; git -C "$P" init -q
bash "$INSTALL" --project "$P" > "$WORK/fresh.out" 2>&1; RC=$?
check "腳本結束碼 0" "[ $RC -eq 0 ]"
for f in "${FILES[@]}"; do check "建立 $f" "[ -f \"\$P/$f\" ]"; done
for src in "$ASSETS"/procedures/*.md; do
  n="$(basename "$src")"
  check "docs/procedures/$n 逐字等於 assets" "same \"\$P/docs/procedures/$n\" \"$src\""
done
check "規則檔 AGENTS.md 逐字等於 assets 規則全文" "same \"\$P/AGENTS.md\" \"\$RULES_SRC\""
check "CLAUDE.md 只有 @AGENTS.md 與 @STATE.md 兩行" "claude_is_two_imports \"\$P\""
check "版本戳是 12 位十六進位" "grep -qxE '[0-9a-f]{12}' \"\$P/.collab-kit-version\""
check "project-rules.md 只有開頭註解" \
  "[ -z \"\$(awk '/<!--/{c=1} !c && NF{print} /-->/{c=0}' \"\$P/docs/project-rules.md\")\" ] && grep -q '<!--' \"\$P/docs/project-rules.md\""

# kit 裝進專案的每個 Markdown 檔，引用到的路徑都要存在。
# 例外：用到才建的檔，與規則裡當作檔名家族提到的字。
ALLOW='^(docs/troubleshooting\.md|docs/environment\.md|docs/specs/.*|docs/plans/.+|\.github/.*|archive/)$'
missing=""
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  [ -e "$P/$ref" ] || missing="$missing $ref"
done < <(cd "$P" && cat CLAUDE.md AGENTS.md STATE.md DECISIONS.md QUESTIONS.md ROADMAP.md \
           docs/procedures/*.md docs/plans/README.md docs/testing.md docs/cold-review.md \
         | tr -d '\r' | grep -oE '`[^` <>]+`' | tr -d '`' \
         | grep -E '(/|\.(md|json|jsonl|py)$)' | grep -vE '^(cd |-|git|npm|node|https?:)' \
         | grep -vE '[*$]|…|／' | sed -E 's/[#:].*$//' | grep -vE "$ALLOW" | sort -u)
check "裝進專案的文件引用的檔案全部存在（缺:${missing:- 無}）" "[ -z \"\$missing\" ]"

echo "== 既有規則檔（CLAUDE.md 以 @AGENTS.md 匯入舊版）與既有檔 =="
P="$WORK/old"; mkdir -p "$P/docs/procedures"; git -C "$P" init -q
printf '@AGENTS.md\n' > "$P/CLAUDE.md"
printf '# 舊規則\n\n舊內容\n' > "$P/AGENTS.md"
printf '# 待決問題\n\n## Q1 · 既有的題\n' > "$P/QUESTIONS.md"
printf '# 現況\n\n專案自己寫的現況\n' > "$P/STATE.md"
printf '被專案改過的程序\n' > "$P/docs/procedures/questions.md"
printf '000000000000\n' > "$P/.collab-kit-version"
cp "$P/QUESTIONS.md" "$WORK/questions.orig"
cp "$P/STATE.md" "$WORK/state.orig"
bash "$INSTALL" --project "$P" > "$WORK/old.out" 2>&1
check "AGENTS.md 換成新版全文" "same \"\$P/AGENTS.md\" \"\$RULES_SRC\""
check "舊 AGENTS.md 留在 AGENTS.md.bak" "grep -q '舊內容' \"\$P/AGENTS.md.bak\""
check "CLAUDE.md 保留 @AGENTS.md 並補上 @STATE.md" "claude_is_two_imports \"\$P\""
check "既有 QUESTIONS.md 不覆蓋" "cmp -s \"\$P/QUESTIONS.md\" \"\$WORK/questions.orig\""
check "既有 STATE.md 不覆蓋" "cmp -s \"\$P/STATE.md\" \"\$WORK/state.orig\""
check "docs/procedures/ 被 kit 版覆寫" "same \"\$P/docs/procedures/questions.md\" \"\$ASSETS/procedures/questions.md\""
check "版本戳從舊值換成新值" "! grep -qx '000000000000' \"\$P/.collab-kit-version\""
check "回報印出版本變動" "grep -q '000000000000 → ' \"\$WORK/old.out\""

echo "== 重跑 =="
rm -f "$P/AGENTS.md.bak"
cp "$P/CLAUDE.md" "$WORK/claude.after"
bash "$INSTALL" --project "$P" > "$WORK/rerun.out" 2>&1
check "規則檔已是新版時不產生 .bak" "[ ! -e \"\$P/AGENTS.md.bak\" ]"
check "重跑不再往 CLAUDE.md 加行" "cmp -s \"\$P/CLAUDE.md\" \"\$WORK/claude.after\""
check "重跑回報版本未變" "grep -q '未變' \"\$WORK/rerun.out\""

echo "== 既有 CLAUDE.md 沒有 @ 匯入（規則直接寫在裡面） =="
P="$WORK/inline"; mkdir -p "$P"; git -C "$P" init -q
printf '# 我的規則\n\n直接寫在 CLAUDE.md\n' > "$P/CLAUDE.md"
bash "$INSTALL" --project "$P" > "$WORK/inline.out" 2>&1
check "舊 CLAUDE.md 留在 CLAUDE.md.bak" "grep -q '直接寫在 CLAUDE.md' \"\$P/CLAUDE.md.bak\""
check "CLAUDE.md 換成兩行匯入" "claude_is_two_imports \"\$P\""
check "規則寫進 AGENTS.md" "same \"\$P/AGENTS.md\" \"\$RULES_SRC\""

echo "== CLAUDE.md 另外匯入其他檔（團隊規則、個人檔） =="
P="$WORK/other"; mkdir -p "$P/docs"; git -C "$P" init -q
printf '# 團隊規則\n\n團隊自己的內容\n' > "$P/docs/team-rules.md"
printf '前言\n@docs/team-rules.md\n@~/personal.md\n' > "$P/CLAUDE.md"
cp "$P/docs/team-rules.md" "$WORK/team.orig"
bash "$INSTALL" --project "$P" > "$WORK/other.out" 2>&1
check "規則一律寫進 AGENTS.md" "same \"\$P/AGENTS.md\" \"\$RULES_SRC\""
check "被匯入的團隊規則檔原封不動" "cmp -s \"\$P/docs/team-rules.md\" \"\$WORK/team.orig\""
check "CLAUDE.md 保留原有匯入" "grep -qx '@docs/team-rules.md' \"\$P/CLAUDE.md\" && grep -qx '@~/personal.md' \"\$P/CLAUDE.md\""
check "CLAUDE.md 補上 @AGENTS.md 與 @STATE.md" "grep -qx '@AGENTS.md' \"\$P/CLAUDE.md\" && grep -qx '@STATE.md' \"\$P/CLAUDE.md\""
check "CLAUDE.md 不產生 .bak（內容沒被取代）" "[ ! -e \"\$P/CLAUDE.md.bak\" ]"
check "回報提醒另外匯入的檔" "grep -q 'docs/team-rules.md' \"\$WORK/other.out\" && grep -q '手動移除' \"\$WORK/other.out\""
cp "$P/CLAUDE.md" "$WORK/other.claude"
bash "$INSTALL" --project "$P" > "$WORK/other2.out" 2>&1
check "重跑不再往 CLAUDE.md 加行" "cmp -s \"\$P/CLAUDE.md\" \"\$WORK/other.claude\""

echo "== 匯入判斷：fence、註解、行尾空白、./ 前綴 =="
P="$WORK/fence"; mkdir -p "$P"; git -C "$P" init -q
printf '```\n@AGENTS.md\n@STATE.md\n```\n@docs/x.md\n' > "$P/CLAUDE.md"
bash "$INSTALL" --project "$P" > "$WORK/fence.out" 2>&1
check "fence 裡的匯入不算數：補上 @AGENTS.md 與 @STATE.md" "[ \"\$(tail -n 2 \"\$P/CLAUDE.md\")\" = \"\$TWO_IMPORTS\" ]"
P="$WORK/cmt"; mkdir -p "$P"; git -C "$P" init -q
printf '<!--\n@AGENTS.md\n-->\n@docs/x.md\n' > "$P/CLAUDE.md"
bash "$INSTALL" --project "$P" > "$WORK/cmt.out" 2>&1
check "HTML 註解裡的匯入不算數" "[ \"\$(tail -n 2 \"\$P/CLAUDE.md\")\" = \"\$TWO_IMPORTS\" ]"
P="$WORK/trail"; mkdir -p "$P"; git -C "$P" init -q
printf '@AGENTS.md  \n@docs/x.md\n' > "$P/CLAUDE.md"
bash "$INSTALL" --project "$P" > "$WORK/trail.out" 2>&1
check "行尾空白的 @AGENTS.md 不重複加行" "[ \"\$(grep -c '^@AGENTS\\.md' \"\$P/CLAUDE.md\")\" = 1 ]"
P="$WORK/dot"; mkdir -p "$P"; git -C "$P" init -q
printf '@./AGENTS.md\n' > "$P/CLAUDE.md"
bash "$INSTALL" --project "$P" > "$WORK/dot.out" 2>&1
check "@./AGENTS.md 視為 @AGENTS.md，不重複加行" "[ \"\$(grep -c 'AGENTS\\.md' \"\$P/CLAUDE.md\")\" = 1 ]"
check "@./AGENTS.md 不被當成『另外匯入』提醒" "! grep -q '另外匯入' \"\$WORK/dot.out\""

echo "== symlink 與既有 .bak：不得遺失使用者檔案 =="
P="$WORK/sym"; mkdir -p "$P"; git -C "$P" init -q
printf '# my rules\nkeep me\n' > "$P/AGENTS.md"
ln -s AGENTS.md "$P/CLAUDE.md"
bash "$INSTALL" --project "$P" > "$WORK/sym.out" 2>&1; RC=$?
check "CLAUDE.md 是 symlink 時結束碼 3" "[ $RC -eq 3 ]"
check "symlink 情況不寫入任何東西（AGENTS.md 原樣、無 STATE.md）" "grep -q 'keep me' \"\$P/AGENTS.md\" && [ ! -e \"\$P/STATE.md\" ] && [ ! -e \"\$P/AGENTS.md.bak\" ]"
bash "$INSTALL" --project "$P" --dry-run > "$WORK/sym2.out" 2>&1; RC=$?
check "symlink 情況 --dry-run 也中止" "[ $RC -eq 3 ]"
P="$WORK/bak"; mkdir -p "$P"; git -C "$P" init -q
printf 'v1\n' > "$P/AGENTS.md"
bash "$INSTALL" --project "$P" > "$WORK/bak1.out" 2>&1
printf 'v2\n' > "$P/AGENTS.md"
bash "$INSTALL" --project "$P" > "$WORK/bak2.out" 2>&1
check "既有 AGENTS.md.bak 不被覆寫（仍是 v1）" "grep -qx 'v1' \"\$P/AGENTS.md.bak\""
check "第二份舊檔留成 AGENTS.md.bak.1（v2）" "grep -qx 'v2' \"\$P/AGENTS.md.bak.1\""
P="$WORK/dry2"; mkdir -p "$P"
bash "$INSTALL" --project "$P" --dry-run > "$WORK/dry2.out" 2>&1
check "CLAUDE.md 不存在時 --dry-run 印『待建立』" "grep -q '待建立 CLAUDE.md' \"\$WORK/dry2.out\""

echo "== --dry-run =="
P="$WORK/dry"; mkdir -p "$P"
bash "$INSTALL" --project "$P" --dry-run > "$WORK/dry.out" 2>&1
check "--dry-run 不寫任何檔" "[ -z \"\$(ls -A \"\$P\")\" ]"

echo "== kit 本體不依賴外部工具與私人專案 =="
ext="$(grep -rilE 'chatgpt|codex|sonnet|calculus-visualizer|dreamcore' "$KIT/skills" 2>/dev/null | tr '\n' ' ')"
check "skills/ 不提指名工具或私人專案名（命中:${ext:- 無}）" "[ -z \"\$ext\" ]"
priv="$(grep -ilE 'calculus-visualizer|dreamcore|HANDOFF' "$KIT/README.md" 2>/dev/null)"
check "README 不提私人專案名或已刪的 HANDOFF" "[ -z \"\$priv\" ]"
plat="$(grep -rilE 'AskUserQuestion|subagent' "$ASSETS" "$KIT/skills/collab-kit-init/SKILL.md" 2>/dev/null | tr '\n' ' ')"
check "assets 與 SKILL.md 不含單一平台專有詞（命中:${plat:- 無}）" "[ -z \"\$plat\" ]"
check "規則檔開工先讀 STATE.md" "grep -q '開工先讀 \`STATE.md\`' \"\$RULES_SRC\""
auto="$(grep -rlE '每次開工自動載入|只自動載入|已自動載入，照它做' "$ASSETS" "$KIT/README.md" 2>/dev/null | tr '\n' ' ')"
check "沒有文件假設 STATE.md 一定自動載入（命中:${auto:- 無}）" "[ -z \"\$auto\" ]"
check "冷審查有不依賴外部工具的備援（未經獨立審查）" "grep -q '未經獨立審查' \"\$ASSETS/cold-review.md\""
check "規則檔不含 push main 永遠／一律放行" "! grep -qE 'push \`?main\`? *(永遠|一律)放行' \"\$RULES_SRC\""
check "規則檔規定授權只來自 user 明示" "grep -q '授權只來自 user 明示' \"\$RULES_SRC\""
check "SKILL.md 規定授權類內容不從 .bak 搬" "grep -q '授權類內容.*一律不搬' \"\$KIT/skills/collab-kit-init/SKILL.md\""
check "force push 只有一種說法（不再寫「不得 force push」）" "! grep -rq '不得 force push' \"\$ASSETS\""
check "規則檔禁止未經 user 要求開新 session" "grep -q '開新 session，或傳訊給其他現存 session' \"\$RULES_SRC\""
check "冷審查不再以新 session 當審查者" "! grep -q '或新 session' \"\$ASSETS/cold-review.md\""
check "SKILL.md 步驟 4 含 git diff docs/procedures/ 找回步驟" "grep -q 'git diff docs/procedures/' \"\$KIT/skills/collab-kit-init/SKILL.md\""
check "close-round.md 不引用不存在的〈待 user 執行〉" "! grep -rq '待 user 執行' \"\$ASSETS\""
check "規則檔與程序檔語言規則一致（不寫死中文自然語言）" "! grep -rq '中文自然語言' \"\$ASSETS\""

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
