#!/usr/bin/env bash
# collab-kit-init 的安裝腳本：把 assets/ 的規則與模板寫進專案。
# 缺什麼建什麼，既有檔案與既有章節一律不覆蓋。
# 判斷題不在這裡做：步驟 1b（改舊措辭）、步驟 2（偵測驗證指令）仍由 agent 執行。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"
RULES_SRC="$ASSETS/claude-md-rules.md"

PROJECT="$PWD"
WITH_DELEGATION=0
DIRECT_PUSH=0
SERVICE_PORTS=""
COLD_START_TOKENS=100000
DRY=0

usage() {
  cat <<'USAGE'
用法: install.sh [--project DIR] [--with-delegation] [--direct-push-main]
                 [--service-ports "埠,埠"] [--cold-start-tokens N] [--dry-run]

  --project DIR            專案根目錄（預設：目前工作目錄）
  --with-delegation        一併安裝〈委派邊界規格〉（專案會用 subagent 才給）
  --direct-push-main       推送政策改用「驗證綠了直接推 main」；不給就是「絕不 push main，開分支開 PR」
  --service-ports LIST     專案測試或開發用的服務埠，逗號分隔（例 "8000,5173"）；不給就寫「無」
  --cold-start-tokens N    冷啟動 agent 一次讀入超過多少 token 屬高風險（預設 100000）
  --dry-run                只印出會做什麼，不寫檔

規則檔：CLAUDE.md 若有單獨一行 `@<相對路徑>` 匯入，規則寫進被匯入的那個檔，CLAUDE.md 不動；
否則寫 CLAUDE.md。規則檔逐節檢查，缺哪節附加哪節。
QUESTIONS.md / SOP.md / SOP/README.md / ROADMAP.md / docs/decisions/README.md /
.claude/templates/session-handoff.md / tools/outline.py 缺就建。既有內容不覆蓋。
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?--project 需要路徑}"; shift 2 ;;
    --with-delegation) WITH_DELEGATION=1; shift ;;
    --direct-push-main) DIRECT_PUSH=1; shift ;;
    --service-ports) SERVICE_PORTS="${2?--service-ports 需要清單}"; shift 2 ;;
    --cold-start-tokens) COLD_START_TOKENS="${2:?--cold-start-tokens 需要數字}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知參數: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$COLD_START_TOKENS" in
  ''|*[!0-9]*) echo "--cold-start-tokens 要是正整數: $COLD_START_TOKENS" >&2; exit 2 ;;
esac

if [ "$DIRECT_PUSH" -eq 1 ]; then
  PUSH_SRC="$ASSETS/push-policy-direct.md"; PUSH_LABEL="直推 main（--direct-push-main）"
else
  PUSH_SRC="$ASSETS/push-policy-pr.md"; PUSH_LABEL="絕不 push main，開分支開 PR（預設）"
fi

[ -d "$PROJECT" ] || { echo "專案目錄不存在: $PROJECT" >&2; exit 2; }
[ -f "$RULES_SRC" ] || { echo "找不到規則全文: $RULES_SRC" >&2; exit 2; }
[ -f "$PUSH_SRC" ] || { echo "找不到推送政策模板: $PUSH_SRC" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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
  RULES_FILE="$PROJECT/$IMPORT"
  RULES_WHY="CLAUDE.md 以 @$IMPORT 匯入；CLAUDE.md 不動"
else
  RULES_REL="CLAUDE.md"
  RULES_FILE="$CLAUDE_MD"
  if [ -n "$IMPORT_NOTE" ]; then RULES_WHY="$IMPORT_NOTE"
  elif [ -f "$CLAUDE_MD" ]; then RULES_WHY="CLAUDE.md 沒有 @ 匯入"
  else RULES_WHY="CLAUDE.md 不存在，新建"; fi
fi

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

# 附加的內容跟著規則檔的行尾走；規則檔還不存在就跟著 assets 走
if [ -f "$RULES_FILE" ]; then
  if has_crlf "$RULES_FILE"; then EOL=crlf; else EOL=lf; fi
else
  if has_crlf "$RULES_SRC"; then EOL=crlf; else EOL=lf; fi
fi
to_eol() { if [ "$EOL" = crlf ]; then sed -e 's/\r*$/\r/'; else sed -e 's/\r*$//'; fi; }

# ---- 代入安裝選項 ----
# 推送政策模板以 `<!-- slot: 名稱 -->` 分段，每段代入規則全文裡整行 `{PUSH_POLICY:名稱}` 的位置。
awk -v out="$TMP" '
  { sub(/\r$/, "") }
  /^<!-- slot: [A-Z_]+ -->[[:space:]]*$/ {
    name = $3; file = sprintf("%s/slot-%s.md", out, name); printf "" > file; next
  }
  file != "" { print > file }
' "$PUSH_SRC"

# 服務埠清單："8000, 5173" → `8000`、`5173`；空的寫「無」
PORTS_TEXT="$(printf '%s' "$SERVICE_PORTS" | awk -F',' '{
  out = ""
  for (i = 1; i <= NF; i++) {
    p = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
    if (p == "") continue
    out = out (out == "" ? "" : "、") "`" p "`"
  }
  printf "%s", out
}')"
[ -n "$PORTS_TEXT" ] || PORTS_TEXT="無"

awk -v slots="$TMP" -v ports="$PORTS_TEXT" -v tokens="$COLD_START_TOKENS" '
  function trimmed(file,   n, i, first, last, buf, line) {
    n = 0
    while ((getline line < file) > 0) buf[++n] = line
    close(file)
    first = 1; while (first <= n && buf[first] ~ /^[[:space:]]*$/) first++
    last = n;  while (last >= first && buf[last] ~ /^[[:space:]]*$/) last--
    for (i = first; i <= last; i++) print buf[i]
  }
  function literal(s) { gsub(/[\\&]/, "\\\\&", s); return s }
  BEGIN { ports = literal(ports) }
  { sub(/\r$/, "") }
  /^\{PUSH_POLICY:[A-Z_]+\}[[:space:]]*$/ {
    name = $0; sub(/^\{PUSH_POLICY:/, "", name); sub(/\}.*$/, "", name)
    file = slots "/slot-" name ".md"
    if ((getline probe < file) < 0) { print "缺推送政策 slot: " name > "/dev/stderr"; exit 3 }
    close(file)
    trimmed(file)
    next
  }
  {
    gsub(/\{COLD_START_TOKENS\}/, tokens)
    gsub(/\{SERVICE_PORTS\}/, ports)
    print
  }
' "$RULES_SRC" > "$TMP/rules.md"

if grep -q -E '\{(PUSH_POLICY:[A-Z_]+|COLD_START_TOKENS|SERVICE_PORTS)\}' "$TMP/rules.md"; then
  echo "規則全文還有沒代入的佔位字串：" >&2
  grep -n -E '\{(PUSH_POLICY:[A-Z_]+|COLD_START_TOKENS|SERVICE_PORTS)\}' "$TMP/rules.md" >&2
  exit 3
fi

# 第一個一級標題之前的文字是開頭句（不屬於八節）；其後以 `---` 分節，切成每節一檔
awk -v out="$TMP" '
  !started && /^# / { started = 1 }
  !started { print > (out "/preamble.md"); next }
  /^---[[:space:]]*$/ { n++; next }
  { print > sprintf("%s/sec-%02d.md", out, n + 0) }
' "$TMP/rules.md"

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
  [ -f "$RULES_FILE" ] || return 1
  grep -q -E "^# $1[[:space:]]*$" "$RULES_FILE"
}

append_section() {
  if [ -s "$RULES_FILE" ]; then
    if [ "$(tail -c 1 "$RULES_FILE" | wc -l)" -eq 0 ]; then
      printf '\n' | to_eol >> "$RULES_FILE"
    fi
    if [ "$FRESH" -eq 1 ]; then
      printf '\n' | to_eol >> "$RULES_FILE"
    else
      printf '\n---\n\n' | to_eol >> "$RULES_FILE"
    fi
  fi
  FRESH=0
  printf '%s\n' "$1" | to_eol >> "$RULES_FILE"
}

# ---- 步驟 1：規則檔開頭句與八節 ----
RULES_TOUCHED=0
FRESH=0

preamble=""
[ -f "$TMP/preamble.md" ] && preamble="$(trim "$TMP/preamble.md")"
if [ -n "$preamble" ]; then
  short="$(printf '%s\n' "$preamble" | head -1)"
  if [ -f "$RULES_FILE" ] && tr -d '\r' < "$RULES_FILE" | grep -q -x -F -- "$short"; then
    report_rule "已存在" "開頭句「$short」"
  elif [ "$DRY" -eq 1 ]; then
    report_rule "待補行" "開頭句「$short」（加在規則檔最前面）"
    RULES_TOUCHED=1
  else
    mkdir -p "$(dirname "$RULES_FILE")"
    if [ -s "$RULES_FILE" ]; then
      { printf '%s\n\n' "$preamble" | to_eol; cat "$RULES_FILE"; } > "$TMP/rules.new"
      cat "$TMP/rules.new" > "$RULES_FILE"
    else
      printf '%s\n' "$preamble" | to_eol > "$RULES_FILE"
      FRESH=1
    fi
    RULES_TOUCHED=1
    report_rule "補行" "開頭句「$short」（加在規則檔最前面）"
  fi
fi

for sec in "$TMP"/sec-*.md; do
  body="$(trim "$sec")"
  title="$(printf '%s\n' "$body" | grep -m1 -E '^# ' | sed -e 's/^# //' -e 's/[[:space:]]*$//')"
  [ -n "$title" ] || continue

  if has_heading "$title"; then
    report_rule "已存在" "# $title"
    continue
  fi

  if [ "$title" = "委派邊界規格" ] && [ "$WITH_DELEGATION" -eq 0 ]; then
    report_rule "略過" "# $title（沒給 --with-delegation。確認〈決策分級〉高風險清單有「委派」那一行）"
    continue
  fi

  if [ "$DRY" -eq 1 ]; then
    report_rule "待附加" "# $title"
  else
    mkdir -p "$(dirname "$RULES_FILE")"
    append_section "$body"
    report_rule "附加" "# $title"
  fi
  RULES_TOUCHED=1
done

[ "$RULES_TOUCHED" -eq 1 ] && mark_touched "$RULES_REL"

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

install_file "QUESTIONS.md"        "QUESTIONS.md"
install_file "SOP.md"              "SOP.md" "→ 只留〈目錄〉；寫法規則在 SOP/README.md，見 references/upgrade-existing.md"
install_file "SOP-README.md"       "SOP/README.md"
install_file "ROADMAP.md"          "ROADMAP.md"
install_file "decisions-README.md" "docs/decisions/README.md"
install_file "session-handoff.md"  ".claude/templates/session-handoff.md"
install_file "outline.py"          "tools/outline.py"

# ---- 回報 ----
echo "專案: $PROJECT"
echo "規則檔: $RULES_REL（$RULES_WHY）"
echo "行尾: $EOL"
echo "推送政策: $PUSH_LABEL"
echo "服務埠: $PORTS_TEXT"
echo "冷啟動上限: $COLD_START_TOKENS token"
if [ "$DRY" -eq 1 ]; then echo "（--dry-run：沒有寫入任何東西）"; fi
echo
echo "== 規則檔 $RULES_REL：開頭句與八節 =="
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
