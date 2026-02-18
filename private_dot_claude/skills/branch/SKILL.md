---
name: branch
description: GitFlow/GitHub Flow に基づいてブランチを作成する。ブランチ作成やブランチの切り替えを依頼されたときに使用。
argument-hint: "[type] [name]"
---

# Branch Creation Skill

Create a branch following the project's branching strategy.

## Procedure

1. **Detect branching strategy**:
   ```bash
   git branch -a | grep -E '(^|\s|/)develop$'
   ```
   - Match found → GitFlow mode
   - No match → GitHub Flow mode

2. **Parse arguments**: Extract branch type and name from `$ARGUMENTS`
   - Format: `[type] [name]` (e.g., `feature user-auth` or `hotfix 456-login-fix`)
   - If type is omitted, default to `feature`
   - If name contains an issue number prefix (e.g., `123-desc`), preserve it

3. **Determine base branch**:

   **GitFlow:**
   | Type | Base Branch |
   |---------|-------------|
   | feature | develop |
   | release | develop |
   | hotfix | main |

   **GitHub Flow:**
   | Type | Base Branch |
   |---------|-------------|
   | feature | main |
   | hotfix | main |

4. **Fetch and create**:
   ```bash
   git fetch origin <base-branch>
   git checkout -b <type>/<name> origin/<base-branch>
   ```

5. **Confirm**: Show the created branch name and its base.

## Examples

- `/branch feature user-auth` → `feature/user-auth` from develop (GitFlow) or main (GitHub Flow)
- `/branch hotfix 123-fix-login` → `hotfix/123-fix-login` from main
- `/branch release 2.1.0` → `release/2.1.0` from develop (GitFlow only)
