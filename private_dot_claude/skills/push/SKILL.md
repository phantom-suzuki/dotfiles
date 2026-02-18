---
name: push
description: 安全なプッシュを実行する。プッシュを依頼されたときに使用。
disable-model-invocation: true
---

# Push Skill

Push commits to the remote repository with safety checks.

## Procedure

1. **Check for uncommitted changes**:
   ```bash
   git status
   ```
   - If there are uncommitted changes, warn the user and suggest committing first

2. **Check current branch**:
   ```bash
   git branch --show-current
   ```
   - If on a protected branch (main, master, develop, release/*): **warn and abort**
   - Ask the user to confirm if they really intend to push directly

3. **Show unpushed commits**:
   ```bash
   git log origin/<branch>..HEAD --oneline
   ```
   - If no unpushed commits exist, inform the user and stop

4. **Check remote status**:
   ```bash
   git fetch origin
   git status
   ```
   - If behind remote: suggest `git pull --rebase` before pushing
   - If diverged: suggest rebase and explain the situation

5. **Execute push**:
   ```bash
   git push origin <branch>
   ```
   - For new branches (no upstream): `git push -u origin <branch>`

6. **Force push handling**:
   - If normal push is rejected and force push is needed:
     - Explain why it's needed
     - Always use `--force-with-lease`, never `--force`
     - Require explicit user confirmation before executing

## Safety Rules

- Never force push to protected branches (main, master, develop, release/*)
- Never push with `--no-verify`
- Always show what will be pushed before executing
