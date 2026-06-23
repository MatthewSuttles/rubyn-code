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

#### Output Compressor — All Strategies (direct)

> **Why this is a direct call, not a tool observation.** Earlier versions of this
> test ran `seq 1 5000`, a big `grep`, etc. through the agent's own tools and
> hoped the compressor would visibly truncate the result. That is unreliable:
> whether a given tool invocation is routed through the compressor gate (and at
> what threshold) depends on the execution path, so the agent often received
> already-handled output and scored a false FAIL even though the compressor was
> fine. Instead, drive `OutputCompressor#compress(tool_name, raw_output)`
> **directly** with inputs crafted to exceed each strategy's threshold, and
> assert on the marker in the returned string. This is deterministic and matches
> how the unit specs exercise it.

- **All strategies**: `bash` with the script below. PASS for each strategy whose line says `PASS`. Report the final `COMPRESSION: N/5 strategies active` line in the scorecard.

  ```bash
  bundle exec ruby -e '
    require_relative "lib/rubyn_code"
    c = RubynCode::Tools::OutputCompressor

    results = {}

    # head_tail (bash, 1000-token threshold): >10 lines, well over 4000 chars
    big = (1..5000).map { |i| "line #{i}" }.join("\n")
    results["head_tail"] = c.new.compress("bash", big).include?("lines omitted")

    # spec_summary (run_specs, 500-token threshold): verbose passing output
    # collapses to just the "N examples, 0 failures" summary line
    spec_out = (Array.new(200) { |i| "  passing example #{i} runs and returns ok value" }.join("\n")) +
               "\n\n42 examples, 0 failures\n"
    results["spec_summary"] = (c.new.compress("run_specs", spec_out).strip == "42 examples, 0 failures")

    # top_matches (grep, 1000-token threshold): keeps top N, marks the rest
    grep_out = (1..500).map { |i| "lib/file#{i}.rb:#{i}:  def method_number_#{i}(arg)" }.join("\n")
    results["top_matches"] = c.new.compress("grep", grep_out).include?("matches omitted")

    # tree (glob, 500-token threshold): collapses paths to "dir/ (N files)"
    glob_out = (1..500).map { |i| "lib/rubyn_code/subdir#{i % 25}/some_file_name_#{i}.rb" }.join("\n")
    results["tree"] = c.new.compress("glob", glob_out).include?("files)")

    # relevant_hunks (git_diff, 2000-token threshold): keeps headers, truncates bodies
    hunk = ->(f) { "diff --git a/#{f} b/#{f}\nindex 000..111 100644\n--- a/#{f}\n+++ b/#{f}\n" +
                   (Array.new(100) { |i| "+ added source line number #{i}" }.join("\n")) + "\n" }
    diff_out = (1..10).map { |i| hunk.call("file#{i}.rb") }.join
    results["relevant_hunks"] = c.new.compress("git_diff", diff_out).include?("lines in this file omitted")

    results.each { |k, v| puts "STRATEGY #{k}: #{v ? "PASS" : "FAIL"}" }
    puts "COMPRESSION: #{results.values.count(true)}/5 strategies active"
  '
  ```

  Each strategy is scored independently (5 line items). A healthy build prints `COMPRESSION: 5/5 strategies active`.

### 7. Skills System
- **load_skill**: Load any available skill (e.g., `classes`). PASS if content is returned.

### 8. Memory System

> **Use the real `Memory::Store` / `Memory::Search` API.** Both are constructed
> as `.new(db, project_path:)` — the `project_path:` keyword is **required**, and
> `db` must respond to `execute` / `query` / `transaction` (a raw
> `SQLite3::Database` alone does **not** provide `query`, which `Search` needs).
> The script below wraps an in-memory SQLite DB to satisfy that interface, exactly
> as the specs' `setup_test_db` helper does. Writing the memory creates its own
> table via `Store#ensure_tables`, so no migrations are needed.

- **Round-trip**: `bash` with the script below. PASS if the final line is `MEMORY: PASS`.

  ```bash
  bundle exec ruby -e '
    require_relative "lib/rubyn_code"
    require "sqlite3"

    # Minimal stand-in for RubynCode::DB::Connection (execute/query/transaction).
    class SelfTestDB
      def initialize(raw) = @raw = raw
      def execute(sql, params = []) = @raw.execute(sql, params)
      def query(sql, params = []) = @raw.execute(sql, params)
      def transaction(&b) = @raw.transaction(&b)
    end

    raw = SQLite3::Database.new(":memory:")
    raw.results_as_hash = true
    db = SelfTestDB.new(raw)

    project = "/self-test"
    store  = RubynCode::Memory::Store.new(db, project_path: project)
    search = RubynCode::Memory::Search.new(db, project_path: project)

    token = "selftesttoken-marker-xyz"
    store.write(content: "self-test memory #{token}")

    found     = search.search(token).any? { |r| r.content.include?(token) }
    recent_ok = search.recent(limit: 5).any? { |r| r.content.include?(token) }

    if found && recent_ok
      puts "MEMORY: PASS (write + search + recent all round-trip)"
    elsif found
      puts "MEMORY: PARTIAL (search works, recent did not return it)"
    else
      puts "MEMORY: FAIL (write succeeded but search did not return it)"
    end
  '
  ```

  The script writes a memory with a unique token, then confirms both
  `Search#search` (LIKE query) and `Search#recent` return it.

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

### 16. Teams System — Multi-Agent

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

### 17. Recent Additions — Claude Code / Codex Parity

Each feature below ships as its own PR; a check FAILs cleanly if that PR has
not yet merged into the branch under test. Run the grep/spec checks — they are
fast and need no API calls.

#### 17a. `/goal` — work until a goal is met
- **grep**: `class GoalHook` in `lib/rubyn_code/hooks/goal_hook.rb`. PASS if found.
- **grep**: `:stop` in `lib/rubyn_code/hooks/runner.rb`. PASS if found (stop-hook gating wired).
- **run_specs**: `bundle exec rspec spec/rubyn_code/hooks/goal_hook_spec.rb spec/rubyn_code/cli/commands/goal_spec.rb --format progress`. PASS if `0 failures`.

#### 17b. `/loop` — repeat a prompt/command on an interval
- **grep**: `class LoopRunner` in `lib/rubyn_code/cli/loop_runner.rb`. PASS if found.
- **run_specs**: `bundle exec rspec spec/rubyn_code/cli/loop_runner_spec.rb spec/rubyn_code/cli/commands/loop_spec.rb --format progress`. PASS if `0 failures`.
- **bash** (behavior): `bundle exec ruby -Ilib -rrubyn_code -e 'puts RubynCode::CLI::LoopRunner.parse_interval("5m")'`. PASS if output is `300`.

#### 17c. `AGENTS.md` project instructions
- **grep**: `AGENTS.md` in `lib/rubyn_code/agent/system_prompt_builder.rb`. PASS if found.
- **run_specs**: `bundle exec rspec spec/rubyn_code/agent/system_prompt_builder_spec.rb --format progress`. PASS if `0 failures`.

#### 17d. `@`-file mentions
- **grep**: `class MentionExpander` in `lib/rubyn_code/cli/mention_expander.rb`. PASS if found.
- **run_specs**: `bundle exec rspec spec/rubyn_code/cli/mention_expander_spec.rb --format progress`. PASS if `0 failures`.

#### 17e. User-defined slash commands
- **grep**: `module CustomLoader` in `lib/rubyn_code/cli/commands/custom_loader.rb`. PASS if found.
- **run_specs**: `bundle exec rspec spec/rubyn_code/cli/commands/custom_loader_spec.rb spec/rubyn_code/cli/commands/command_template_spec.rb --format progress`. PASS if `0 failures`.

#### 17f. Custom sub-agents + `/agents`
- **grep**: `class Catalog` in `lib/rubyn_code/sub_agents/catalog.rb`. PASS if found.
- **run_specs**: `bundle exec rspec spec/rubyn_code/sub_agents/catalog_spec.rb spec/rubyn_code/tools/spawn_agent_spec.rb --format progress`. PASS if `0 failures` (spawn_agent must still pass after the refactor).

#### 17g. MCP resources & prompts
- **grep**: `def supports_resources?` in `lib/rubyn_code/mcp/client.rb`. PASS if found.
- **run_specs**: `bundle exec rspec spec/rubyn_code/mcp/client_spec.rb spec/rubyn_code/mcp/tool_bridge_spec.rb --format progress`. PASS if `0 failures`.

#### 17h. `/rewind` — checkpoint & restore
- **grep**: `class Manager` in `lib/rubyn_code/checkpoint/manager.rb`. PASS if found.
- **run_specs**: `bundle exec rspec spec/rubyn_code/checkpoint --format progress`. PASS if `0 failures`.

#### 17i. Learning export/import
- **grep**: `module Porter` in `lib/rubyn_code/learning/porter.rb`. PASS if found.
- **run_specs**: `bundle exec rspec spec/rubyn_code/learning/porter_spec.rb --format progress`. PASS if `0 failures`.
- **bash** (round-trip): the script below exports instincts to a temp file and re-imports them into a fresh in-memory DB. PASS if the final line is `LEARNING ROUNDTRIP: PASS`.

  ```bash
  bundle exec ruby -Ilib -rrubyn_code -rsqlite3 -rtmpdir -e '
    def db_with_instincts
      raw = SQLite3::Database.new(":memory:"); raw.results_as_hash = true
      raw.execute(File.read("db/migrations/010_create_instincts.sql").split(";").first + ";")
      wrap = Object.new
      wrap.define_singleton_method(:execute) { |sql, p = []| raw.execute(sql, p) }
      wrap.define_singleton_method(:query)   { |sql, p = []| raw.execute(sql, p) }
      wrap
    end
    src = db_with_instincts
    src.execute("INSERT INTO instincts (id,project_path,pattern,context_tags,confidence,decay_rate,times_applied,times_helpful,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
                ["x","/p","prefer guard clauses","[]",0.8,0.05,1,1,"2026-01-01T00:00:00Z","2026-01-01T00:00:00Z"])
    Dir.mktmpdir do |d|
      f = File.join(d, "l.json")
      RubynCode::Learning::Porter.export(db: src, path: f)
      dst = db_with_instincts
      res = RubynCode::Learning::Porter.import(db: dst, path: f)
      ok = res[:imported] == 1 && dst.query("SELECT COUNT(*) AS n FROM instincts").first["n"] == 1
      puts(ok ? "LEARNING ROUNDTRIP: PASS" : "LEARNING ROUNDTRIP: FAIL #{res.inspect}")
    end
  '
  ```

#### 17j. Command registry integrity (all new commands load + register)
- **bash**: the script below boots the command registry exactly as the REPL does and asserts the new slash commands are present and unique. PASS if the final line is `COMMANDS: PASS`.

  ```bash
  bundle exec ruby -Ilib -rrubyn_code -e '
    reg = RubynCode::CLI::Commands::Registry.new
    [RubynCode::CLI::Commands::Goal, RubynCode::CLI::Commands::Loop,
     RubynCode::CLI::Commands::Agents, RubynCode::CLI::Commands::Rewind,
     RubynCode::CLI::Commands::Learning].each { |c| reg.register(c) }
    want = %w[/goal /loop /agents /rewind /learning]
    missing = want.reject { |n| reg.known?(n) }
    puts(missing.empty? ? "COMMANDS: PASS" : "COMMANDS: FAIL missing #{missing.inspect}")
  '
  ```

### 18. Chisel — Minimal-Code Enforcement (opt-in)

Chisel is rubyn-code's "write the minimum that works" layer. It is **off by
default** and only changes the agent once a user turns it on (`/chisel full` or
`chisel_mode` in config). These checks prove the engine resolves modes, injects
its ruleset only when enabled, never chisels away the safety floor, and that the
debt scanner, inspection prompts, and all five slash commands are wired up — all
deterministic, no API calls.

The deterministic target is a committed, deliberately over-engineered fixture,
`skills/self_test/fixtures/chisel_sample.rb`. Chisel scans it and must return the
**same three `chisel:` markers every time** (and ignore the two decoys). That is
what makes this check repeatable rather than a one-off tmpdir.

- **grep** (prompt integration): `append_chisel_ruleset` in `lib/rubyn_code/agent/system_prompt_builder.rb`. PASS if found (confirms the ruleset reaches the system prompt).
- **run_specs**: `bundle exec rspec spec/rubyn_code/chisel_spec.rb spec/rubyn_code/chisel spec/rubyn_code/cli/commands/chisel_spec.rb spec/rubyn_code/cli/commands/chisel_review_spec.rb spec/rubyn_code/cli/commands/chisel_audit_spec.rb spec/rubyn_code/cli/commands/chisel_debt_spec.rb spec/rubyn_code/cli/commands/chisel_gain_spec.rb --format progress`. PASS if output contains `0 failures`. (Includes `self_test_fixture_spec.rb`, which guards the fixture's exact scan result.)
- **Smoke run against the fixture**: `bash` runs the committed runner — no inline script to keep in sync:

  ```bash
  bundle exec ruby skills/self_test/chisel_smoke.rb
  ```

  It scores four areas on their own line and exits non-zero on any failure:

  ```
  CHISEL debt: PASS
  CHISEL engine: PASS
  CHISEL inspection: PASS
  CHISEL commands: PASS
  CHISEL: PASS
  ```

  - **debt** — scanning the fixture returns exactly its three planted markers
    (file/line/note), with the string-literal and trailing-comment decoys ignored.
  - **engine** — `off` injects nothing; `lite`/`full`/`ultra` layer the right
    addenda and always keep the safety floor; a garbage mode never crashes or
    leaks through. Driven via `RUBYN_CHISEL_MODE`, independent of this machine's
    `chisel_mode` config.
  - **inspection** — `:diff` and `:repo` prompts assemble a String carrying the
    ladder + safety floor; an unknown scope raises instead of emitting junk.
  - **commands** — all five (`/chisel`, `/chisel-review`, `/chisel-audit`,
    `/chisel-debt`, `/chisel-gain`) register and resolve.

  Score each `CHISEL <area>` line independently (4 line items). PASS criteria:
  all four areas PASS and the final line is `CHISEL: PASS`.

  You can also point Chisel at the fixture by hand to see the consistent result
  directly: `bundle exec ruby -Ilib -rrubyn_code -e 'RubynCode::Chisel::Debt.scan("skills/self_test/fixtures").each { |i| puts "#{i.file}:#{i.line} — #{i.note}" }'`.

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
