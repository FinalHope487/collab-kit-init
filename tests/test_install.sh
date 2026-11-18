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
  docs/project-rules.md docs/testing.md docs/codex-collaboration.md
  tools/outline.py .collab-kit-version
)
# 不再安裝的檔
GONE=(
  NOTES.md SOP.md SOP/README.md handoff.md claude-decisions.json DECISIONS.jsonl
  docs/decisions/README.md .claude/templates/session-handoff.md
)

echo "== 全新專案 =="
P="$WORK/fresh"; mkdir -p "$P"; git -C "$P" init -q
bash "$INSTALL" --project "$P" > "$WORK/fresh.out" 2>&1; RC=$?
check "腳本結束碼 0" "[ $RC -eq 0 ]"
for f in "${FILES[@]}"; do check "建立 $f" "[ -f \"\$P/$f\" ]"; done
for f in "${GONE[@]}"; do check "不建立 $f" "[ ! -e \"\$P/$f\" ]"; done
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
           docs/procedures/*.md docs/plans/README.md docs/testing.md docs/codex-collaboration.md \
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

echo "== --dry-run =="
P="$WORK/dry"; mkdir -p "$P"
bash "$INSTALL" --project "$P" --dry-run > "$WORK/dry.out" 2>&1
check "--dry-run 不寫任何檔" "[ -z \"\$(ls -A \"\$P\")\" ]"

echo "== 說明文件不提已移除的檔 =="
# SKILL.md 的步驟 4 要點名舊版的專案檔才能偵測，所以只查它有沒有提到已刪的 asset。
stale="$(grep -lE 'NOTES\.md|claude-decisions\.json|DECISIONS\.jsonl' \
  "$KIT/README.md" "$INSTALL" 2>/dev/null | tr '\n' ' ')"
stale="$stale$(grep -lE 'SOP-README|SOP-retired|session-handoff|decisions-README|calculus-visualizer' \
  "$KIT/README.md" "$KIT/skills/collab-kit-init/SKILL.md" "$INSTALL" 2>/dev/null | tr '\n' ' ')"
check "README、SKILL.md、install.sh 不提已移除的檔（命中:${stale:- 無}）" "[ -z \"\$stale\" ]"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
