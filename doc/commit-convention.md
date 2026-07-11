# Commit convention

Commits follow [Conventional Commits], kept deliberately terse.

## Pull requests format

Development happens through pull requests, merged one of two ways:

- **Squash** — when a step-by-step history doesn't matter. The PR title and description must follow the convention;
  the individual branch commits' format is **advisory**.
- **Rebase and merge** — when a detailed history matters. Both the PR and every commit must follow the convention.

## Commits format

These rules describe the commit format, which is based on [Conventional Commits]. Recommended commit format:

```
<type>: <short summary>
```

- Single line — no body, no footer.
- No `Co-Authored-By` trailer (or any co-authorship attribution).
- Imperative mood, lower case, no trailing period.
- Keep the summary short and clear.

When a commit genuinely needs more explanation, the fuller [Conventional Commits]
format (with a body/footer) is also acceptable.

## Types

| Type       | Use for                                              |
|------------|------------------------------------------------------|
| `feat`     | A new feature / public API addition                  |
| `fix`      | A bug fix                                            |
| `perf`     | A performance improvement (without changing the API) |
| `refactor` | Restructuring                                        |
| `docs`     | Documentation only                                   |
| `test`     | Tests only                                           |
| `style`    | Formatting only (no code meaning change)             |
| `chore`    | Maintenance (anything else)                          |

## Examples

```
feat: add zoom-based polyline simplification
fix: correct _distBtwn miscalculation
refactor: split RouteManager into engine and manager layers
docs: add readme, changelog and license
chore: remove orphaned quad_tree.dart left over from v7.0.0 merge
```

[Conventional Commits]: https://www.conventionalcommits.org/