#!/usr/bin/env bash
# collab-kit-init 的安裝腳本：把 assets/ 的規則與模板寫進專案。
# kit 擁有、每次整份覆寫：規則檔（內容不同時舊檔留成 .bak）、docs/procedures/、.collab-kit-version。
# 專案擁有、缺才建、已存在不覆蓋：其餘檔案。
# 偵測驗證指令、搬移舊內容不在這裡做，由 agent 執行（見 SKILL.md）。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$SKILL_DIR/assets"
RULES_SRC="$ASSETS/claude-md-rules.md"
MERGE_HOOKS="$SKILL_DIR/scripts/merge_hooks.py"

PROJECT="$PWD"
DRY=0
WITH_HOOKS=0
ALLOW_PUSH_MAIN=0
ALLOW_MCP_WRITES=0

usage() {
  cat <<'USAGE'
用法: install.sh [--project DIR] [--dry-run] [--with-hooks [--allow-push-main] [--allow-github-mcp-writes]]

  --project DIR   專案根目錄（預設：目前工作目錄）
  --dry-run       只印出會做什麼，不寫檔
  --with-hooks    另外安裝 agent hook 與 git pre-commit（預設不裝，裝之前要 user 同意；
                  --project 必須是 git 專案的頂層目錄）：
                    tools/hooks/、.claude/settings.json 與 .codex/hooks.json 的 hooks 區塊（冪等合併，舊檔留 .bak）、
                    git 的 pre-commit（已有別人的 hook 就不覆蓋）
  --allow-push-main  只和 --with-hooks 併用：專案已明寫放行 push main 時，hook 不擋 push main
                    （force push 與密鑰檔仍擋）
  --allow-github-mcp-writes  只和 --with-hooks 併用：Claude 的 permissions.deny 預設擋掉 GitHub MCP 的
                    push_files、create_or_update_file、delete_file、merge_pull_request；加這個旗標就不擋

規則檔：一律寫進 AGENTS.md（內容不同時舊檔留成 AGENTS.md.bak；.bak 已存在就依序用 .bak.1、.bak.2，不覆蓋）。
預檢：CLAUDE.md 或 AGENTS.md 是 symlink、兩者是同一個檔、任何要寫的檔是目錄或斷掉的 symlink 時，中止（結束碼 3），不寫任何東西（含 --dry-run）。
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
    --with-hooks) WITH_HOOKS=1; shift ;;
    --allow-push-main) ALLOW_PUSH_MAIN=1; shift ;;
    --allow-github-mcp-writes) ALLOW_MCP_WRITES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知參數: $1" >&2; usage >&2; exit 2 ;;
  esac
done

{ [ "$ALLOW_PUSH_MAIN" -eq 0 ] && [ "$ALLOW_MCP_WRITES" -eq 0 ]; } || [ "$WITH_HOOKS" -eq 1 ] || { echo "--allow-push-main、--allow-github-mcp-writes 只能和 --with-hooks 一起用" >&2; exit 2; }
[ -d "$PROJECT" ] || { echo "專案目錄不存在: $PROJECT" >&2; exit 2; }
[ -f "$RULES_SRC" ] || { echo "找不到規則全文: $RULES_SRC" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"
# ---- 預檢：任何東西寫下去之前先確認沒有會讓寫入損壞或中途失敗的狀態 ----
PROBLEMS=""
problem() { PROBLEMS="${PROBLEMS}  $1
"; }
for f in CLAUDE.md AGENTS.md; do
  if [ -L "$PROJECT/$f" ]; then problem "$f 是 symlink（→ $(readlink "$PROJECT/$f")）：寫入會改到連結的另一端，使用者原檔可能遺失"; fi
done
if [ -e "$PROJECT/CLAUDE.md" ] && [ -e "$PROJECT/AGENTS.md" ] && [ "$PROJECT/CLAUDE.md" -ef "$PROJECT/AGENTS.md" ]; then
  problem "CLAUDE.md 與 AGENTS.md 是同一個檔（硬連結或指向同一檔）：寫其中一個會改到另一個"
fi
for d in docs docs/plans docs/procedures ROADMAP tools; do
  if { [ -e "$PROJECT/$d" ] && [ ! -d "$PROJECT/$d" ]; } || { [ -L "$PROJECT/$d" ] && [ ! -e "$PROJECT/$d" ]; }; then
    problem "$d 不是目錄（或是斷掉的 symlink）：無法在底下建檔"
  fi
done
PREFLIGHT_FILES="CLAUDE.md AGENTS.md QUESTIONS.md ROADMAP.md ROADMAP/later.md ROADMAP/parked.md DECISIONS.md STATE.md docs/spec.md docs/plans/README.md docs/project-rules.md docs/testing.md docs/cold-review.md tools/outline.py .collab-kit-version"
for pf in "$ASSETS"/procedures/*.md; do PREFLIGHT_FILES="$PREFLIGHT_FILES docs/procedures/$(basename "$pf")"; done
for f in $PREFLIGHT_FILES; do
  if [ -L "$PROJECT/$f" ] && [ ! -e "$PROJECT/$f" ]; then problem "$f 是斷掉的 symlink"
  elif [ -e "$PROJECT/$f" ] && [ ! -f "$PROJECT/$f" ]; then problem "$f 存在但不是一般檔案（可能是目錄）"; fi
done
if [ "$WITH_HOOKS" -eq 1 ]; then
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' 2>/dev/null; then
    problem "--with-hooks 需要 python3（3.7 以上）：用來合併設定檔與執行 hook"
  fi
  for d in .claude .codex tools/hooks; do
    if { [ -e "$PROJECT/$d" ] && [ ! -d "$PROJECT/$d" ]; } || { [ -L "$PROJECT/$d" ] && [ ! -e "$PROJECT/$d" ]; }; then
      problem "$d 不是目錄（或是斷掉的 symlink）：無法在底下建檔"
    fi
  done
  for f in tools/hooks/collab_hook.py tools/hooks/collab_adapters.py tools/hooks/doc_check.py .claude/settings.json .codex/hooks.json; do
    if [ -L "$PROJECT/$f" ]; then problem "$f 是 symlink：腳本不寫入設定檔或 hook 腳本的連結"
    elif [ -e "$PROJECT/$f" ] && [ ! -f "$PROJECT/$f" ]; then problem "$f 存在但不是一般檔案"; fi
  done
  GIT_TOP="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "$GIT_TOP" ]; then
    problem "--with-hooks 需要 git 專案：Codex 的 hook 與 pre-commit 都以 git 根目錄定位腳本（先 git init）"
  elif [ "$(cd "$GIT_TOP" && pwd -P)" != "$(cd "$PROJECT" && pwd -P)" ]; then
    problem "--project 不是 git 專案的頂層目錄（頂層是 $GIT_TOP）：hook 以 git 根目錄找腳本，裝在子目錄會全部失效。請對頂層目錄安裝"
  else
    GIT_HOOKS_DIR="$(git -C "$PROJECT" rev-parse --git-path hooks)"
    case "$GIT_HOOKS_DIR" in /*) ;; *) GIT_HOOKS_DIR="$PROJECT/$GIT_HOOKS_DIR" ;; esac
    if { [ -e "$GIT_HOOKS_DIR" ] && [ ! -d "$GIT_HOOKS_DIR" ]; } || { [ -L "$GIT_HOOKS_DIR" ] && [ ! -e "$GIT_HOOKS_DIR" ]; }; then
      problem "git hooks 目錄 $GIT_HOOKS_DIR 不是目錄（或是斷掉的 symlink）：無法安裝 pre-commit"
    fi
  fi
  if [ -z "$PROBLEMS" ]; then
    for spec in ".claude/settings.json:claude" ".codex/hooks.json:codex"; do
      if ! out="$(python3 "$MERGE_HOOKS" --target "$PROJECT/${spec%%:*}" --agent "${spec##*:}" --check 2>&1)"; then
        problem "$out"
      fi
    done
  fi
fi
if [ -n "$PROBLEMS" ]; then
  echo "預檢失敗，腳本不寫入任何東西（含 --dry-run）。請先處理下列狀態再重跑：" >&2
  printf '%s' "$PROBLEMS" >&2
  exit 3
fi

# ---- 規則檔：一律寫 AGENTS.md ----
# 只認整行只有 `@<路徑>` 的一層匯入；略過 HTML 註解（含句中開始）、``` 與 ~~~ code fence（同字元、不短於開頭才算關閉）裡的行，並去掉開頭的 UTF-8 BOM。
CLAUDE_MD="$PROJECT/CLAUDE.md"
IMPORTS=""
if [ -f "$CLAUDE_MD" ]; then
  IMPORTS="$(awk '
    function fence_close(s, ch, len,    t, rest) {
      if (!match(s, /^[ \t]*(```+|~~~+)/)) return 0
      t = substr(s, RSTART, RLENGTH); rest = substr(s, RSTART + RLENGTH); sub(/^[ \t]+/, "", t)
      return substr(t, 1, 1) == ch && length(t) >= len && rest ~ /^[ \t]*$/
    }
    { sub(/\r$/, "") }
    NR == 1 && index($0, "\357\273\277") == 1 { $0 = substr($0, 4) }
    fch != "" { if (fence_close($0, fch, flen)) fch = ""; next }
    {
      line = $0; out = ""
      for (;;) {
        if (incomment) {
          i = index(line, "-->")
          if (i == 0) { line = ""; break }
          line = substr(line, i + 3); incomment = 0
        } else {
          i = index(line, "<!--")
          if (i == 0) break
          out = out substr(line, 1, i - 1)
          rest = substr(line, i + 4); j = index(rest, "-->")
          if (j == 0) { line = ""; incomment = 1; break }
          line = substr(rest, j + 3)
        }
      }
      line = out line
      if (match(line, /^[ \t]*(```+|~~~+)/)) {
        t = substr(line, RSTART, RLENGTH); sub(/^[ \t]+/, "", t)
        fch = substr(t, 1, 1); flen = length(t); next
      }
      if (line ~ /^@[^[:space:]]+[[:space:]]*$/) {
        sub(/^@/, "", line); sub(/[[:space:]]+$/, "", line); sub(/^(\.\/)+/, "", line); print line
      }
    }
  ' "$CLAUDE_MD")"
fi
OTHER_IMPORTS="$(printf '%s\n' "$IMPORTS" | grep -vxE 'AGENTS\.md|STATE\.md|' | awk '!seen[$0]++' | paste -sd' ' - || true)"
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
# ---- 選用：agent hook 與 git pre-commit（--with-hooks）----
if [ "$WITH_HOOKS" -eq 1 ]; then
  for hf in collab_hook.py collab_adapters.py doc_check.py; do
    hrel="tools/hooks/$hf"
    if [ -f "$PROJECT/$hrel" ] && same_text "$PROJECT/$hrel" "$ASSETS/hooks/$hf"; then
      report "已是新版" "$hrel"
    elif [ "$DRY" -eq 1 ]; then
      report "待覆寫" "$hrel"
    else
      mkdir -p "$PROJECT/tools/hooks"
      if [ -f "$PROJECT/$hrel" ]; then report "覆寫" "$hrel"; else report "建立" "$hrel"; fi
      cp "$ASSETS/hooks/$hf" "$PROJECT/$hrel"
      mark_touched "$hrel"
    fi
  done
  for spec in ".claude/settings.json:claude" ".codex/hooks.json:codex"; do
    hrel="${spec%%:*}"; hagent="${spec##*:}"
    margs=(--target "$PROJECT/$hrel" --agent "$hagent")
    if [ "$ALLOW_PUSH_MAIN" -eq 1 ]; then margs+=(--allow-push-main); fi
    if [ "$ALLOW_MCP_WRITES" -eq 1 ]; then margs+=(--allow-github-mcp-writes); fi
    if [ "$DRY" -eq 1 ]; then margs+=(--dry-run); else margs+=(--apply); fi
    mout="$(python3 "$MERGE_HOOKS" "${margs[@]}")"
    mstatus="${mout%%$'\t'*}"
    mbak=""; case "$mout" in *$'\t'*) mbak="${mout#*$'\t'}" ;; esac
    case "$mstatus" in
      unchanged) report "已是新版" "$hrel 的 hooks" ;;
      created) if [ "$DRY" -eq 1 ]; then report "待建立" "$hrel"; else report "建立" "$hrel"; mark_touched "$hrel"; fi ;;
      updated)
        if [ "$DRY" -eq 1 ]; then report "待合併" "$hrel（舊檔會留成 .bak）"
        else report "合併" "$hrel 的 hooks（舊檔留成 ${mbak#"$PROJECT"/}）"; mark_touched "$hrel"; mark_touched "${mbak#"$PROJECT"/}"; fi ;;
      *) echo "merge_hooks.py 回傳了無法辨識的結果：$mout" >&2; exit 1 ;;
    esac
  done
  # git pre-commit：只覆寫自己裝的（檔內有標記）；內容不同時舊檔先留成 .bak.N；已有別人的 hook 就不動
  HOOK_SRC="$ASSETS/hooks/pre-commit"
  HOOK_DEST="$GIT_HOOKS_DIR/pre-commit"
  if [ -e "$HOOK_DEST" ] || [ -L "$HOOK_DEST" ]; then
    if [ -f "$HOOK_DEST" ] && [ ! -L "$HOOK_DEST" ] && grep -q 'collab-kit-init pre-commit' "$HOOK_DEST"; then
      if same_text "$HOOK_DEST" "$HOOK_SRC"; then report "已是新版" "git pre-commit"
      elif [ "$DRY" -eq 1 ]; then report "待覆寫" "git pre-commit（舊檔留成 $(basename "$(next_bak "$HOOK_DEST")")）"
      else
        HBAK="$(next_bak "$HOOK_DEST")"
        cp "$HOOK_DEST" "$HBAK"
        cp "$HOOK_SRC" "$HOOK_DEST"; chmod +x "$HOOK_DEST"
        report "覆寫" "git pre-commit（舊檔留成 $(basename "$HBAK")）"
      fi
    else
      report "略過" "git pre-commit：已有別的 hook，不覆蓋。請在它裡面加一行 python3 tools/hooks/doc_check.py"
    fi
  elif [ "$DRY" -eq 1 ]; then
    report "待建立" "git pre-commit"
  else
    mkdir -p "$GIT_HOOKS_DIR"; cp "$HOOK_SRC" "$HOOK_DEST"; chmod +x "$HOOK_DEST"; report "建立" "git pre-commit"
  fi
fi
# 版本戳＝kit 擁有的檔（規則全文＋程序檔＋hook 檔）的內容雜湊；hook 檔有改，所有專案的版本戳都會變。不用 git 短碼：skill 被複製進專案後，git 會回報專案自己的 commit。
KIT_VER="$(cat "$RULES_SRC" "$ASSETS"/procedures/*.md "$ASSETS"/hooks/* | tr -d '\r' | md5sum | cut -c1-12)"
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
echo "  步驟 4：留了 .bak 時依 SKILL.md 步驟 4 分流搬（專案規則→docs/project-rules.md、目標與約束→STATE.md、其他 @ 匯入→CLAUDE.md、授權類不搬）；並用 git diff docs/procedures/ 檢查被覆寫的程序檔"
if [ "$WITH_HOOKS" -eq 1 ]; then
  echo "== hook 還需要你做 =="
  echo "  Codex：hook 要先被信任才會跑。在 Codex 開 /hooks，核准 collab 的 hook（hook 或腳本有變動時要重新核准）"
  echo "  Claude Code：開啟這個專案時接受專案信任對話框；改過設定檔後用 /hooks 確認載入"
  echo "  hook 只是護欄：兩邊逾時或出錯時工具都會照常執行"
fi
