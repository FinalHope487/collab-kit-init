#!/usr/bin/env bash
# collab-kit-init 的安裝腳本：把 assets/ 的規則與模板寫進專案。
# 規則檔整份換成 assets 規則全文（內容不同時舊檔留成 .bak）；其餘檔案缺就建，已存在不覆蓋。
# 偵測驗證指令、搬移舊內容不在這裡做，由 agent 執行（見 SKILL.md）。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"
RULES_SRC="$ASSETS/claude-md-rules.md"

PROJECT="$PWD"
DRY=0

usage() {
  cat <<'USAGE'
用法: install.sh [--project DIR] [--dry-run]

  --project DIR   專案根目錄（預設：目前工作目錄）
  --dry-run       只印出會做什麼，不寫檔

規則檔：CLAUDE.md 若有單獨一行 `@<相對路徑>` 匯入，規則寫進被匯入的那個檔，CLAUDE.md 不動；
否則寫 CLAUDE.md。規則檔整份換成規則全文；內容不同時舊檔留成 `<規則檔>.bak`。
其餘檔案缺就建，已存在不覆蓋：
  QUESTIONS.md / NOTES.md / SOP.md / SOP/README.md / SOP/已退役.md /
  ROADMAP.md / ROADMAP/later.md / ROADMAP/parked.md / docs/decisions/README.md /
  docs/project-rules.md / .claude/templates/session-handoff.md / handoff.md /
  tools/outline.py / claude-decisions.json / DECISIONS.jsonl
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?--project 需要路徑}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知參數: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -d "$PROJECT" ] || { echo "專案目錄不存在: $PROJECT" >&2; exit 2; }
[ -f "$RULES_SRC" ] || { echo "找不到規則全文: $RULES_SRC" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"

# ---- 規則檔：CLAUDE.md 或它用 @ 匯入的檔 ----
# 只認整行只有 `@<路徑>` 的一層匯入，略過 HTML 註解與 code fence 裡的行；絕對路徑不算。
CLAUDE_MD="$PROJECT/CLAUDE.md"
IMPORT=""
IMPORT_NOTE=""
if [ -f "$CLAUDE_MD" ]; then
  IMPORT="$(awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    incomment { if (index($0, "-->")) incomment = 0; next }
    /^[[:space:]]*<!--/ { if (!index($0, "-->")) incomment = 1; next }
    /^@[^[:space:]]+[[:space:]]*$/ { sub(/^@/, ""); sub(/[[:space:]]+$/, ""); print; exit }
  ' "$CLAUDE_MD")"
  case "$IMPORT" in
    /*|~*|[A-Za-z]:*)
      IMPORT_NOTE="CLAUDE.md 匯入 @$IMPORT 不是相對路徑，不採用"
      IMPORT="" ;;
  esac
fi
if [ -n "$IMPORT" ]; then
  RULES_REL="$IMPORT"
  RULES_WHY="CLAUDE.md 以 @$IMPORT 匯入；CLAUDE.md 不動"
else
  RULES_REL="CLAUDE.md"
  if [ -n "$IMPORT_NOTE" ]; then RULES_WHY="$IMPORT_NOTE"
  elif [ -f "$CLAUDE_MD" ]; then RULES_WHY="CLAUDE.md 沒有 @ 匯入"
  else RULES_WHY="CLAUDE.md 不存在，新建"; fi
fi
RULES_FILE="$PROJECT/$RULES_REL"

REPORT=""
TOUCHED=""
report() { REPORT="${REPORT}$(printf '  %-8s %s' "$1" "$2")
"; }
mark_touched() { TOUCHED="${TOUCHED}$1
"; }
same_text() { cmp -s <(tr -d '\r' < "$1") <(tr -d '\r' < "$2"); }

# ---- 規則檔：整份換成規則全文 ----
if [ -f "$RULES_FILE" ] && same_text "$RULES_FILE" "$RULES_SRC"; then
  report "已是新版" "$RULES_REL"
elif [ "$DRY" -eq 1 ]; then
  if [ -f "$RULES_FILE" ]; then report "待換新" "$RULES_REL（舊檔留成 $RULES_REL.bak）"
  else report "待建立" "$RULES_REL"; fi
else
  mkdir -p "$(dirname "$RULES_FILE")"
  if [ -f "$RULES_FILE" ]; then
    cp "$RULES_FILE" "$RULES_FILE.bak"
    report "換新" "$RULES_REL（舊檔留成 $RULES_REL.bak）"
    mark_touched "$RULES_REL.bak"
  else
    report "建立" "$RULES_REL"
  fi
  cp "$RULES_SRC" "$RULES_FILE"
  mark_touched "$RULES_REL"
fi

# ---- 其餘檔案：缺就建 ----
install_file() {  # $1=asset 檔名  $2=專案相對路徑
  local src="$ASSETS/$1" dest="$PROJECT/$2"
  if [ ! -f "$src" ]; then
    report "缺來源" "$2（找不到 $src）"
    return
  fi
  if [ -f "$dest" ]; then
    report "已存在" "$2"
    return
  fi
  if [ "$DRY" -eq 1 ]; then
    report "待建立" "$2"
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    report "建立" "$2"
  fi
  mark_touched "$2"
}

install_file "QUESTIONS.md"          "QUESTIONS.md"
install_file "NOTES.md"              "NOTES.md"
install_file "SOP.md"                "SOP.md"
install_file "SOP-README.md"         "SOP/README.md"
install_file "SOP-retired.md"        "SOP/已退役.md"
install_file "ROADMAP.md"            "ROADMAP.md"
install_file "ROADMAP-later.md"      "ROADMAP/later.md"
install_file "ROADMAP-parked.md"     "ROADMAP/parked.md"
install_file "decisions-README.md"   "docs/decisions/README.md"
install_file "project-rules.md"      "docs/project-rules.md"
install_file "session-handoff.md"    ".claude/templates/session-handoff.md"
install_file "session-handoff.md"    "handoff.md"
install_file "outline.py"            "tools/outline.py"
install_file "claude-decisions.json" "claude-decisions.json"
install_file "DECISIONS.jsonl"       "DECISIONS.jsonl"

# ---- 回報 ----
echo "專案: $PROJECT"
echo "規則檔: $RULES_REL（$RULES_WHY）"
if [ "$DRY" -eq 1 ]; then echo "（--dry-run：沒有寫入任何東西）"; fi
echo
echo "== 檔案 =="
printf '%s' "$REPORT"
echo
echo "== 命中 .gitignore =="
if git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  hit=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if out="$(git -C "$PROJECT" check-ignore -v -- "$f" 2>/dev/null)"; then
      echo "  $out"
      hit=1
    fi
  done <<< "$TOUCHED"
  if [ "$hit" -eq 0 ]; then echo "  無"; fi
else
  echo "  不是 git repo，跳過"
fi
echo
echo "== 腳本不做、接下來由你做的 =="
echo "  步驟 2：偵測本專案的驗證指令、服務埠等，寫進 docs/project-rules.md"
echo "  步驟 3：規則檔留了 .bak 時，照 references/upgrade-existing.md 把舊檔裡本專案專屬的內容搬進 docs/project-rules.md"
echo "  步驟 4：標「已存在」的檔案要逐項檢查缺件並補上"
