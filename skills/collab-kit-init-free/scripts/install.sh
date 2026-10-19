#!/usr/bin/env bash
# collab-kit-init-free 的安裝腳本：把 assets/ 的不可逆防護規則與基本模板寫進專案。
# 規則檔整份換成 assets 規則全文（內容不同時舊檔留成 .bak）；其餘檔案缺就建，已存在不覆蓋。
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
  QUESTIONS.md / ROADMAP.md / docs/decisions/README.md
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
install_file() {
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
install_file "ROADMAP.md"            "ROADMAP.md"
install_file "decisions-README.md"   "docs/decisions/README.md"

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
