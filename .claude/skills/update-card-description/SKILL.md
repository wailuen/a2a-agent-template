---
name: update-card-description
description: "Regenerate AGENT_DESCRIPTION in .env from current tool docstrings and skill descriptions so the agent card stays accurate for A2A registry semantic matching. Run before committing when tools or skills have changed."
---

# /update-card-description — refresh the agent card description

The agent card `description` field is what A2A registries use for semantic
matching — routing tasks to the right agent. When tools or skills are added,
removed, or renamed, this field goes stale unless updated.

This skill reads the current tools and skills, drafts a tight 1–2 sentence
description, and writes it to `AGENT_DESCRIPTION` in `.env`.

## Steps

### 1 — Scan tools

Read every `src/tools/*.py` file (skip `__init__.py`). For each file:

- Find all `@tools.tool(...)` decorated async functions.
- The tool description is the **first non-blank line of the function's
  docstring**. Collect `(tool_name, one_line_description)` for each.
- Note the `tier=` value: tier 1 = accessible via MCP + A2A; tier 2 = A2A only.

If `src/tools/` is absent or has no decorated functions, note it and skip.

### 2 — Scan skills

Read every `src/skills/*.md` file. For each:

- Extract the `description:` value from the YAML frontmatter (between `---` fences).
- Collect `(skill_name, description)`.

### 3 — Read current value

Read `AGENT_DESCRIPTION` from `.env` (empty string if absent or blank).
Show it to the developer alongside the incoming draft.

### 4 — Draft the description

Write a 1–2 sentence description (target: ≤ 200 characters) that:

- **Names the domain** — what real-world problem space the agent covers
  (e.g. "property climate risk", "M365 calendar & email", "investment research").
  Derive this from the tool docstrings and skill descriptions, not from the
  module file names.
- **Summarises the key actions** — what a caller can ask for, in plain language.
  Use the intent behind tool docstrings, not the function names themselves.
- **Omits implementation details** — no mention of SDK, A2A, MCP, SSE, etc.
  Registries match user tasks against this text; protocol words don't help.

Good example:
> "Retrieves climate risk scores, flood/fire exposure, and resilience metrics
> for any global property by address or coordinates."

Bad example:
> "An agent-sdk agent exposing get_risk_data and get_scores via A2A and MCP."

### 5 — Propose and confirm

Show the developer:

```
Current AGENT_DESCRIPTION: <current value or "(blank)">
Proposed:                  <draft>
```

Ask: "Write this to .env? [yes / edit / cancel]"

- **edit** — let the developer revise the draft inline, then confirm again.
- **cancel** — stop; make no changes.
- **yes** — proceed to step 6.

### 6 — Write to .env

Update `AGENT_DESCRIPTION=` in `.env` in-place:

- If the line exists: replace the value.
- If absent: append `AGENT_DESCRIPTION=<value>` before the first blank line
  after the `AGENT_NAME=` line, or at the end of the file if not found.
- Quote the value with double-quotes if it contains spaces or commas.
- Never modify any other line in `.env`.

### 7 — Verify and remind

Print the final written value. Then check:

```bash
grep '^AGENT_DESCRIPTION' .env
```

Remind the developer:
- `.env` is gitignored — the same value must be set in staging/prod environments
  (Azure Container App env vars, CI secret, etc.).
- The agent card is built at boot from this value; a restart is needed for
  registry consumers to see the new description.

## Notes

- This skill is safe to run repeatedly — it only touches the `AGENT_DESCRIPTION`
  line in `.env`.
- If the agent has multiple tool modules, combine descriptions from all of them.
- Skills in `src/skills/` are model-facing; their `description:` frontmatter
  is part of the agent's surface — include them in the draft.
- Run `/agent-verify` after updating to confirm the card at
  `/.well-known/agent-card.json` reflects the new description.
