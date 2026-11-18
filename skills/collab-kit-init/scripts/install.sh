#!/usr/bin/env bash
# collab-kit-init 的安裝腳本：把 assets/ 的規則與模板寫進專案。
# kit 擁有、每次整份覆寫：規則檔（內容不同時舊檔留成 .bak）、docs/procedures/、.collab-kit-version。
# 專案擁有、缺才建、已存在不覆蓋：其餘檔案。
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

規則檔：一律寫進 AGENTS.md（內容不同時舊檔留成 AGENTS.md.bak；.bak 已存在就依序用 .bak.1、.bak.2，不覆蓋）。
CLAUDE.md 或 AGENTS.md 是 symlink 時中止（結束碼 3），不寫任何東西。
CLAUDE.md：不存在就新建成 `@AGENTS.md` 與 `@STATE.md` 兩行；已有 `@` 匯入就保留原內容，只補缺的那幾行；
沒有任何 `@` 匯入（規則直接寫在裡面）就換成兩行匯入，舊檔留成 CLAUDE.md.bak。
docs/procedures/ 每次整份覆寫。
其餘檔案缺就建，已存在不覆蓋：
  QUESTIONS.md / STATE.md / DECISIONS.md / docs/spec.md / docs/plans/README.md /
  ROADMAP.md / ROADMAP/later.md / ROADMAP/parked.md /
  docs/project-rules.md / docs/testing.md / docs/cold-review.md /
  tools/outline.py；docs/procedures/ 每次整份覆寫，並寫 .collab-kit-version
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
for f in CLAUDE.md AGENTS.md; do
  if [ -L "$PROJECT/$f" ]; then
    echo "$f 是 symlink（$(readlink "$PROJECT/$f")）：腳本不寫入，避免 CLAUDE.md 與 AGENTS.md 互相覆蓋、使用者原檔遺失。" >&2
    echo "請先決定哪個是真檔，把另一個換成一般檔或移除連結，再重跑。" >&2
    exit 3
  fi
done

# ---- 規則檔：一律寫 AGENTS.md ----
# 只認整行只有 `@<路徑>` 的一層匯入，略過 HTML 註解與 code fence 裡的行。
CLAUDE_MD="$PROJECT/CLAUDE.md"
IMPORTS=""
if [ -f "$CLAUDE_MD" ]; then
  IMPORTS="$(awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    incomment { if (index($0, "-->")) incomment = 0; next }
    /^[[:space:]]*<!--/ { if (!index($0, "-->")) incomment = 1; next }
    /^@[^[:space:]]+[[:space:]]*$/ { sub(/^@/, ""); sub(/[[:space:]]+$/, ""); sub(/^(\.\/)+/, ""); print }
  ' "$CLAUDE_MD")"
fi
OTHER_IMPORTS="$(printf '%s\n' "$IMPORTS" | grep -vxE 'AGENTS\.md|STATE\.md|' | tr '\n' ' ' || true)"
RULES_REL="AGENTS.md"
if [ ! -f "$CLAUDE_MD" ]; then RULES_WHY="CLAUDE.md 不存在，新建成匯入檔"
elif [ -z "$IMPORTS" ]; then RULES_WHY="CLAUDE.md 沒有 @ 匯入；CLAUDE.md 換成匯入檔，舊檔留成 CLAUDE.md.bak"
else RULES_WHY="CLAUDE.md 已有 @ 匯入；保留原內容，只補缺的 @AGENTS.md／@STATE.md"; fi
RULES_FILE="$PROJECT/$RULES_REL"

REPORT=""
TOUCHED=""
report() { REPORT="${REPORT}$(printf '  %-8s %s' "$1" "$2")
"; }
mark_touched() { TOUCHED="${TOUCHED}$1
"; }
same_text() { cmp -s <(tr -d '\r' < "$1") <(tr -d '\r' < "$2"); }
# 已存在的 .bak 不覆蓋：它可能是使用者還沒搬走內容的舊檔。依序用 .bak、.bak.1、.bak.2……
next_bak() {
  local base="$1.bak" n=1
  if [ ! -e "$base" ]; then printf '%s' "$base"; return; fi
  while [ -e "$base.$n" ]; do n=$((n + 1)); done
  printf '%s' "$base.$n"
}

# ---- 規則檔：整份換成規則全文 ----
if [ -f "$RULES_FILE" ] && same_text "$RULES_FILE" "$RULES_SRC"; then
  report "已是新版" "$RULES_REL"
elif [ "$DRY" -eq 1 ]; then
  if [ -f "$RULES_FILE" ]; then report "待換新" "$RULES_REL（舊檔留成 $(basename "$(next_bak "$RULES_FILE")")）"
  else report "待建立" "$RULES_REL"; fi
else
  mkdir -p "$(dirname "$RULES_FILE")"
  if [ -f "$RULES_FILE" ]; then
    BAK="$(next_bak "$RULES_FILE")"
    cp "$RULES_FILE" "$BAK"
    report "換新" "$RULES_REL（舊檔留成 ${BAK#"$PROJECT"/}）"
    mark_touched "${BAK#"$PROJECT"/}"
  else
    report "建立" "$RULES_REL"
  fi
  cp "$RULES_SRC" "$RULES_FILE"
  mark_touched "$RULES_REL"
fi

# ---- CLAUDE.md：要匯入規則檔與 STATE.md，兩者才會在開工時自動載入 ----
has_import() { printf '%s\n' "$IMPORTS" | grep -qxF -- "$1"; }
if [ -z "$IMPORTS" ]; then
  WANT="$(printf '@AGENTS.md\n@STATE.md')"
  if [ "$DRY" -eq 1 ]; then
    if [ -f "$CLAUDE_MD" ]; then report "待換新" "CLAUDE.md（改成匯入 @AGENTS.md 與 @STATE.md；舊檔留成 $(basename "$(next_bak "$CLAUDE_MD")")）"
    else report "待建立" "CLAUDE.md（匯入 @AGENTS.md 與 @STATE.md）"; fi
  else
    if [ -f "$CLAUDE_MD" ]; then
      BAK="$(next_bak "$CLAUDE_MD")"
      cp "$CLAUDE_MD" "$BAK"
      report "換新" "CLAUDE.md（舊檔留成 ${BAK#"$PROJECT"/}）"
      mark_touched "${BAK#"$PROJECT"/}"
    else
      report "建立" "CLAUDE.md"
    fi
    printf '%s\n' "$WANT" > "$CLAUDE_MD"
    mark_touched "CLAUDE.md"
  fi
else
  for target in AGENTS.md STATE.md; do
    if has_import "$target"; then
      report "已匯入" "CLAUDE.md 已有 @$target"
    elif [ "$DRY" -eq 1 ]; then
      report "待加一行" "CLAUDE.md（加 @$target）"
    else
      if [ -n "$(tail -c1 "$CLAUDE_MD")" ]; then printf '\n' >> "$CLAUDE_MD"; fi
      printf '@%s\n' "$target" >> "$CLAUDE_MD"
      report "加一行" "CLAUDE.md（加 @$target）"
      mark_touched "CLAUDE.md"
    fi
  done
  if [ -n "$OTHER_IMPORTS" ]; then
    report "注意" "CLAUDE.md 另外匯入：${OTHER_IMPORTS}。其中若有舊版規則全文，請手動移除，以免與 AGENTS.md 重複"
  fi
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
install_file "ROADMAP.md"            "ROADMAP.md"
install_file "ROADMAP-later.md"      "ROADMAP/later.md"
install_file "ROADMAP-parked.md"     "ROADMAP/parked.md"
install_file "DECISIONS.md"         "DECISIONS.md"
install_file "STATE.md"             "STATE.md"
install_file "spec.md"              "docs/spec.md"
install_file "plans-README.md"      "docs/plans/README.md"
install_file "project-rules.md"      "docs/project-rules.md"
install_file "testing.md"            "docs/testing.md"
install_file "cold-review.md"         "docs/cold-review.md"
install_file "outline.py"            "tools/outline.py"

# ---- kit 擁有的程序檔：每次整份覆寫，並寫版本戳 ----
for p in "$ASSETS"/procedures/*.md; do
  rel="docs/procedures/$(basename "$p")"
  if [ "$DRY" -eq 1 ]; then report "待覆寫" "$rel"; else mkdir -p "$PROJECT/docs/procedures"; cp "$p" "$PROJECT/$rel"; report "覆寫" "$rel"; fi
  mark_touched "$rel"
done
# 版本戳＝kit 擁有的檔（規則全文＋程序檔）的內容雜湊。不用 git 短碼：skill 被複製進專案後，git 會回報專案自己的 commit。
KIT_VER="$(cat "$RULES_SRC" "$ASSETS"/procedures/*.md | tr -d '\r' | md5sum | cut -c1-12)"
VER_FILE="$PROJECT/.collab-kit-version"
OLD_VER=""
if [ -f "$VER_FILE" ]; then OLD_VER="$(tr -d '\r\n' < "$VER_FILE")"; fi
if [ "$OLD_VER" = "$KIT_VER" ]; then
  report "版本" ".collab-kit-version = $KIT_VER（未變）"
elif [ "$DRY" -eq 1 ]; then
  report "待寫版本" ".collab-kit-version：${OLD_VER:-無} → $KIT_VER"
else
  printf '%s\n' "$KIT_VER" > "$VER_FILE"
  report "版本" ".collab-kit-version：${OLD_VER:-無} → $KIT_VER"
  mark_touched ".collab-kit-version"
fi

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
echo "  步驟 2：STATE.md 還是模板時，照已知事實填目標、契約、下一步、測試指令"
echo "  步驟 3：偵測本專案的驗證指令、服務埠等，寫進 docs/project-rules.md"
echo "  步驟 4：留了 .bak 時依 SKILL.md 步驟 4 分流搬（專案規則→docs/project-rules.md、目標與約束→STATE.md、其他 @ 匯入→CLAUDE.md、授權類不搬）；並用 git diff docs/procedures/ 檢查被覆寫的程序檔、處理舊 docs/codex-collaboration.md"
