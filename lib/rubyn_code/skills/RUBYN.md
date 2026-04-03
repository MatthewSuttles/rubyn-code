# Layer 5: Skills

112 curated markdown skill documents loaded on demand.

## Classes

- **`Catalog`** — Discovers all skill files under `skills/` and builds a searchable index.
  Maps slash-names (`/factory-bot`) to file paths. No registration needed — drop a `.md`
  file in the right category directory and it's discoverable.

- **`Loader`** — Loads a skill document by name, returns its content. Caches loaded skills
  in the `skills_cache` SQLite table to avoid repeated file reads.

- **`Document`** — Value object representing a loaded skill: name, category, content, path.

## Adding a Skill

1. Create `skills/<category>/my-skill.md`
2. It auto-discovers. That's it.
