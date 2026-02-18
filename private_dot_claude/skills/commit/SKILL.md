---
name: commit
description: Conventional Commits に準拠したコミットを作成する。コミットの作成を依頼されたときに使用。
disable-model-invocation: true
---

# Commit Skill

Create a Conventional Commits compliant commit.

## Procedure

1. **Check working tree status**:
   ```bash
   git status
   ```

2. **Check staged changes**:
   ```bash
   git diff --staged
   ```
   - If nothing is staged, show unstaged changes and suggest which files to `git add`
   - Never use `git add -A` or `git add .` — add specific files by name

3. **Review recent commit style**:
   ```bash
   git log --oneline -5
   ```

4. **Analyze changes and determine commit type**:
   | Type | When to Use |
   |----------|-------------------------------|
   | feat | New feature |
   | fix | Bug fix |
   | refactor | Code restructuring, no behavior change |
   | docs | Documentation only |
   | test | Adding or updating tests |
   | chore | Build, CI, dependencies, etc. |

5. **Generate commit message**:
   - Subject line: English, max 72 characters, imperative mood
   - Format: `<type>: <description>` or `<type>(<scope>): <description>`
   - Always append the Co-Authored-By trailer

6. **Execute commit** using HEREDOC for proper formatting:
   ```bash
   git commit -m "$(cat <<'EOF'
   <type>: <description>

   Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
   EOF
   )"
   ```

7. **Large changes**: If the staged changes span multiple logical units, propose splitting into separate commits.

## Rules

- 1 commit = 1 logical change
- Never commit files that may contain secrets (.env, credentials, etc.)
- Never amend a previous commit unless the user explicitly requests it
- If a pre-commit hook fails, fix the issue and create a NEW commit (do not --amend)
