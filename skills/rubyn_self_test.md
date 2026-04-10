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

### 13. Architecture Integrity
- **grep**: Search for `autoload` in `lib/rubyn_code.rb`. PASS if at least 40 autoload entries found.
- **glob**: Check that all 16 layer directories exist under `lib/rubyn_code/`. PASS if at least 14 found.
- **read_file**: Read `lib/rubyn_code.rb` and verify it has modules for Agent, Tools, Context, Skills, Memory, Observability, Learning. PASS if all 7 found.

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
