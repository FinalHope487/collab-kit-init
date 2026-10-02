#!/usr/bin/env bash
# install.sh 的驗收：對暫存目錄真跑腳本，斷言建出的檔案與內容。
# 用法: bash tests/test_install.sh
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$KIT/skills/collab-kit-init/scripts/install.sh"
ASSETS="$KIT/skills/collab-kit-init/assets"
RULES_SRC="$ASSETS/claude-md-rules.md"
# 規則全文的來源專案；不在這台機器上就跳過那一條
SOURCE_AGENTS="${SOURCE_AGENTS:-$KIT/../calculus-visualizer/AGENTS.md}"

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL  $1"; }
skip() { SKIP=$((SKIP + 1)); echo "  skip  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
same() { cmp -s <(tr -d '\r' < "$1") <(tr -d '\r' < "$2"); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FILES=(
  QUESTIONS.md SOP.md SOP/README.md "SOP/已退役.md" ROADMAP.md ROADMAP/later.md ROADMAP/parked.md
  docs/decisions/README.md .claude/templates/session-handoff.md tools/outline.py
  docs/project-rules.md NOTES.md claude-decisions.json DECISIONS.jsonl handoff.md
)

echo "== 全新專案 =="
P="$WORK/fresh"; mkdir -p "$P"; git -C "$P" init -q
bash "$INSTALL" --project "$P" > "$WORK/fresh.out" 2>&1; RC=$?
check "腳本結束碼 0" "[ $RC -eq 0 ]"
for f in "${FILES[@]}"; do check "建立 $f" "[ -f \"\$P/$f\" ]"; done
check "規則檔 CLAUDE.md 逐字等於 assets 規則全文" "same \"\$P/CLAUDE.md\" \"\$RULES_SRC\""
check "claude-decisions.json 是 []" "[ \"\$(tr -d '[:space:]' < \"\$P/claude-decisions.json\")\" = '[]' ]"
check "DECISIONS.jsonl 是空檔" "[ ! -s \"\$P/DECISIONS.jsonl\" ]"
check "handoff.md 是交接模板" "same \"\$P/handoff.md\" \"\$ASSETS/session-handoff.md\""
check "project-rules.md 只有開頭註解" \
  "[ -z \"\$(awk '/<!--/{c=1} !c && NF{print} /-->/{c=0}' \"\$P/docs/project-rules.md\")\" ] && grep -q '<!--' \"\$P/docs/project-rules.md\""

# 規則全文引用到的每個路徑都要存在（git-commit skill 除外）
missing=""
while IFS= read -r ref; do
  [ -e "$P/$ref" ] || missing="$missing $ref"
done < <(tr -d '\r' < "$RULES_SRC" | grep -oE '`[^` <>]+`' | tr -d '`' \
         | grep -E '(/|\.(md|json|jsonl|py)$)' | grep -vE '^(cd |-)' | sort -u)
check "規則全文引用的檔案全部存在（缺:${missing:- 無}）" "[ -z \"\$missing\" ]"

echo "== 既有規則檔（CLAUDE.md 以 @AGENTS.md 匯入舊版）與既有檔 =="
P="$WORK/old"; mkdir -p "$P"; git -C "$P" init -q
printf '@AGENTS.md\n' > "$P/CLAUDE.md"
printf '# 舊規則\n\n舊內容\n' > "$P/AGENTS.md"
printf '# 待決問題\n\n## Q1 · 既有的題\n' > "$P/QUESTIONS.md"
cp "$P/QUESTIONS.md" "$WORK/questions.orig"
bash "$INSTALL" --project "$P" > "$WORK/old.out" 2>&1
check "AGENTS.md 換成新版全文" "same \"\$P/AGENTS.md\" \"\$RULES_SRC\""
check "舊 AGENTS.md 留在 AGENTS.md.bak" "grep -q '舊內容' \"\$P/AGENTS.md.bak\""
check "CLAUDE.md 不動" "[ \"\$(cat \"\$P/CLAUDE.md\")\" = '@AGENTS.md' ]"
check "既有 QUESTIONS.md 不覆蓋" "cmp -s \"\$P/QUESTIONS.md\" \"\$WORK/questions.orig\""

echo "== 重跑 =="
rm -f "$P/AGENTS.md.bak"
bash "$INSTALL" --project "$P" > "$WORK/rerun.out" 2>&1
check "規則檔已是新版時不產生 .bak" "[ ! -e \"\$P/AGENTS.md.bak\" ]"

echo "== --dry-run =="
P="$WORK/dry"; mkdir -p "$P"
bash "$INSTALL" --project "$P" --dry-run > "$WORK/dry.out" 2>&1
check "--dry-run 不寫任何檔" "[ -z \"\$(ls -A \"\$P\")\" ]"

echo "== 與來源專案一致 =="
if [ -f "$SOURCE_AGENTS" ]; then
  check "assets 規則全文逐字等於 $SOURCE_AGENTS" "same \"\$RULES_SRC\" \"\$SOURCE_AGENTS\""
else
  skip "找不到 $SOURCE_AGENTS"
fi

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
