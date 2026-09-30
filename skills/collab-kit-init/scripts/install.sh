#!/usr/bin/env bash
# collab-kit-init 的安裝腳本：把 assets/ 的規則與模板寫進專案。
# 缺什麼建什麼，既有檔案與既有章節一律不覆蓋。
# 判斷題不在這裡做：步驟 1b（改舊措辭）、步驟 2（偵測驗證指令）仍由 agent 執行。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"
RULES="$ASSETS/claude-md-rules.md"

PROJECT="$PWD"
WITH_DELEGATION=0
DRY=0

usage() {
  cat <<'USAGE'
用法: install.sh [--project DIR] [--with-delegation] [--dry-run]

  --project DIR       專案根目錄（預設：目前工作目錄）
  --with-delegation   一併安裝〈委派邊界規格〉（專案會用 subagent 才給）
  --dry-run           只印出會做什麼，不寫檔

CLAUDE.md 逐節檢查，缺哪節附加哪節；QUESTIONS.md / SOP.md / ROADMAP.md /
.claude/templates/session-handoff.md 缺就建。既有內容不覆蓋。
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?--project 需要路徑}"; shift 2 ;;
    --with-delegation) WITH_DELEGATION=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知參數: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -d "$PROJECT" ] || { echo "專案目錄不存在: $PROJECT" >&2; exit 2; }
[ -f "$RULES" ] || { echo "找不到規則全文: $RULES" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"
CLAUDE_MD="$PROJECT/CLAUDE.md"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPORT_RULES=""
REPORT_FILES=""
TOUCHED=""
report_rule() { REPORT_RULES="${REPORT_RULES}$(printf '  %-8s %s' "$1" "$2")
"; }
report_file() { REPORT_FILES="${REPORT_FILES}$(printf '  %-8s %s' "$1" "$2")
"; }
mark_touched() { TOUCHED="${TOUCHED}$1
"; }

has_crlf() { [ -f "$1" ] && [ "$(tr -cd '\r' < "$1" | wc -c)" -gt 0 ]; }

# 附加的內容跟著目標檔的行尾走；目標檔還不存在就跟著 assets 走
if [ -f "$CLAUDE_MD" ]; then
  if has_crlf "$CLAUDE_MD"; then EOL=crlf; else EOL=lf; fi
else
  if has_crlf "$RULES"; then EOL=crlf; else EOL=lf; fi
fi
to_eol() { if [ "$EOL" = crlf ]; then sed -e 's/\r*$/\r/'; else sed -e 's/\r*$//'; fi; }

# 規則全文以 `---` 分節，切成每節一檔
awk -v out="$TMP" '
  { sub(/\r$/, "") }
  /^---[[:space:]]*$/ { n++; next }
  { print > sprintf("%s/sec-%02d.md", out, n + 0) }
' "$RULES"

# 去掉頭尾空行
trim() {
  awk '
    { sub(/\r$/, "") }
    NF == 0 && !started { next }
    { started = 1; buf[++n] = $0 }
    END {
      last = n
      while (last > 0 && buf[last] ~ /^[[:space:]]*$/) last--
      for (i = 1; i <= last; i++) print buf[i]
    }
  ' "$1"
}

has_heading() {
  [ -f "$CLAUDE_MD" ] || return 1
  grep -q -E "^# $1[[:space:]]*$" "$CLAUDE_MD"
}

append_section() {
  if [ -s "$CLAUDE_MD" ]; then
    if [ "$(tail -c 1 "$CLAUDE_MD" | wc -l)" -eq 0 ]; then
      printf '\n' | to_eol >> "$CLAUDE_MD"
    fi
    printf '\n---\n\n' | to_eol >> "$CLAUDE_MD"
  fi
  printf '%s\n' "$1" | to_eol >> "$CLAUDE_MD"
}

# 印出該節的 "起始行 下一節起始行"
section_range() {
  local start next
  start="$(grep -n -E "^# $1[[:space:]]*$" "$CLAUDE_MD" | head -1 | cut -d: -f1)"
  [ -n "$start" ] || return 1
  next="$(awk -v s="$start" 'NR > s && /^# / { print NR; exit }' "$CLAUDE_MD")"
  [ -n "$next" ] || next=$(( $(wc -l < "$CLAUDE_MD") + 1 ))
  printf '%s %s\n' "$start" "$next"
}

# ---- 步驟 1：CLAUDE.md 八節 ----
CLAUDE_TOUCHED=0

for sec in "$TMP"/sec-*.md; do
  body="$(trim "$sec")"
  title="$(printf '%s\n' "$body" | grep -m1 -E '^# ' | sed -e 's/^# //' -e 's/[[:space:]]*$//')"
  [ -n "$title" ] || continue

  if [ "$title" = "委派邊界規格" ] && [ "$WITH_DELEGATION" -eq 0 ]; then
    if has_heading "$title"; then
      report_rule "已存在" "# $title"
    else
      report_rule "略過" "# $title（沒給 --with-delegation。確認〈決策分級〉高風險清單有「委派」那一行）"
    fi
    continue
  fi

  if has_heading "$title"; then
    # 這節已存在，但可能缺 QUESTIONS.md 那兩行
    if [ "$title" = "累積型檔案觸發規則" ]; then
      range="$(section_range "$title")"
      s="${range% *}"; e="${range#* }"
      if ! awk -v s="$s" -v e="$e" 'NR > s && NR < e' "$CLAUDE_MD" | grep -q 'QUESTIONS\.md'; then
        printf '%s\n' "$body" | grep -E '^- .*QUESTIONS\.md' > "$TMP/qlines" || true
        if [ -s "$TMP/qlines" ]; then
          if [ "$DRY" -eq 1 ]; then
            report_rule "待補行" "# $title（缺 QUESTIONS.md 那兩行）"
          else
            end="$(awk -v s="$s" -v e="$e" '
              NR >= s && NR < e {
                sub(/\r$/, "")
                if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^---[[:space:]]*$/) next
                last = NR
              }
              END { print last }' "$CLAUDE_MD")"
            {
              head -n "$end" "$CLAUDE_MD"
              to_eol < "$TMP/qlines"
              tail -n +"$((end + 1))" "$CLAUDE_MD"
            } > "$TMP/claude.new"
            cat "$TMP/claude.new" > "$CLAUDE_MD"
            CLAUDE_TOUCHED=1
            report_rule "補行" "# $title（補上 QUESTIONS.md 那兩行）"
          fi
          continue
        fi
      fi
    fi
    report_rule "已存在" "# $title"
    continue
  fi

  if [ "$DRY" -eq 1 ]; then
    report_rule "待附加" "# $title"
    CLAUDE_TOUCHED=1
  else
    append_section "$body"
    CLAUDE_TOUCHED=1
    report_rule "附加" "# $title"
  fi
done

[ "$CLAUDE_TOUCHED" -eq 1 ] && mark_touched "CLAUDE.md"

# ---- 步驟 3~6：其餘檔案 ----
install_file() {  # $1=asset 檔名  $2=專案相對路徑  $3=已存在時的提醒
  local src="$ASSETS/$1" dest="$PROJECT/$2"
  if [ ! -f "$src" ]; then
    report_file "缺來源" "$2（找不到 $src）"
    return
  fi
  if [ -f "$dest" ]; then
    report_file "已存在" "$2${3:+ $3}"
    return
  fi
  if [ "$DRY" -eq 1 ]; then
    report_file "待建立" "$2"
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    report_file "建立" "$2"
  fi
  mark_touched "$2"
}

install_file "QUESTIONS.md"       "QUESTIONS.md"
install_file "SOP.md"             "SOP.md" "→ 逐節檢查：常缺「退場」與「已退役」；每條開頭要有 (日期・工具/模型版本)"
install_file "ROADMAP.md"         "ROADMAP.md"
install_file "session-handoff.md" ".claude/templates/session-handoff.md"

# ---- 回報 ----
echo "專案: $PROJECT"
echo "行尾: $EOL"
if [ "$DRY" -eq 1 ]; then echo "（--dry-run：沒有寫入任何東西）"; fi
echo
echo "== CLAUDE.md 八節 =="
printf '%s' "$REPORT_RULES"
echo
echo "== 檔案 =="
printf '%s' "$REPORT_FILES"
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
echo "  步驟 1b：既有章節裡與新規則打架的舊措辭，照 references/upgrade-existing.md 逐條改"
echo "  步驟 2：偵測三層驗證指令填進〈驗證：不接受目測〉末尾清單；缺的那層開成 QUESTIONS.md 的題目"
echo "  步驟 3~6：標「已存在」的檔案要逐項檢查缺件並補上"
