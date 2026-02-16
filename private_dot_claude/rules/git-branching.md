---
description: Branch strategy auto-detection (GitFlow / GitHub Flow) and naming conventions
globs: "**"
---

# Git Branching Rules

## Branch Strategy Detection

Detect the branching strategy automatically:
- `develop` branch exists (`git branch -a | grep -E '(^|\/)develop$'`) → **GitFlow**
- No `develop` branch → **GitHub Flow**

## GitFlow Branch Rules

| Type | Naming | Base | Merge Target |
|---------|------------------------|---------|-----------------|
| feature | `feature/<name>` | develop | develop |
| release | `release/<version>` | develop | main + develop |
| hotfix | `hotfix/<name>` | main | main + develop |

## GitHub Flow Branch Rules

| Type | Naming | Base | Merge Target |
|---------|-------------------|------|-----------------|
| feature | `feature/<name>` | main | main (via PR) |
| hotfix | `hotfix/<name>` | main | main (via PR) |

## Naming Conventions

- Lowercase, hyphen-separated: `feature/add-user-auth`
- Include Issue number when available: `feature/123-add-user-auth`
- Keep names concise but descriptive
- Valid prefixes: `feature/`, `hotfix/`, `release/`, `bugfix/`, `chore/`
