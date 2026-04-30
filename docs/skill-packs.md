# Skill Packs

Skill packs extend Rubyn Code with domain-specific knowledge for popular gems,
patterns, and frameworks. Each pack is a curated set of markdown skills that load
on demand when you work with related code.

Rubyn Code ships with 112 built-in skills covering core Ruby, Rails, RSpec, and
design patterns. Skill packs add specialized knowledge for specific gems like
Hotwire, Stripe, Devise, Sidekiq, and more.

---

## Quick Start

```
rubyn > /install-skills hotwire

Fetching hotwire pack from rubyn.ai...
  Downloading 14 skill files...
  → hotwire/turbo_drive.md
  → hotwire/turbo_frames.md
  → hotwire/turbo_streams.md
  → hotwire/stimulus_controllers.md
  ...

Installed 14 skills to .rubyn-code/skills/hotwire/
These skills load on demand when you work with related code.
```

Once installed, skills activate automatically. When you ask about Turbo Frames or
edit a file containing `turbo_frame_tag`, the relevant skill loads into context.

---

## Commands

### `/install-skills`

Install one or more skill packs from the rubyn.ai registry.

```
/install-skills <name> [name2] [name3]
```

**Examples:**

```bash
# Install a single pack
/install-skills hotwire

# Install multiple packs at once
/install-skills hotwire stripe sidekiq

# Install to the global directory (~/.rubyn-code/skills/)
/install-skills --global devise

# Update all installed packs to their latest versions
/install-skills --update

# Update a specific pack
/install-skills --update stripe
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--global` | Install to `~/.rubyn-code/skills/` instead of the project directory. Global packs are available across all projects on this machine. |
| `--update` | Update installed packs without prompting. When used alone (`/install-skills --update`), updates all installed packs. When combined with a pack name (`/install-skills --update stripe`), updates that specific pack only. |

**What happens on install:**

1. Fetches pack metadata from the rubyn.ai registry
2. Downloads each skill file (skips unchanged files via ETag — see [ETag Caching](#etag-caching))
3. Writes files to `.rubyn-code/skills/<pack>/`
4. Skills are immediately available — no restart needed

**Version handling:**

- If a pack is already installed at the same version, it reports "up to date"
- If a newer version is available, it prompts you to update (or updates silently with `--update`)
- ETag caching means re-installs and updates only download files that actually changed

**CLI flag:**

You can also install packs from the terminal before starting a session:

```bash
rubyn-code --install-skills hotwire
```

---

### `/skills`

List all loaded skills — both built-in and community packs.

```
/skills
```

**Output:**

```
Loaded skills (126 total)

  Built-in (112)
    design_patterns: adapter, builder, decorator, observer, ...
    rails: action_cable, active_record, controllers, ...
    rspec: factories, mocking, shared_examples, ...
    ruby: blocks, classes, concurrency, ...

  Community: hotwire (14)

```

**Browse the registry:**

```
/skills --available
```

Lists all packs in the rubyn.ai registry, grouped by category. Installed packs
are marked with ✓.

```
Available skill packs (8)

  Auth
    devise               OAuth, JWT, confirmable, security hardening  (8 skills) ✓

  Background
    sidekiq              Job patterns, queues, retries, batches       (8 skills)

  Frontend
    hotwire              Turbo Drive, Frames, Streams, Stimulus       (14 skills) ✓
    view-component       Components, slots, previews, Stimulus        (7 skills)

  ...

  Install with: /install-skills <name>
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--available` | Fetch and display all packs from the rubyn.ai registry. Requires network access. |

---

### `/remove-skills`

Remove an installed skill pack.

```
/remove-skills <name>
```

**Example:**

```
rubyn > /remove-skills hotwire

Remove hotwire (14 skills)? This cannot be undone.
  Confirm (y/N): y

Removed skill pack 'hotwire'.
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--global` | Remove from the global directory (`~/.rubyn-code/skills/`) instead of the project directory. Required when the pack was installed with `--global`. |

---

## Installation Directories

Skill packs install to one of two locations:

| Location | Path | Scope | Default |
|----------|------|-------|---------|
| **Project** | `.rubyn-code/skills/<pack>/` | This project only | ✓ |
| **Global** | `~/.rubyn-code/skills/<pack>/` | All projects on this machine | Use `--global` |

**Project-level** is the default. The pack is version-controlled with your project,
so the whole team gets the same skills. Commit `.rubyn-code/skills/` to your
repository.

**Global** packs are useful for personal preferences or skills you want available
across all projects (e.g., your preferred testing framework conventions).

Project-level packs take precedence over global packs with the same name.

---

## Auto-Suggestion

When Rubyn Code starts in a project, it parses your `Gemfile` and checks the
registry for matching skill packs. If matches are found, you see a one-time
suggestion:

```
Skill packs available: stripe (stripe gem detected in Gemfile),
  sidekiq (sidekiq gem detected in Gemfile)
Run /install-skills stripe sidekiq to install.
```

Suggestions are shown **once per project per pack**. After you see a suggestion
(or install/dismiss the pack), it won't appear again. Suggestion state is tracked
in `.rubyn-code/suggested.json`.

**How suggestions work:**

- Parses all `gem` declarations from your `Gemfile`
- Queries the registry with those gem names
- Filters out packs you've already installed or dismissed
- Silently skips the check if the registry is unreachable (see [Offline Mode](#offline-mode))

---

## Offline Mode

Rubyn Code never blocks session start on a failed registry fetch. If rubyn.ai is
unreachable:

- **Already installed packs** continue to work normally from the local cache
- **`/install-skills`** shows a registry error but doesn't crash the session
- **`/skills --available`** shows a registry error; locally installed packs still list correctly
- **Auto-suggestions** are silently skipped for the session

The next time the registry is reachable, everything works as normal.

---

## ETag Caching

Each skill file download includes an HTTP ETag from the server. Rubyn Code stores
ETags in `.rubyn-code/skills/<pack>/.etags.json` alongside the skill files.

On subsequent installs or updates, each file is fetched with an
`If-None-Match: <etag>` header. If the file hasn't changed, the server responds
`304 Not Modified` and the local copy is kept — no download, no write. Only
files that actually changed are transferred.

**Practical effect:**

- `/install-skills --update` on an unchanged pack: fast, zero downloads
- Re-running `/install-skills hotwire` when it's already current: reports "up to date" immediately
- A pack with 14 skills where 2 changed: downloads exactly 2 files

The `.etags.json` file is an implementation detail. Don't edit it manually.

---

## How Skills Load

Installed skill packs work exactly like the built-in skills:

1. **On-demand loading:** Skills activate when you work with related code or ask
   about related topics. A Stripe skill loads when you ask about webhooks or edit
   a file with `Stripe::Webhook`.

2. **Trigger matching:** Each skill declares `triggers` in its YAML frontmatter —
   keywords and method names that signal relevance.

3. **TTL management:** Loaded skills expire after 5 turns of inactivity. Active
   skills (ones you're still referencing) stay loaded. This keeps the context
   window clean.

4. **Size cap:** Individual skills are capped at ~800 tokens. This prevents any
   single skill from consuming too much context.

5. **Shadowing:** Project-level skills with the same name as built-in skills take
   precedence. Community packs don't conflict with built-in skills because they
   cover different domains (specific gems vs. core Ruby/Rails).

For more on how skills work internally, see [Skills Authoring Guide](SKILLS.md).

---

## Available Packs

The registry at rubyn.ai hosts curated skill packs. Use `/skills --available` to
see the current catalog, or visit [rubyn.ai/skills](https://rubyn.ai/skills) to
browse online.

### Launch Packs

| Pack | Skills | Category | Gems |
|------|--------|----------|------|
| **hotwire** | 14 | Frontend | `turbo-rails`, `stimulus-rails` |
| **devise** | 8 | Authentication | `devise` |
| **sidekiq** | 8 | Background Jobs | `sidekiq` |
| **stripe** | 11 | Payments | `stripe`, `pay` |
| **graphql-ruby** | 9 | API | `graphql` |
| **view-component** | 7 | Frontend | `view_component` |
| **pundit** | 6 | Authorization | `pundit` |
| **kamal** | 7 | Infrastructure | `kamal` |

### Creating Your Own Packs

Want to contribute a pack for a gem you know well? See the
[Contributing Guide](https://github.com/Rubyn-AI/skill-packs/blob/main/CONTRIBUTING.md)
in the skill-packs repository.

---

## Project-Specific Skills

You can also write custom skills for your own project without publishing them to
the registry. Create markdown files in `.rubyn-code/skills/`:

```bash
mkdir -p .rubyn-code/skills
```

```markdown
# .rubyn-code/skills/our-api-patterns.md

---
name: our-api-patterns
description: API conventions for this project
tags: [api, conventions]
---

# API Design Patterns

## Authentication
All API endpoints use Bearer token authentication...
```

These load alongside built-in and community skills. See [Skills Authoring Guide](SKILLS.md)
for the full format reference.

---

## Troubleshooting

### Pack won't install

```
Registry error: Registry returned 403: ...
```

The rubyn.ai API requires a specific `Accept` header. This is sent automatically
by the CLI. If you see this error, make sure you're using the `/install-skills`
command rather than downloading pack files manually.

### Skills not loading after install

Skills should be available immediately after install. If they're not activating:

- Verify the pack installed: `/skills` should list it under "Community"
- Check the pack directory exists: `ls .rubyn-code/skills/<pack>/`
- Skills activate on matching triggers — ask about a topic the pack covers, or
  open a file that uses the relevant gem

### Offline and can't install

Rubyn Code caches all installed packs locally. If you've installed a pack before,
it works fully offline. New installs require a connection to rubyn.ai.

### Global vs project install confusion

Use `/skills` to see where each skill is loaded from. Project-level packs
(`.rubyn-code/skills/`) take precedence over global packs (`~/.rubyn-code/skills/`).

To remove a globally-installed pack, use the `--global` flag:

```
/remove-skills --global devise
```

### Stale ETag cache

If skills aren't updating after a pack release, force a full re-download by
removing the `.etags.json` file for that pack:

```bash
rm .rubyn-code/skills/<pack>/.etags.json
```

Then run `/install-skills --update <pack>` to re-fetch all files.
