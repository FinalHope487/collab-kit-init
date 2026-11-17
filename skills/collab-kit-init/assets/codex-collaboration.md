# ChatGPT and Codex Collaboration

## Cold review

Before push, review all code changes for the task in a clean session. Use `docs/spec.md`, the plan for the task in `docs/plans/`, and the new lines in `DECISIONS.md` as the review contract. Batches that only change documentation or tests are exempt.

Use ChatGPT first, then Codex, then a read-only Sonnet subagent if the other reviewers are unavailable. Use adversarial review for changes to public contracts, data formats, module boundaries, data flow, or documented design decisions.

Check each finding against the code. Give file and line evidence when a finding is incorrect. For a confirmed defect, write a test that reproduces it before the fix. Review the updated diff in a new clean session until the reviewer finds no issue that directly blocks further development.

## 名詞定義

- A blocking finding breaks an approved contract for a supported input, causes public entry points to disagree, loses or overwrites data, or requires a public interface change to complete approved follow-up work. Cite the contract or input and identify the affected work.
- A suggestion does not meet the blocking criteria. Add it to the backlog in `ROADMAP.md`.

## Rescue and limits

Use Codex rescue for independent work with separate file ownership. Give it the five fields from the delegation rules. Check the result before reporting it. If rescue is unavailable, do the work in the main session.

Use paid capacity only within the user's actual authorization. Record the approved tools, operations, and limits for this project. Report the number and purpose of Codex calls. Use the next review option if a tool is missing, unsigned in, over quota, or below the project's minimum remaining quota. For an error or timeout, check quota and retry once if quota permits. Report the fallback and its cause.
