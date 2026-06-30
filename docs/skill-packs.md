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

Fetching pack 'hotwire' from registry...
  Downloading 14 skill files...
  → hotwire/turbo_drive.md
  → hotwire/turbo_frames.md
  → hotwire/turbo_streams.md
  → hotwire/stimulus_controllers.md
  ...

Installed 14 skills to ~/.rubyn-code/skill-packs/hotwire/
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

```
rubyn > /install-skills hotwire

rubyn > /install-skills hotwire stripe sidekiq
```

**What happens on install:**

1. Fetches pack metadata from the rubyn.ai registry
2. Downloads each skill file (unchanged files are skipped via ETag — see [ETag Caching](#etag-caching))
3. Writes files to `~/.rubyn-code/skill-packs/<pack>/`
4. Skills are immediately available — no restart needed

**Already installed:** if the pack is already present, Rubyn Code reports it
and suggests using `/remove-skills` first if you want to reinstall.

**CLI flag (outside the REPL):**

You can also install packs before starting a session using the `--install-skills`
CLI flag. This variant supports project-level installs and update operations:

```bash
# Install to the project directory (.rubyn-code/skills/<pack>/)
rubyn-code --install-skills hotwire

# Install multiple packs
rubyn-code --install-skills hotwire stripe sidekiq

# Install to the global directory (~/.rubyn-code/skills/) — available across all projects
rubyn-code --install-skills --global devise

# Update all installed packs to their latest versions
rubyn-code --install-skills --update

# Update a specific pack
rubyn-code --install-skills --update stripe
```

| CLI Flag | Description |
|----------|-------------|
| `--global` | Install to `~/.rubyn-code/skills/` instead of the project `.rubyn-code/skills/` directory. Packs installed globally are available across all projects on this machine. |
| `--update` | Update installed packs without prompting. When used alone, updates all installed packs. When combined with a pack name, updates that pack only. |

> **Note:** `--global` and `--update` are only available as CLI flags
> (`rubyn-code --install-skills`). They are not options to the REPL
> `/install-skills` command.

---

### `/skills`

List loaded skills and browse or search the registry.

**Subcommands:**

| Usage | Description |
|-------|-------------|
| `/skills` | List all loaded skills — built-in and installed community packs |
| `/skills available` | Fetch and display all packs from the rubyn.ai registry |
| `/skills search <term>` | Search the registry for packs matching a keyword |

**`/skills` — list loaded skills:**

```
rubyn > /skills

Loaded skills (126 total)

  Built-in (112)
    design_patterns: adapter, builder, decorator, observer, ...
    rails: action_cable, active_record, controllers, ...
    rspec: factories, mocking, shared_examples, ...
    ruby: blocks, classes, concurrency, ...

  Community: hotwire (14)
```

If no community packs are installed:

```
  Community: none installed
  Run /skills available to browse, or /install-skills <name> to install.
```

**`/skills available` — browse the registry:**

```
rubyn > /skills available

  Auth
    devise               OAuth, JWT, confirmable, security hardening  (8 skills) ✓

  Background
    sidekiq              Job patterns, queues, retries, batches       (8 skills)

  Frontend
    hotwire              Turbo Drive, Frames, Streams, Stimulus       (14 skills) ✓
    view-component       Components, slots, previews, Stimulus        (7 skills)

  Install with: /install-skills <name>
```

Installed packs are marked with ✓. Requires network access to rubyn.ai.

**`/skills search <term>` — search the registry:**

```
rubyn > /skills search stripe

Packs matching 'stripe' (1)
  stripe — Stripe payments in Rails: intents, webhooks, subscriptions
```

Searches pack names, descriptions, and tags. Requires network access.

---

### `/remove-skills`

Remove an installed skill pack.

```
/remove-skills <name> [name2] [name3]
```

**Example:**

```
rubyn > /remove-skills hotwire

Removed skill pack 'hotwire'.
```

> **Removing CLI-installed packs:** Packs installed via
> `rubyn-code --install-skills --global` live in `~/.rubyn-code/skills/`.
> Remove them by deleting the directory:
> ```bash
> rm -rf ~/.rubyn-code/skills/devise
> ```

---

## Installation Directories

Where files land depends on how the pack was installed:

| Method | Location | Scope |
|--------|----------|-------|
| `/install-skills <name>` (REPL) | `~/.rubyn-code/skill-packs/<name>/` | Machine-wide |
| `rubyn-code --install-skills <name>` (CLI) | `.rubyn-code/skills/<name>/` | Project only |
| `rubyn-code --install-skills --global <name>` (CLI) | `~/.rubyn-code/skills/<name>/` | Machine-wide |

When the same pack exists at both the project and global level, the project-level
version takes precedence.

---

## Auto-Suggestion

When you open a file or start a conversation, Rubyn Code checks the gems in your
`Gemfile` against the skill pack registry. If a pack exists for a gem you have
installed but haven't loaded, Rubyn Code suggests it:

```
Tip: You have 'sidekiq' in your Gemfile. Install the sidekiq skill pack for
job patterns and best practices:
  /install-skills sidekiq
```

Auto-suggestions appear once per session per pack and are suppressed after
installation. They do not run in offline mode.

---

## Offline Mode

All installed skill files are cached locally. If you have previously installed
a pack, it works fully offline — no network access required.

**What works offline:**

- All installed packs load and activate normally
- `/skills` lists your installed packs
- `/remove-skills` removes packs

**What requires network access:**

- `/install-skills` (fetching new packs)
- `/skills available` (browsing the registry)
- `/skills search <term>` (searching the registry)
- Pack updates via `rubyn-code --install-skills --update`

If a network request fails, Rubyn Code reports the error and continues. Installed
packs are unaffected.

---

## ETag Caching

Rubyn Code uses HTTP ETags to avoid re-downloading skill files that haven't
changed. Update runs are fast: only modified files are fetched.

**How it works:**

1. On first install, the server returns an ETag for each file
2. ETags are stored alongside the pack files in `.etags.json`
3. On subsequent updates, Rubyn Code sends `If-None-Match` headers
4. The server returns `304 Not Modified` for unchanged files — no download
5. Changed files return a new ETag and updated content

ETag cache locations:

| Install method | Cache file |
|----------------|------------|
| REPL `/install-skills` | `~/.rubyn-code/skill-packs/.etags.json` |
| CLI `--install-skills` (project) | `.rubyn-code/skills/.etags.json` |
| CLI `--install-skills --global` | `~/.rubyn-code/skills/.etags.json` |

Running `rubyn-code --install-skills --update` on an up-to-date pack typically
downloads zero bytes.

---

## How Skills Load

Skills load automatically based on triggers defined in each skill file's
frontmatter. A trigger fires when:

- You ask a question containing a matching keyword or phrase
- You open or edit a file that references a matching class or method name
- A gem in your `Gemfile` matches the skill's `gems` field

Skills load into context on demand — not all at startup. The system prompt stays
lean; skills appear only when relevant.

---

## Available Packs

Run `/skills available` to browse the current catalog, or visit
[rubyn.ai/skills](https://rubyn.ai/skills) to browse online.

### Wave 1 Packs

| Pack | Description |
|------|-------------|
| `devise` | Authentication, OAuth, confirmable, security hardening |
| `graphql-ruby` | Schema design, resolvers, mutations, subscriptions |
| `hotwire` | Turbo Drive, Frames, Streams, Stimulus controllers |
| `kamal` | Deploy configuration, secrets, zero-downtime deploys |
| `pundit` | Policy objects, scopes, authorization patterns |
| `sidekiq` | Job patterns, queues, retries, batches, testing |
| `stripe` | Payment intents, webhooks, subscriptions, testing |
| `view-component` | Components, slots, previews, Stimulus integration |

---

## Project-Specific Skills

You can add custom skill files to your project without going through the
registry. Place `.md` files with valid YAML frontmatter in:

```
.rubyn-code/skills/<category>/<skill-name>.md
```

These load alongside installed packs. The `triggers` frontmatter field is
required for auto-loading to work.

---

## Authentication

Installing and updating packs does not require authentication. The rubyn.ai
registry is publicly readable.

If you have a Rubyn account, log in to unlock:

- Pack usage analytics
- Private organization packs
- PR review integration (GitHub App)

---

## Troubleshooting

### Pack won't install

```
rubyn > /install-skills hotwire
Registry error: Failed to fetch pack 'hotwire': ...
```

- Check your network connection
- Verify the pack name: `/skills available`
- Try again — transient network errors are common

### Skills not loading after install

Skills activate on matching triggers. If a skill isn't loading:

- Run `/skills` to confirm the pack is listed under "Community"
- Ask about a topic the pack covers, or open a file that imports the gem
- Check that the pack directory exists: `ls ~/.rubyn-code/skill-packs/`

### Pack already installed warning

```
Pack 'hotwire' is already installed. Use /remove-skills first to reinstall.
```

Run `/remove-skills hotwire` then `/install-skills hotwire`.

### Offline and can't install

New installs require a connection to rubyn.ai. Packs already installed work
fully offline. There is no offline install from a local archive.

### Stale ETag cache

If a pack isn't updating after a registry release, force a full re-download by
removing its ETag cache and reinstalling:

```bash
# REPL-installed packs
rm ~/.rubyn-code/skill-packs/.etags.json

# CLI project-installed packs
rm .rubyn-code/skills/.etags.json
```

Then reinstall: `/remove-skills <name>` followed by `/install-skills <name>`.
