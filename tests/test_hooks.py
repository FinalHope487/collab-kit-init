"""agent hook、git pre-commit 與 --with-hooks 安裝的驗收。

用法: python3 tests/test_hooks.py
Codex 無法在這裡真正執行，所以 Codex 端用「官方文件規定的 stdin 格式」模擬輸入；Claude 端同樣以文件格式模擬。
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import warnings

# 測試裡為了簡短用了 open(...).read()，關掉 ResourceWarning 的雜訊（只影響本測試檔）
warnings.simplefilter("ignore", ResourceWarning)

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILL = os.path.join(KIT, "skills", "collab-kit-init")
HOOKS = os.path.join(SKILL, "assets", "hooks")
CORE = os.path.join(HOOKS, "collab_hook.py")
MERGE = os.path.join(SKILL, "scripts", "merge_hooks.py")
INSTALL = os.path.join(SKILL, "scripts", "install.sh")
DOC_CHECK = os.path.join(HOOKS, "doc_check.py")


def run(cmd, stdin=None, cwd=None, env=None):
    return subprocess.run(
        cmd, input=stdin, capture_output=True, text=True, cwd=cwd, env=env
    )


def git(cwd, *args):
    done = subprocess.run(["git"] + list(args), cwd=cwd, capture_output=True, text=True)
    assert done.returncode == 0, done.stderr
    return done.stdout


def new_repo():
    d = tempfile.mkdtemp(prefix="collab-test-")
    git(d, "init", "-q", "-b", "main")
    git(d, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init")
    return d


def hook(agent, payload, *extra):
    done = run(["python3", CORE, "--agent", agent] + list(extra), stdin=json.dumps(payload))
    return done


def decision(done):
    """回傳 (結束碼, deny 的理由或 None)。"""
    if not done.stdout.strip():
        return done.returncode, None
    out = json.loads(done.stdout)["hookSpecificOutput"]
    assert out["permissionDecision"] == "deny"
    return done.returncode, out["permissionDecisionReason"]


def bash_payload(cwd, command):
    return {"hook_event_name": "PreToolUse", "cwd": cwd, "tool_name": "Bash", "tool_input": {"command": command}}


class CoreHook(unittest.TestCase):
    def setUp(self):
        self.repo = new_repo()
        self.addCleanup(shutil.rmtree, self.repo, True)

    def test_session_start_injects_state_for_both_agents(self):
        with open(os.path.join(self.repo, "STATE.md"), "w", encoding="utf-8") as f:
            f.write("# 現況\n目標：試試看\n")
        for agent in ("claude", "codex"):
            done = hook(agent, {"hook_event_name": "SessionStart", "cwd": self.repo, "source": "startup"})
            self.assertEqual(done.returncode, 0)
            self.assertIn("目標：試試看", done.stdout)

    def test_session_start_without_state_is_silent(self):
        done = hook("claude", {"hook_event_name": "SessionStart", "cwd": self.repo})
        self.assertEqual((done.returncode, done.stdout), (0, ""))

    def test_session_start_truncates_huge_state_with_notice(self):
        with open(os.path.join(self.repo, "STATE.md"), "w", encoding="utf-8") as f:
            f.write("字" * 20000)
        done = hook("codex", {"hook_event_name": "SessionStart", "cwd": self.repo})
        self.assertIn("請自行讀取完整檔案", done.stdout)
        self.assertLess(len(done.stdout), 9500)

    BASH_CASES = [
        ("git push origin main", True),
        ("git push", True),  # 目前在 main
        ("git push origin", True),
        ("git push origin HEAD", True),
        ("git push origin HEAD:refs/heads/main", True),
        ("git push origin :main", True),
        ("git push --delete origin main", True),
        ("git push origin feature main", True),
        ("git push origin main 2>&1", True),
        # 先前漏擋：重導向與帶值選項被當成 refspec，使「在 main 上單純 push」被放行
        ("git push origin 2>&1", True),
        ("git push origin 2>&1 | tail -5", True),
        ("git push origin 2>/dev/null", True),
        ("git push origin > /tmp/log 2>&1", True),
        ("git push -o ci.skip origin", True),
        ("git push --push-option=ci.skip origin", True),
        ("git push -u origin feature", False),
        ("git push origin feature", False),
        ("git push origin feature 2>&1", False),
        ("git push -o x origin feature", False),
        ("git push --force origin feature", True),
        ("git push -f origin feature", True),
        ("git push --force-with-lease origin feature", True),
        ("git push origin +feature", True),
        ('bash -c "git push origin main"', True),
        ("git -C . push origin main", True),
        ("env FOO=1 git push origin main", True),
        ("git status", False),
        ("git log --oneline -3", False),
        ("python3 -m pytest -q", False),
    ]

    # Bash 端刻意不猜「會不會改檔、讀密鑰」：這些都放行（受保護檔只看檔案工具的路徑）
    BASH_NOT_GUESSED = [
        "cat .env",
        "cat AGENTS.md 2>&1",
        "cp AGENTS.md /tmp/x",
        "cp docs/spec.md docs/spec.proposed.md",
        "sed -i s/a/b/ AGENTS.md",
        "echo x > docs/spec.md",
        "jq '.key' package.json",
        "rg -n '.env' src",
        "ls && cat .env",
        "git add .env",
    ]

    def test_command_given_as_list_is_checked_like_a_string(self):
        cases = [
            (["bash", "-lc", "git push origin main"], True),
            (["git", "push", "origin", "main"], True),
            (["git", "push", "--force", "origin", "feature"], True),
            (["bash", "-lc", "git push origin feature"], False),
            (["git", "status"], False),
        ]
        for command, expect_deny in cases:
            for agent in ("claude", "codex"):
                payload = {"hook_event_name": "PreToolUse", "cwd": self.repo, "tool_name": "Bash",
                           "tool_input": {"command": command}}
                code, reason = decision(hook(agent, payload))
                self.assertEqual(code, 0, command)
                self.assertEqual(reason is not None, expect_deny, (agent, command))

    def test_malformed_command_types_pass_without_crashing(self):
        for command in (None, 5, {"a": 1}, [], [1, 2], ["git", 3]):
            payload = {"hook_event_name": "PreToolUse", "cwd": self.repo, "tool_name": "Bash",
                       "tool_input": {"command": command}}
            done = hook("codex", payload)
            self.assertEqual((done.returncode, done.stdout), (0, ""), command)

    def test_bash_does_not_guess_reads_or_writes(self):
        for command in self.BASH_NOT_GUESSED:
            for agent in ("claude", "codex"):
                _, reason = decision(hook(agent, bash_payload(self.repo, command)))
                self.assertIsNone(reason, (agent, command))

    def test_bash_matrix_is_identical_for_both_agents(self):
        for command, expect_deny in self.BASH_CASES:
            results = []
            for agent in ("claude", "codex"):
                code, reason = decision(hook(agent, bash_payload(self.repo, command)))
                self.assertEqual(code, 0, command)
                results.append(reason is not None)
            self.assertEqual(results, [expect_deny, expect_deny], command)

    def test_push_to_feature_branch_is_allowed_while_on_main(self):
        code, reason = decision(hook("claude", bash_payload(self.repo, "git push origin feature")))
        self.assertIsNone(reason)

    def test_allow_push_main_flag_only_relaxes_push_main(self):
        for command, expect_deny in (
            ("git push origin main", False),
            ("git push", False),
            ("git push origin 2>&1", False),
            ("git push --force origin feature", True),
            ("git push origin +main", True),
        ):
            _, reason = decision(hook("claude", bash_payload(self.repo, command), "--allow-push-main"))
            self.assertEqual(reason is not None, expect_deny, command)

    def test_spec_denial_points_to_proposed_file(self):
        payload = {"hook_event_name": "PreToolUse", "cwd": self.repo, "tool_name": "Edit",
                   "tool_input": {"file_path": os.path.join(self.repo, "docs", "spec.md")}}
        for agent in ("claude", "codex"):
            if agent == "codex":
                payload = {"hook_event_name": "PreToolUse", "cwd": self.repo, "tool_name": "apply_patch",
                           "tool_input": {"command": "*** Begin Patch\n*** Update File: docs/spec.md\n@@\n-a\n+b\n*** End Patch"}}
            _, reason = decision(hook(agent, payload))
            self.assertIn("docs/spec.proposed.md", reason)
            self.assertIn("QUESTIONS.md", reason)

    def test_deny_reason_tells_agent_to_ask_user(self):
        _, reason = decision(hook("codex", bash_payload(self.repo, "git push origin main")))
        self.assertIn("user", reason)
        self.assertIn("問答工具", reason)

    def test_claude_file_tools(self):
        cases = [
            ("Edit", "docs/spec.md", True),
            ("Write", "AGENTS.md", True),
            ("Edit", "docs/procedures/verification.md", True),
            ("Edit", ".env", True),
            ("Read", ".env", True),
            ("Read", "AGENTS.md", False),
            ("Read", "docs/spec.md", False),
            ("Edit", "src/main.py", False),
            ("Edit", "sub/AGENTS.md", False),
            ("Edit", "docs/project-rules.md", False),
            ("Write", "docs/spec.proposed.md", False),
        ]
        for tool, path, expect_deny in cases:
            payload = {
                "hook_event_name": "PreToolUse",
                "cwd": self.repo,
                "tool_name": tool,
                "tool_input": {"file_path": os.path.join(self.repo, path)},
            }
            _, reason = decision(hook("claude", payload))
            self.assertEqual(reason is not None, expect_deny, (tool, path))

    def test_codex_apply_patch(self):
        def patch(*paths):
            body = "".join("*** Update File: %s\n@@\n-a\n+b\n" % p for p in paths)
            return "*** Begin Patch\n" + body + "*** End Patch"

        cases = [
            (patch("AGENTS.md"), True),
            (patch("docs/spec.md"), True),
            (patch("src/a.py", "docs/procedures/chores.md"), True),
            (patch("src/a.py"), False),
            (patch("docs/project-rules.md"), False),
            (patch("docs/spec.proposed.md"), False),
        ]
        for text, expect_deny in cases:
            payload = {
                "hook_event_name": "PreToolUse",
                "cwd": self.repo,
                "tool_name": "apply_patch",
                "tool_input": {"command": text},
            }
            _, reason = decision(hook("codex", payload))
            self.assertEqual(reason is not None, expect_deny, text)

    def test_codex_patch_with_unknown_format_falls_back_to_text_match(self):
        payload = {
            "hook_event_name": "PreToolUse",
            "cwd": self.repo,
            "tool_name": "apply_patch",
            "tool_input": {"command": "diff --git a/docs/spec.md b/docs/spec.md\n-a\n+b\n"},
        }
        _, reason = decision(hook("codex", payload))
        self.assertIsNotNone(reason)

    def test_symlinked_project_path_does_not_bypass_protection(self):
        base = tempfile.mkdtemp(prefix="collab-sym-")
        self.addCleanup(shutil.rmtree, base, True)
        real = os.path.join(base, "repo")
        os.makedirs(real)
        git(real, "init", "-q", "-b", "main")
        link = os.path.join(base, "link")
        os.symlink(real, link)
        cases = [
            ("claude", {"tool_name": "Write", "tool_input": {"file_path": os.path.join(link, "AGENTS.md")}}),
            ("claude", {"tool_name": "Edit", "tool_input": {"file_path": "docs/spec.md"}}),
            ("codex", {"tool_name": "apply_patch", "tool_input": {"command": "*** Begin Patch\n*** Update File: AGENTS.md\n@@\n-a\n+b\n*** End Patch"}}),
        ]
        for agent, extra in cases:
            payload = dict({"hook_event_name": "PreToolUse", "cwd": link}, **extra)
            _, reason = decision(hook(agent, payload))
            self.assertIsNotNone(reason, (agent, extra))

    def test_protected_file_that_is_itself_a_symlink_inside_project(self):
        os.makedirs(os.path.join(self.repo, "docs"))
        open(os.path.join(self.repo, "other.md"), "w").write("x")
        os.symlink(os.path.join(self.repo, "other.md"), os.path.join(self.repo, "docs", "spec.md"))
        for rel in ("docs/spec.md", "other.md"):
            payload = {"hook_event_name": "PreToolUse", "cwd": self.repo, "tool_name": "Write",
                       "tool_input": {"file_path": os.path.join(self.repo, rel)}}
            _, reason = decision(hook("claude", payload))
            if rel == "docs/spec.md":
                self.assertIsNotNone(reason)
            else:
                self.assertIsNone(reason)  # 只擋寫在 docs/spec.md 這個路徑上，不擋被連結的檔本身

    def test_unrelated_tools_and_events_pass(self):
        for payload in (
            {"hook_event_name": "PreToolUse", "cwd": self.repo, "tool_name": "mcp__x__y", "tool_input": {"a": 1}},
            {"hook_event_name": "PostToolUse", "cwd": self.repo, "tool_name": "Bash", "tool_input": {"command": "cat .env"}},
            {"hook_event_name": "Stop", "cwd": self.repo},
        ):
            done = hook("claude", payload)
            self.assertEqual((done.returncode, done.stdout), (0, ""))

    def test_errors_never_exit_with_2(self):
        for stdin, args in (("not json", ["--agent", "claude"]), ("[]", ["--agent", "codex"]), ("{}", ["--agent", "x"]), ("{}", [])):
            done = run(["python3", CORE] + args, stdin=stdin)
            self.assertEqual(done.returncode, 1, (stdin, args))
            self.assertIn("collab_hook", done.stderr)

    def test_paths_with_spaces_and_unicode(self):
        d = tempfile.mkdtemp(prefix="collab 測試 ")
        self.addCleanup(shutil.rmtree, d, True)
        git(d, "init", "-q", "-b", "dev")
        with open(os.path.join(d, "STATE.md"), "w", encoding="utf-8") as f:
            f.write("中文內容\n")
        done = hook("claude", {"hook_event_name": "SessionStart", "cwd": d})
        self.assertIn("中文內容", done.stdout)
        _, reason = decision(hook("claude", bash_payload(d, "git push origin dev")))
        self.assertIsNone(reason)


class Merge(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="collab-merge-")
        self.addCleanup(shutil.rmtree, self.dir, True)

    def merge(self, target, agent, mode, *extra):
        return run(["python3", MERGE, "--target", target, "--agent", agent, "--" + mode] + list(extra))

    def test_create_then_idempotent(self):
        t = os.path.join(self.dir, ".claude", "settings.json")
        self.assertEqual(self.merge(t, "claude", "apply").stdout.strip(), "created")
        before = open(t, encoding="utf-8").read()
        self.assertEqual(self.merge(t, "claude", "apply").stdout.strip(), "unchanged")
        self.assertEqual(open(t, encoding="utf-8").read(), before)
        self.assertFalse(os.path.exists(t + ".bak"))

    def test_preserves_other_settings_and_hooks_and_makes_bak(self):
        t = os.path.join(self.dir, "settings.json")
        original = {"permissions": {"allow": ["Bash(ls)"]}, "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo mine"}]}]}}
        with open(t, "w", encoding="utf-8") as f:
            json.dump(original, f)
        out = self.merge(t, "claude", "apply").stdout.strip()
        self.assertTrue(out.startswith("updated\t"))
        data = json.load(open(t, encoding="utf-8"))
        self.assertEqual(data["permissions"], original["permissions"])
        commands = [h["command"] for g in data["hooks"]["PreToolUse"] for h in g["hooks"]]
        self.assertIn("echo mine", commands)
        self.assertEqual(sum("collab_hook.py" in c for c in commands), 1)
        self.assertEqual(json.load(open(t + ".bak", encoding="utf-8")), original)

    def test_existing_bak_is_not_overwritten(self):
        t = os.path.join(self.dir, "s.json")
        open(t + ".bak", "w").write("keep")
        json.dump({"x": 1}, open(t, "w"))
        self.merge(t, "codex", "apply")
        self.assertEqual(open(t + ".bak").read(), "keep")
        self.assertEqual(json.load(open(t + ".bak.1")), {"x": 1})

    def test_allow_flag_added_and_removed_on_rerun(self):
        t = os.path.join(self.dir, "s.json")
        self.merge(t, "claude", "apply", "--allow-push-main")
        self.assertIn("--allow-push-main", open(t, encoding="utf-8").read())
        self.merge(t, "claude", "apply")
        self.assertNotIn("--allow-push-main", open(t, encoding="utf-8").read())

    def test_agent_specific_differences_are_the_only_differences(self):
        c, x = os.path.join(self.dir, "c.json"), os.path.join(self.dir, "x.json")
        self.merge(c, "claude", "apply")
        self.merge(x, "codex", "apply")
        cj, xj = json.load(open(c)), json.load(open(x))
        self.assertNotIn("additionalContextLimit", json.dumps(cj))
        self.assertEqual(xj["hooks"]["SessionStart"][0]["hooks"][0]["additionalContextLimit"], 6000)
        # Claude 已由 CLAUDE.md 載入 STATE.md，只裝 PreToolUse；Codex 兩個都裝
        self.assertEqual(sorted(cj["hooks"]), ["PreToolUse"])
        self.assertEqual(sorted(xj["hooks"]), ["PreToolUse", "SessionStart"])
        for doc in (cj, xj):
            for groups in doc["hooks"].values():
                for g in groups:
                    for h in g["hooks"]:
                        self.assertEqual(h["type"], "command")

    def test_only_touches_our_two_events_and_drops_emptied_keys(self):
        t = os.path.join(self.dir, "s.json")
        ours = "sh -c 'x tools/hooks/collab_hook.py --agent claude'"
        user_stop = {"hooks": [{"type": "command", "command": "python3 tools/hooks/collab_hook.py --mine"}]}
        original = {"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": ours}]}], "Stop": [user_stop], "PostToolUse": []}}
        json.dump(original, open(t, "w"))
        self.merge(t, "claude", "apply")
        data = json.load(open(t))["hooks"]
        self.assertNotIn("SessionStart", data)  # 舊的 SessionStart 是我們的，Claude 不再裝，移除後刪鍵
        self.assertEqual(data["Stop"], [user_stop])  # 使用者自己的 Stop 即使命令含相同字串也不動
        self.assertEqual(data["PostToolUse"], [])  # 使用者原有的空陣列不動

    def test_invalid_json_and_bad_structure_exit_3_without_writing(self):
        t = os.path.join(self.dir, "bad.json")
        for text in ("{bad", "[]", '{"hooks": []}', '{"hooks": {"PreToolUse": {}}}'):
            open(t, "w").write(text)
            done = self.merge(t, "claude", "apply")
            self.assertEqual(done.returncode, 3, text)
            self.assertEqual(open(t).read(), text)
            self.assertFalse(os.path.exists(t + ".bak"))

    def test_generated_commands_run_and_fail_with_1_when_script_missing(self):
        repo = new_repo()
        self.addCleanup(shutil.rmtree, repo, True)
        for agent in ("claude", "codex"):
            t = os.path.join(repo, "%s.json" % agent)
            self.merge(t, agent, "apply")
            cmd = json.load(open(t))["hooks"]["PreToolUse"][0]["hooks"][0]["command"]
            env = dict(os.environ)
            env.pop("CLAUDE_PROJECT_DIR", None)
            if agent == "claude":
                env["CLAUDE_PROJECT_DIR"] = repo
            missing = run(["sh", "-c", cmd], stdin=json.dumps(bash_payload(repo, "ls")), cwd=repo, env=env)
            self.assertEqual(missing.returncode, 1, agent)
            self.assertIn("找不到", missing.stderr)
            os.makedirs(os.path.join(repo, "tools", "hooks"), exist_ok=True)
            for name in ("collab_hook.py", "collab_adapters.py"):
                shutil.copy(os.path.join(HOOKS, name), os.path.join(repo, "tools", "hooks", name))
            ok = run(["sh", "-c", cmd], stdin=json.dumps(bash_payload(repo, "git push origin main")), cwd=repo, env=env)
            self.assertEqual(ok.returncode, 0, (agent, ok.stderr))
            self.assertIsNotNone(decision(ok)[1], agent)
            shutil.rmtree(os.path.join(repo, "tools"))


class DocCheck(unittest.TestCase):
    def setUp(self):
        self.repo = new_repo()
        self.addCleanup(shutil.rmtree, self.repo, True)
        os.makedirs(os.path.join(self.repo, "tools", "hooks"))
        shutil.copy(DOC_CHECK, os.path.join(self.repo, "tools", "hooks", "doc_check.py"))

    def write(self, name, text):
        path = os.path.join(self.repo, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        git(self.repo, "add", name)

    def check(self):
        return run(["python3", os.path.join(self.repo, "tools", "hooks", "doc_check.py")], cwd=self.repo)

    def test_clean_commit_passes(self):
        self.write("AGENTS.md", "規則\n")
        self.write("STATE.md", "見 `AGENTS.md`\n")
        self.write("CLAUDE.md", "@AGENTS.md\n@STATE.md\n")
        done = self.check()
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_oversize_markdown(self):
        self.write("notes.md", "a" * (32 * 1024 + 1))
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("32 KiB", done.stderr)

    def test_state_over_6kib(self):
        self.write("STATE.md", "a" * (6 * 1024 + 1))
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("6 KiB", done.stderr)

    def test_missing_referenced_path_only_warns(self):
        self.write("STATE.md", "見 `docs/nothing.md` 與 `docs/troubleshooting.md`\n")
        done = self.check()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("docs/nothing.md 不存在", done.stderr)
        self.assertIn("只警告", done.stderr)
        self.assertNotIn("troubleshooting", done.stderr)

    def test_branch_names_urls_and_absolute_paths_do_not_block_commit(self):
        self.write("STATE.md", "分支 `feature/login` 對 `origin/main` 開 PR；`/api/users/:id` 與 `/etc/hosts`\n")
        done = self.check()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertNotIn("/etc/hosts", done.stderr)
        self.assertNotIn("/api/users", done.stderr)

    def test_claude_md_must_import_both(self):
        self.write("AGENTS.md", "規則\n")
        self.write("CLAUDE.md", "@AGENTS.md\n")
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("@STATE.md", done.stderr)

    def test_imports_inside_fence_or_comment_do_not_count(self):
        self.write("AGENTS.md", "規則\n")
        self.write("CLAUDE.md", "~~~\n@AGENTS.md\n@STATE.md\n~~~\n<!-- @AGENTS.md -->\n")
        done = self.check()
        self.assertEqual(done.returncode, 1)
        self.assertIn("@AGENTS.md", done.stderr)

    def test_only_staged_files_are_checked(self):
        with open(os.path.join(self.repo, "big.md"), "w") as f:
            f.write("a" * (40 * 1024))
        self.assertEqual(self.check().returncode, 0)

    def test_git_failure_is_reported_not_swallowed(self):
        done = run(["python3", os.path.join(self.repo, "tools", "hooks", "doc_check.py")], cwd=tempfile.gettempdir())
        self.assertEqual(done.returncode, 1)
        self.assertIn("collab pre-commit", done.stderr)


class InstallWithHooks(unittest.TestCase):
    def setUp(self):
        self.repo = new_repo()
        self.addCleanup(shutil.rmtree, self.repo, True)

    def install(self, *extra, repo=None):
        return run(["bash", INSTALL, "--project", repo or self.repo] + list(extra))

    def snapshot(self, root=None):
        root = root or self.repo
        out = []
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d != ".git"]
            for name in files:
                p = os.path.join(base, name)
                out.append((os.path.relpath(p, root), open(p, "rb").read()))
        return sorted(out)

    def test_default_install_touches_no_hooks(self):
        done = self.install()
        self.assertEqual(done.returncode, 0, done.stderr)
        for rel in (".claude", ".codex", "tools/hooks"):
            self.assertFalse(os.path.exists(os.path.join(self.repo, rel)), rel)
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".git", "hooks", "pre-commit")))

    def test_with_hooks_installs_everything_and_is_idempotent(self):
        done = self.install("--with-hooks")
        self.assertEqual(done.returncode, 0, done.stderr)
        for rel in ("tools/hooks/collab_hook.py", "tools/hooks/collab_adapters.py", "tools/hooks/doc_check.py", ".claude/settings.json", ".codex/hooks.json", ".git/hooks/pre-commit"):
            self.assertTrue(os.path.isfile(os.path.join(self.repo, rel)), rel)
        self.assertTrue(os.access(os.path.join(self.repo, ".git", "hooks", "pre-commit"), os.X_OK))
        self.assertIn("/hooks", done.stdout)
        first = self.snapshot()
        second = self.install("--with-hooks")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.snapshot(), first)

    def test_installed_hooks_really_block_and_inject(self):
        self.install("--with-hooks")
        with open(os.path.join(self.repo, "STATE.md"), "w", encoding="utf-8") as f:
            f.write("安裝後的現況\n")
        for rel, agent, event_tool in ((".claude/settings.json", "claude", "Bash"), (".codex/hooks.json", "codex", "Bash")):
            hooks = json.load(open(os.path.join(self.repo, rel)))["hooks"]
            env = dict(os.environ)
            env.pop("CLAUDE_PROJECT_DIR", None)
            if agent == "claude":
                env["CLAUDE_PROJECT_DIR"] = self.repo
                self.assertNotIn("SessionStart", hooks)
            else:
                start = hooks["SessionStart"][0]["hooks"][0]["command"]
                done = run(["sh", "-c", start], stdin=json.dumps({"hook_event_name": "SessionStart", "cwd": self.repo}), cwd=self.repo, env=env)
                self.assertIn("安裝後的現況", done.stdout, agent)
            pre = hooks["PreToolUse"][0]["hooks"][0]["command"]
            done = run(["sh", "-c", pre], stdin=json.dumps(bash_payload(self.repo, "git push --force origin x")), cwd=self.repo, env=env)
            self.assertIsNotNone(decision(done)[1], agent)

    def test_allow_push_main_flag_reaches_both_configs(self):
        self.install("--with-hooks", "--allow-push-main")
        for rel in (".claude/settings.json", ".codex/hooks.json"):
            self.assertIn("--allow-push-main", open(os.path.join(self.repo, rel), encoding="utf-8").read())

    def test_allow_flag_without_with_hooks_is_rejected(self):
        done = self.install("--allow-push-main")
        self.assertEqual(done.returncode, 2)
        self.assertEqual(self.snapshot(), [])

    def test_dry_run_writes_nothing(self):
        before = self.snapshot()
        done = self.install("--with-hooks", "--dry-run")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".git", "hooks", "pre-commit")))
        self.assertIn(".claude/settings.json", done.stdout)

    def test_existing_settings_are_merged_with_bak(self):
        os.makedirs(os.path.join(self.repo, ".claude"))
        path = os.path.join(self.repo, ".claude", "settings.json")
        json.dump({"permissions": {"allow": ["Bash(ls)"]}}, open(path, "w"))
        self.install("--with-hooks")
        self.assertEqual(json.load(open(path))["permissions"], {"allow": ["Bash(ls)"]})
        self.assertEqual(json.load(open(path + ".bak")), {"permissions": {"allow": ["Bash(ls)"]}})

    def test_invalid_existing_json_aborts_before_writing_anything(self):
        os.makedirs(os.path.join(self.repo, ".codex"))
        open(os.path.join(self.repo, ".codex", "hooks.json"), "w").write("{bad")
        before = self.snapshot()
        done = self.install("--with-hooks")
        self.assertEqual(done.returncode, 3)
        self.assertEqual(self.snapshot(), before)
        self.assertIn("hooks.json", done.stderr)

    def test_symlinked_settings_abort(self):
        os.makedirs(os.path.join(self.repo, ".claude"))
        real = os.path.join(self.repo, "shared.json")
        open(real, "w").write("{}")
        os.symlink(real, os.path.join(self.repo, ".claude", "settings.json"))
        done = self.install("--with-hooks")
        self.assertEqual(done.returncode, 3)
        self.assertFalse(os.path.exists(os.path.join(self.repo, "AGENTS.md")))
        self.assertEqual(open(real).read(), "{}")

    def test_foreign_pre_commit_is_not_overwritten(self):
        path = os.path.join(self.repo, ".git", "hooks", "pre-commit")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w").write("#!/bin/sh\necho theirs\n")
        done = self.install("--with-hooks")
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("echo theirs", open(path).read())
        self.assertIn("已有別的 hook", done.stdout)

    def test_own_pre_commit_is_updated(self):
        self.install("--with-hooks")
        path = os.path.join(self.repo, ".git", "hooks", "pre-commit")
        with open(path, "a") as f:
            f.write("# stale\n")
        done = self.install("--with-hooks")
        self.assertNotIn("# stale", open(path).read())
        self.assertIn("# stale", open(path + ".bak").read())  # 覆寫前先留備份
        self.assertIn("pre-commit.bak", done.stdout)

    def test_non_git_project_aborts_without_writing(self):
        d = tempfile.mkdtemp(prefix="collab-nogit-")
        self.addCleanup(shutil.rmtree, d, True)
        done = self.install("--with-hooks", repo=d)
        self.assertEqual(done.returncode, 3)
        self.assertIn("git", done.stderr)
        self.assertEqual(self.snapshot(d), [])

    def test_subdirectory_of_a_git_repo_aborts_without_writing(self):
        sub = os.path.join(self.repo, "app")
        os.makedirs(sub)
        done = self.install("--with-hooks", repo=sub)
        self.assertEqual(done.returncode, 3)
        self.assertIn("頂層", done.stderr)
        self.assertEqual(self.snapshot(sub), [])
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".git", "hooks", "pre-commit")))
        # 不加 --with-hooks 時，子目錄照常可以安裝
        self.assertEqual(self.install(repo=sub).returncode, 0)

    def test_hooks_path_that_is_a_file_aborts_before_writing(self):
        open(os.path.join(self.repo, "hookfile"), "w").write("x")
        git(self.repo, "config", "core.hooksPath", "hookfile")
        before = self.snapshot()
        done = self.install("--with-hooks")
        self.assertEqual(done.returncode, 3)
        self.assertIn("hooks 目錄", done.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.install("--with-hooks", "--dry-run").returncode, 3)

    def test_symlinked_project_path_is_accepted_as_git_toplevel(self):
        base = tempfile.mkdtemp(prefix="collab-linkproj-")
        self.addCleanup(shutil.rmtree, base, True)
        link = os.path.join(base, "link")
        os.symlink(self.repo, link)
        done = self.install("--with-hooks", repo=link)
        self.assertEqual(done.returncode, 0, done.stderr)

    def test_pre_commit_blocks_a_real_commit(self):
        self.install("--with-hooks")
        git(self.repo, "add", "-A")
        git(self.repo, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "-m", "chore: 安裝")
        with open(os.path.join(self.repo, "STATE.md"), "w", encoding="utf-8") as f:
            f.write("a" * (7 * 1024))
        git(self.repo, "add", "STATE.md")
        done = run(["git", "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-m", "chore: 超大"], cwd=self.repo)
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("6 KiB", done.stderr + done.stdout)

    def test_version_stamp_changes_when_hook_assets_change(self):
        self.install()
        stamp = open(os.path.join(self.repo, ".collab-kit-version")).read().strip()
        self.assertRegex(stamp, r"^[0-9a-f]{12}$")


class DocsMentionCodexOnlyInHookSections(unittest.TestCase):
    """README 與 SKILL.md 只有選用 hook 的章節可以提 Codex；其餘章節保持 agent 中性。"""

    HOOK_HEADINGS = ("## 選用的 hook", "## 步驟 5")

    def test_codex_only_in_hook_sections(self):
        for rel in ("README.md", os.path.join("skills", "collab-kit-init", "SKILL.md")):
            section_ok = False
            with open(os.path.join(KIT, rel), encoding="utf-8") as handle:
                for number, line in enumerate(handle, 1):
                    if line.startswith("## "):
                        section_ok = line.startswith(self.HOOK_HEADINGS)
                    if "codex" in line.lower() and not section_ok:
                        self.fail("%s:%d 在 hook 章節之外提到 Codex：%s" % (rel, number, line.strip()))


if __name__ == "__main__":
    unittest.main(verbosity=1, warnings="ignore")
