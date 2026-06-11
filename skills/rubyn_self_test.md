---
name: self-test
description: Smoke test Rubyn-Code itself — exercises every major subsystem and reports a pass/fail scorecard
tags: [rubyn, testing, diagnostics]
---

# Rubyn Self-Test

Run a systematic smoke test of Rubyn-Code's major subsystems. Exercise each one, track pass/fail, and report a scorecard at the end.

## Instructions

When the user loads this skill (via `/skill self-test` or `load_skill name: "self-test"`), run through EVERY test below **in order**. For each test:

1. Run the described action using your tools
2. Record PASS or FAIL
3. If FAIL, note the error in one line
4. Keep going — don't stop on failures

At the end, print a scorecard like this:

```
Rubyn Self-Test Results
═══════════════════════════════════════════
 1. ✅ File read/write/edit cycle
 2. ✅ Glob file search
 3. ✅ Grep content search
 4. ❌ Run specs — exit code 1 (3 failures)
 5. ✅ Git status
 ...
═══════════════════════════════════════════
Score: 18/22 (82%) — 4 failures
```

## The Tests

### 1. Tool System — File Operations
- **read_file**: Read `lib/rubyn_code/version.rb`. PASS if it contains `VERSION =`.
- **write_file**: Write a temp file `.rubyn-code/self_test_tmp.rb` with content `# self-test`. PASS if no error.
- **edit_file**: Edit that temp file — replace `# self-test` with `# self-test passed`. PASS if no error.
- **read_file** (verify): Read the temp file back. PASS if it contains `# self-test passed`.
- **Cleanup**: Delete the temp file with bash `rm .rubyn-code/self_test_tmp.rb`.

### 2. Tool System — Search
- **glob**: Find all `*.rb` files under `lib/`. PASS if result contains at least 50 files.
- **grep**: Search for `class.*Base` across `lib/`. PASS if at least 3 matches found.

### 3. Tool System — Bash
- **bash**: Run `ruby --version`. PASS if output contains `ruby`.
- **bash**: Run `bundle exec rubocop --version`. PASS if output contains a version number.

### 4. Tool System — Git
- **git_status**: Run git status. PASS if no error.
- **git_log**: Run git log (last 3 commits). PASS if output contains commit hashes.
- **git_diff**: Run git diff. PASS if no error (even if empty).

### 5. Tool System — Specs
- **run_specs**: Run `bundle exec rspec spec/rubyn_code/tools/output_compressor_spec.rb --format progress`. PASS if output contains `0 failures`.
- **run_specs**: Run `bundle exec rspec spec/rubyn_code/llm/model_router_spec.rb --format progress`. PASS if output contains `0 failures`.

### 6. Context & Efficiency Engine

#### File Cache
- Read `lib/rubyn_code/version.rb` twice. PASS if both reads succeed (cache should serve the second).

#### Output Compressor — Head/Tail Strategy
- Run `bash` with `seq 1 5000` (generates 5,000 lines — well over the bash threshold of 4,000 chars). PASS if the result contains "lines omitted" or is significantly shorter than 5,000 lines. This proves the head_tail compressor is working.

#### Output Compressor — Spec Summary Strategy
- Run `bash` with `cd <project_root> && bundle exec rspec spec/rubyn_code/tools/base_spec.rb --format documentation 2>&1`. This produces multi-line RSpec output. PASS if the result you receive is shorter than the full verbose output — specifically check if passing specs got compressed to a summary line like "N examples, 0 failures" instead of listing every example.

#### Output Compressor — Grep Top Matches
- Run `grep` searching for `def ` across all of `lib/`. This will match hundreds of method definitions. PASS if the result contains "matches omitted" or shows only a subset of results (the compressor limits to top N matches).

#### Output Compressor — Glob Tree Collapse
- Run `glob` for `**/*.rb` across the entire project. With 170+ files this should exceed the glob threshold. PASS if the result shows directory summaries like `app/models/ (N files)` instead of listing every individual file path, OR if the result is significantly shorter than listing all 170+ paths individually.

#### Output Compressor — Diff Strategy
- Run `bash` with `cd <project_root> && git log --oneline -1 --format=%H | xargs git diff HEAD~5..` (diff of last 5 commits). If the diff is large enough, the compressor should keep headers but truncate bodies. PASS if result contains diff headers. SKIP if diff is small enough to pass through uncompressed.

#### Compression Stats
- After running the above tests, note whether any output you received contained truncation markers like "lines omitted", "matches omitted", or "files)". Count how many of the 5 compression strategies actually triggered. Report: "N/5 compression strategies verified active".

### 7. Skills System
- **load_skill**: Load any available skill (e.g., `classes`). PASS if content is returned.

### 8. Memory System
- **memory_write**: Write a test memory: `category: "test", content: "self-test at #{Time.now}"`. PASS if no error.
- **memory_search**: Search for `self-test`. PASS if the memory we just wrote is found.

### 9. Configuration
- **bash**: Run `cat ~/.rubyn-code/config.yml`. PASS if file exists and contains `provider:`.
- **read_file**: Check if `.rubyn-code/project_profile.yml` exists in the project root. PASS if exists (or SKIP if first session).

### 10. Codebase Index
- **bash**: Check if `.rubyn-code/codebase_index.json` exists. PASS if exists (or SKIP if first session).

### 11. Slash Commands (report only — don't execute)
- Report which slash commands are registered by reading `lib/rubyn_code/cli/commands/registry.rb` or the help output. PASS if at least 15 commands found.

### 12. MCP Integration
- **grep**: Search for `url:.*server_def` in `lib/rubyn_code/mcp/config.rb`. PASS if at least 1 match found (confirms SSE url is extracted — a critical bug was shipped without this).
- **grep**: Search for `autoload.*Mcp` in `lib/rubyn_code.rb`. PASS if found (confirms `/mcp` command is wired up).
- **run_specs**: Run `bundle exec rspec spec/rubyn_code/mcp/config_spec.rb --format progress`. PASS if output contains `0 failures`.
- **bash**: Check if `.rubyn-code/mcp.json` exists in the project root. PASS if exists, SKIP if not (MCP is optional per-project).

### 13. GOLEM Autonomous Mode
- **grep**: Search for `class Daemon` in `lib/rubyn_code/autonomous/daemon.rb`. PASS if found (confirms daemon framework exists).
- **grep**: Search for `failed\?` in `lib/rubyn_code/tasks/models.rb`. PASS if found (confirms failed task status is available).
- **grep**: Search for `total_cost` in `lib/rubyn_code/autonomous/daemon.rb`. PASS if at least 2 matches (confirms cost tracking is implemented).
- **run_specs**: Run `bundle exec rspec spec/rubyn_code/autonomous/daemon_spec.rb --format progress`. PASS if output contains `0 failures` (verifies lifecycle, retries, cost limits, audit trails, concurrent claiming).

### 14. Architecture Integrity
- **grep**: Search for `autoload` in `lib/rubyn_code.rb`. PASS if at least 40 autoload entries found.
- **glob**: Check that all 16 layer directories exist under `lib/rubyn_code/`. PASS if at least 14 found.
- **read_file**: Read `lib/rubyn_code.rb` and verify it has modules for Agent, Tools, Context, Skills, Memory, Observability, Learning. PASS if all 7 found.

### 15. Skill-Pack Autoload — Live Registry Roundtrip

End-to-end exercise of the autoload pipeline against the real registry at `rubyn.ai`: fetch the catalog, install a pack the user does **not** already have, verify it works on disk + in the catalog + through the matcher, then remove it. The user's pre-existing installed packs are not touched.

- **Live roundtrip**: `bash` with the script below. PASS if the final line is `ROUNDTRIP: PASS`. SKIP if the final line starts with `SKIP:` (means every registry pack is already installed locally — rare).

  ```bash
  bundle exec ruby -e '
    require_relative "lib/rubyn_code"

    client = RubynCode::Skills::RegistryClient.new
    pack_manager = RubynCode::Skills::PackManager.new

    catalog_packs = client.fetch_catalog[:data] || []
    abort "FAIL: empty registry catalog" if catalog_packs.empty?

    already_installed = catalog_packs.map { |p| p[:name] || p["name"] }
                                     .select { |n| pack_manager.installed?(n) }
    target = catalog_packs.find { |p| !already_installed.include?(p[:name] || p["name"]) }
    abort "SKIP: every registry pack is already installed" if target.nil?

    name = target[:name] || target["name"]
    puts "TEST PACK: #{name}"

    success = false
    begin
      result = client.fetch_pack(name)
      pack_manager.install(result[:data], etag: result[:etag])
      raise "install did not create directory" unless pack_manager.installed?(name)
      puts "STEP install: PASS"

      catalog_obj = RubynCode::Skills::Catalog.new(
        File.join(Dir.home, ".rubyn-code", "skill-packs")
      )
      skills = catalog_obj.available.select { |e| e[:path].include?("/#{name}/") }
      raise "catalog sees no skills" if skills.empty?
      raise "no skills have triggers" if skills.none? { |s| !s[:triggers].empty? }
      puts "STEP catalog: PASS (#{skills.size} skills, #{skills.count { |s| !s[:triggers].empty? }} with triggers)"

      sample = skills.find { |s| !s[:triggers].empty? }
      matcher = RubynCode::Skills::Matcher.new(catalog: catalog_obj)
      hits = matcher.match("question about #{sample[:triggers].first}")
      raise "matcher did not hit on \"#{sample[:triggers].first}\"" if hits.none? { |h| h[:name] == sample[:name] }
      puts "STEP matcher: PASS (hit \"#{sample[:name]}\" via \"#{sample[:triggers].first}\")"
      success = true
    ensure
      pack_manager.remove(name)
      if pack_manager.installed?(name)
        puts "STEP cleanup: FAIL (pack still on disk)"
      else
        puts "STEP cleanup: PASS"
      end
    end

    puts(success ? "ROUNDTRIP: PASS" : "ROUNDTRIP: FAIL")
  '
  ```

  The script:
  1. Fetches the registry catalog (proves the static API at `rubyn.ai/api/v1/skills/packs.json` is reachable).
  2. Picks the first pack the user does **not** have installed, so we never touch their existing packs.
  3. Installs the pack via `RegistryClient#fetch_pack` + `PackManager#install` — exactly the path the autoload pipeline uses.
  4. Reads the disk back through a fresh `Skills::Catalog` and confirms the new skills are visible with parsed triggers.
  5. Runs `Skills::Matcher#match` against a real trigger from one of the freshly-installed skills, confirming the matcher would have fired in a real session.
  6. Removes the pack in an `ensure` block so a partial failure still leaves the user's system clean.

  PASS criteria: `STEP install`, `STEP catalog`, `STEP matcher`, and `STEP cleanup` all `PASS`, with a final `ROUNDTRIP: PASS`.

- **Live autoload notification (manual verification, not scored)**: This isn't a tool call — it's a hint to surface in the scorecard for the user. Tell them: after the self-test completes, send a follow-up prompt that includes a trigger word from any pack in the registry (e.g. `"explain turbo drive"`). The Rubyn renderer should print:
  ```
  📥 Fetching skill pack 'hotwire' from registry…
  📚 Loaded: turbo-drive
  ```
  before the next response (the `📥` line appears only if the pack wasn't already installed). Do **not** count this as PASS/FAIL — just mention it in the scorecard so the user can verify the renderer side themselves.

### 10. Teams System — Multi-Agent

Run the following inline Ruby script with `bash`. It exercises the teammate manager, mailbox (including structured messaging), and agent registry in a single SQLite-backed round-trip. PASS if the final line is `ALL PASS`.

  ```bash
  bundle exec ruby -e '
    require_relative "lib/rubyn_code"
    require "sqlite3"

    db = SQLite3::Database.new(":memory:")
    db.results_as_hash = true

    mailbox = RubynCode::Teams::Mailbox.new(db)
    manager = RubynCode::Teams::Manager.new(db, mailbox: mailbox)
    registry = RubynCode::Teams::AgentRegistry.new(manager: manager, mailbox: mailbox)

    # 1. Spawn root + child teammates
    root = manager.spawn(name: "lead", role: "coordinator")
    child = manager.spawn(name: "coder", role: "developer", parent_agent_id: root.id)
    raise "spawn failed" unless root.root? && !child.root?
    puts "STEP spawn: PASS"

    # 2. Parent-child tracking
    kids = manager.children_of(root.id)
    raise "children_of broken" unless kids.size == 1 && kids.first.name == "coder"
    raise "roots broken" unless manager.roots.size == 1
    tree = manager.agent_tree(root.id)
    raise "tree broken" unless tree[:children].size == 1
    puts "STEP lineage: PASS"

    # 3. Structured messaging with correlation_id
    corr_id = mailbox.send_structured(
      from: "lead", to: "coder", type: "task",
      data: { action: "write_tests", files: ["user.rb"] },
      content: "Write tests for user.rb"
    )
    raise "send_structured returned nil" if corr_id.nil?

    msgs = mailbox.read_inbox("coder")
    raise "inbox empty" if msgs.empty?
    msg = msgs.first
    raise "missing data" unless msg[:data].is_a?(Hash) && msg[:data][:action] == "write_tests"
    raise "missing correlation_id" unless msg[:correlation_id].is_a?(String)
    puts "STEP structured_msg: PASS"

    # 4. Correlation chain
    mailbox.send(
      from: "coder", to: "lead", content: "Done",
      message_type: "result", correlation_id: msg[:correlation_id],
      data: { status: "ok", tests: 5 }
    )
    chain = mailbox.find_by_correlation_id(msg[:correlation_id])
    raise "correlation chain broken (#{chain.size})" unless chain.size == 2
    puts "STEP correlation: PASS"

    # 5. Agent discovery
    manager.update_status("coder", "active")
    snap = registry.snapshot
    raise "snapshot broken" unless snap.size == 2
    actives = registry.active
    raise "active filter broken" unless actives.size == 1 && actives.first[:name] == "coder"
    forest = registry.forest
    raise "forest broken" unless forest.size == 1 && forest.first[:children].size == 1
    lineage = registry.lineage(child.id)
    raise "lineage broken" unless lineage.size == 1 && lineage.first.name == "lead"
    report = registry.status_report
    raise "status_report broken" unless report.include?("lead") && report.include?("coder")
    puts "STEP discovery: PASS"

    # 6. Cleanup + unread_count
    raise "unread wrong" unless mailbox.unread_count("lead") == 1
    mailbox.read_inbox("lead")
    raise "read didnt clear" unless mailbox.unread_count("lead") == 0
    manager.remove("coder")
    manager.remove("lead")
    raise "cleanup failed" unless manager.list.empty?
    puts "STEP cleanup: PASS"

    puts "ALL PASS"
  '
  ```

  The script tests:
  1. **Spawn** — root and child teammates with parent tracking
  2. **Lineage** — `children_of`, `roots`, `agent_tree`
  3. **Structured messaging** — `send_structured` with typed data payloads
  4. **Correlation chains** — request/response pairing via `correlation_id`
  5. **Agent discovery** — `snapshot`, `active`, `forest`, `lineage`, `status_report`
  6. **Cleanup** — `unread_count`, `read_inbox`, `remove`

  PASS criteria: all 6 `STEP` lines say PASS and the final line is `ALL PASS`.

## Scoring

Count total PASS results out of total tests run. Report the percentage.

- **90-100%**: Rubyn is healthy. All major systems operational.
- **75-89%**: Rubyn is mostly working. Check the failures — they may be config/environment issues.
- **50-74%**: Something is wrong. Multiple subsystems are broken.
- **Below 50%**: Rubyn needs repair. Check installation, dependencies, and database.

## Important

- Do NOT skip tests. Run all of them.
- Do NOT stop on failures. Record and continue.
- Clean up any temp files you create.
- The self-test should take less than 60 seconds.
- Report the scorecard in a clear, formatted table at the end.
