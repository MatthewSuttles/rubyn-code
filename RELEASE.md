# Rubyn Code v0.9.0 — Phone a Friend

**Two models are better than one.**

This release adds `phone_a_friend`, a built-in tool that lets the agent ask a different model for a second opinion mid-task, and brings the README fully up to date with the Claude 5 defaults that shipped in v0.8.0.

---

## Phone a Friend

When the agent is stuck, weighing two approaches, or wants its reasoning sanity-checked, it can now consult a second model instead of spinning on the problem alone.

### How the friend is picked

The friend is chosen to maximize perspective diversity:

1. **Another configured provider first.** If a different provider's API key is present (say you run on Anthropic and have `OPENAI_API_KEY` set), the friend is that provider's top-tier model — a genuinely different model family with different blind spots.
2. **Escalate within the provider otherwise.** With no second provider available, the friend is the active provider's top-tier model, so a mid-tier session still gets its second opinion from the strongest model configured.

### What the friend sees

The consultation is deliberately narrow:

- **One shot** — a single question plus optional context, no follow-ups.
- **No tools** — the friend cannot touch the project.
- **No conversation history** — it sees only what the agent chooses to send, so the second opinion is not anchored on the first model's framing.

The friend is prompted to commit to a recommendation, explain the key reason, flag anything the agent may have missed, and say exactly what is missing if the context is insufficient. The answer returns as plain text labeled with the provider and model that gave it:

```
[tool] phone_a_friend
## Second Opinion — openai/gpt-5.4
Commit to the polymorphic association. The key reason: ...
```

Cross-provider calls build a fresh LLM client for the friend; same-provider calls reuse the active one. Failures degrade gracefully — a missing client, an empty answer, or a failed call each return a clear message instead of raising, and the tool is classified at the `external` risk level like the other network tools.

---

## Docs

The README is now fully current:

- The tagline, auth section, config examples, and model-router tier table all reflect the Claude 5 defaults (`claude-opus-5` default and top tier, `claude-sonnet-5` mid, `claude-haiku-4-5` cheap) instead of the 4.6-era models.
- The `/effort` and task-budget feature notes include Opus 5 in their supported-model lists.
- Tool tables and counts include `phone_a_friend`, `code_graph`, and `todo_write` — the built-in count is now 32 everywhere (the earlier tables still said 29 and were missing three tools).
- A new "Phone a Friend" section documents the second-opinion flow under Sub-Agents & Teams.

---

## Upgrade

```bash
gem update rubyn-code
```

Or from source:

```bash
cd rubyn-code
git pull
bundle install
ruby -Ilib exe/rubyn-code
```

### Breaking changes

None. `phone_a_friend` is additive; it makes no calls unless the agent invokes it, and it uses only providers you have already configured.

---

## Numbers

| Metric | Value |
|--------|-------|
| New tool | `phone_a_friend` |
| Built-in tools | 32 |
| Test examples | 2,846 |
| Failures | 0 |

---

## Full changelog

- Add `phone_a_friend` second-opinion tool; Executor injects the active LLM client (#155)
- README: document Phone a Friend and refresh all model references to the Claude 5 defaults (#157)
- README/ARCHITECTURE: add `code_graph` and `todo_write` to tool tables; fix stale tool counts (#155)
