# frozen_string_literal: true

module RubynCode
  module Agent
    class Loop
      MAX_ITERATIONS = Config::Defaults::MAX_ITERATIONS

      # @param llm_client [LLM::Client]
      # @param tool_executor [Tools::Executor]
      # @param context_manager [Context::Manager]
      # @param hook_runner [Hooks::Runner]
      # @param conversation [Agent::Conversation]
      # @param permission_tier [Symbol] one of Permissions::Tier::ALL
      # @param deny_list [Permissions::DenyList]
      # @param budget_enforcer [Observability::BudgetEnforcer, nil]
      # @param background_manager [Background::Worker, nil]
      # @param stall_detector [Agent::LoopDetector]
      def initialize(
        llm_client:,
        tool_executor:,
        context_manager:,
        hook_runner:,
        conversation:,
        permission_tier: Permissions::Tier::ALLOW_READ,
        deny_list: Permissions::DenyList.new,
        budget_enforcer: nil,
        background_manager: nil,
        stall_detector: LoopDetector.new,
        on_tool_call: nil,
        on_tool_result: nil,
        on_text: nil,
        skill_loader: nil,
        project_root: nil
      )
        @llm_client         = llm_client
        @tool_executor      = tool_executor
        @context_manager    = context_manager
        @hook_runner        = hook_runner
        @conversation       = conversation
        @permission_tier    = permission_tier
        @deny_list          = deny_list
        @budget_enforcer    = budget_enforcer
        @background_manager = background_manager
        @stall_detector     = stall_detector
        @on_tool_call       = on_tool_call
        @on_tool_result     = on_tool_result
        @on_text            = on_text
        @skill_loader       = skill_loader
        @project_root       = project_root
        @plan_mode          = false
      end

      # @return [Boolean]
      attr_accessor :plan_mode

      # Send a user message and run the agent loop until a final text response
      # is produced or the iteration limit is reached.
      #
      # @param user_input [String]
      # @return [String] the final assistant text response
      def send_message(user_input)
        check_user_feedback(user_input)

        # Drain any completed background jobs BEFORE adding the user message,
        # so the LLM sees the results in the right order
        drain_background_notifications

        @conversation.add_user_message(user_input)
        @max_tokens_override = nil
        @output_recovery_count = 0
        @task_budget_remaining = nil

        MAX_ITERATIONS.times do |iteration|
          RubynCode::Debug.loop_tick("iteration=#{iteration} messages=#{@conversation.length} max_tokens_override=#{@max_tokens_override || 'default'}")

          response = call_llm
          tool_calls = extract_tool_calls(response)
          stop_reason = response.respond_to?(:stop_reason) ? response.stop_reason : nil

          RubynCode::Debug.llm("stop_reason=#{stop_reason} tool_calls=#{tool_calls.size} content_blocks=#{get_content(response).size}")

          if tool_calls.empty?
            if truncated?(response)
              RubynCode::Debug.recovery("Text response truncated, entering recovery")
              response = recover_truncated_response(response)
            end

            # Before returning, check if background jobs finished while we were thinking
            drain_background_notifications
            if has_pending_background_jobs?
              @conversation.add_assistant_message(response_content(response))
              @conversation.add_user_message(
                "[system] Background jobs are still running. You may continue or wait for results."
              )
              next
            end

            @conversation.add_assistant_message(response_content(response))
            return extract_response_text(response)
          end

          # Tier 1: If a tool-use response was truncated, silently escalate and retry
          if truncated?(response)
            unless @max_tokens_override
              RubynCode::Debug.recovery("Tier 1: Escalating max_tokens from #{Config::Defaults::CAPPED_MAX_OUTPUT_TOKENS} to #{Config::Defaults::ESCALATED_MAX_OUTPUT_TOKENS}")
              @max_tokens_override = Config::Defaults::ESCALATED_MAX_OUTPUT_TOKENS
              next
            end
          end

          @conversation.add_assistant_message(get_content(response))
          process_tool_calls(tool_calls)

          # Drain notifications after tool execution — jobs may have finished
          drain_background_notifications

          run_maintenance(iteration)
        end

        RubynCode::Debug.warn("Hit MAX_ITERATIONS (#{MAX_ITERATIONS})")
        max_iterations_warning
      end

      private

      # ── LLM interaction ──────────────────────────────────────────────

      TASK_BUDGET_TOTAL = 100_000 # tokens per user message

      def call_llm
        @hook_runner.fire(:pre_llm_call, conversation: @conversation)

        opts = {
          messages: @conversation.to_api_format,
          tools: @plan_mode ? read_only_tool_definitions : tool_definitions,
          system: build_system_prompt,
          on_text: @on_text
        }
        opts[:max_tokens] = @max_tokens_override if @max_tokens_override

        # Task budget: tell the model how many tokens remain for this task
        if @task_budget_remaining
          opts[:task_budget] = { total: TASK_BUDGET_TOTAL, remaining: @task_budget_remaining }
        end

        response = @llm_client.chat(**opts)

        @hook_runner.fire(:post_llm_call, response: response, conversation: @conversation)
        track_usage(response)
        update_task_budget(response)

        response
      rescue LLM::Client::PromptTooLongError
        # 413: context too large — compact and retry once
        RubynCode::Debug.recovery("413 prompt too long — running emergency compaction")
        @context_manager.check_compaction!(@conversation)

        response = @llm_client.chat(**opts.merge(messages: @conversation.to_api_format))
        @hook_runner.fire(:post_llm_call, response: response, conversation: @conversation)
        track_usage(response)

        response
      end

      SYSTEM_PROMPT = <<~PROMPT.freeze
        You are Rubyn — a snarky but lovable AI coding assistant who lives and breathes Ruby.
        You're the kind of pair programmer who'll roast your colleague's `if/elsif/elsif/else` chain
        with a smirk, then immediately rewrite it as a beautiful `case/in` with pattern matching.
        You're sharp, opinionated, and genuinely helpful. Think of yourself as the senior Ruby dev
        who's seen every Rails antipattern in production and somehow still loves this language.

        ## Personality
        - Snarky but never mean. You tease the code, not the coder.
        - You celebrate good Ruby — "Oh, a proper guard clause? You love to see it."
        - You mourn bad Ruby — "A `for` loop? In MY Ruby? It's more likely than you think."
        - Brief and punchy. No walls of text unless teaching something important.
        - You use Ruby metaphors: "Let's refactor this like Matz intended."
        - When something is genuinely good code, you say so. No notes.

        ## Ruby Convictions (non-negotiable)
        - `frozen_string_literal: true` in every file. Every. Single. One.
        - Prefer `each`, `map`, `select`, `reduce` over manual iteration. Always.
        - Guard clauses over nested conditionals. Return early, return often.
        - `Data.define` for value objects (Ruby 3.2+). `Struct` only if you need mutability.
        - `snake_case` methods, `CamelCase` classes, `SCREAMING_SNAKE` constants. No exceptions.
        - Single quotes unless you're interpolating. Fight me.
        - Methods under 15 lines. Classes under 100. Extract or explain why not.
        - Explicit over clever. Metaprogramming is a spice, not the main course.
        - `raise` over `fail`. Rescue specific exceptions, never bare `rescue`.
        - Prefer composition over inheritance. Mixins are not inheritance.
        - `&&` / `||` over `and` / `or`. The precedence difference has burned too many.
        - `dig` for nested hashes. `fetch` with defaults over `[]` with `||`.
        - `freeze` your constants. Frozen arrays, frozen hashes, frozen regexps.
        - No `OpenStruct`. Ever. It's slow, it's a footgun, and `Data.define` exists.

        ## Rails Convictions
        - Skinny controllers, fat models is dead. Skinny controllers, skinny models, service objects.
        - `has_many :through` over `has_and_belongs_to_many`. Every time.
        - Add database indexes for every foreign key and every column you query.
        - Migrations are generated, not handwritten. `rails generate migration`.
        - Strong parameters in controllers. No `permit!`. Ever.
        - Use `find_each` for batch processing. `each` on a large scope is a memory bomb.
        - `exists?` over `present?` for checking DB existence. One is a COUNT, the other loads the record.
        - Scopes over class methods for chainable queries.
        - Background jobs for anything that takes more than 100ms.
        - Don't put business logic in callbacks. That way lies madness.

        ## Testing Convictions
        - RSpec > Minitest (but you'll work with either without complaining... much)
        - FactoryBot over fixtures. Factories are explicit. Fixtures are magic.
        - One assertion per test when practical. "It does three things" is three tests.
        - `let` over instance variables. `let!` only when you need eager evaluation.
        - `described_class` over repeating the class name.
        - Test behavior, not implementation. Mock the boundary, not the internals.

        ## How You Work
        - For greetings and casual chat, just respond naturally. No need to run tools.
        - Only use tools when the user asks you to DO something (read, write, search, run, review).
        - Read before you write. Always understand existing code before suggesting changes.
        - Use tools to verify. Don't guess if a file exists — check.
        - Show diffs when editing. The human should see what changed.
        - Run specs after changes. If they break, fix them.
        - When you are asked to work in a NEW directory you haven't seen yet, check for RUBYN.md, CLAUDE.md, or AGENT.md there. But don't do this unprompted on startup — those files are already loaded into your context.
        - Load skills when you need deep knowledge on a topic. Don't wing it.
        - You have 112 curated best-practice skill documents covering Ruby, Rails, RSpec, design patterns, and code quality. When writing new code or reviewing existing code, load the relevant skill BEFORE implementing. Don't reinvent patterns that are already documented.
        - HOWEVER: always respect patterns already established in the codebase. If the project uses a specific convention (e.g. service objects, a particular test style, a custom base class), follow that convention even if it differs from the skill doc. Consistency with the codebase beats textbook best practice. Only break from established patterns if they are genuinely harmful (security issues, major performance problems, or bugs).
        - Keep responses concise. Code speaks louder than paragraphs.
        - Use spawn_agent sparingly — only for tasks that require reading many files (10+) or deep exploration. For simple reads or edits, use tools directly. Don't spawn a sub-agent when a single read_file or grep will do.
        - IMPORTANT: You can call MULTIPLE tools in a single response. When you need to read several files, search multiple patterns, or perform independent operations, return all tool_use blocks at once rather than one at a time. This is dramatically faster and cheaper. For example, if you need to read 5 files, emit 5 read_file tool calls in one response — don't read them one by one across 5 turns.

        ## Memory
        You have persistent memory across sessions via `memory_write` and `memory_search` tools.
        Use them proactively:
        - When the user tells you a preference or convention, save it: memory_write(content: "User prefers Grape over Rails controllers for APIs", category: "user_preference")
        - When you discover a project pattern (e.g. "this app uses service objects in app/services/"), save it: memory_write(content: "...", category: "project_convention")
        - When you fix a tricky bug, save the resolution: memory_write(content: "...", category: "error_resolution")
        - When you learn a key architectural decision, save it: memory_write(content: "...", category: "decision")
        - Before starting work on a project, search memory for context: memory_search(query: "project conventions")
        - Don't save trivial things. Save what would be useful in a future session.
        Categories: user_preference, project_convention, error_resolution, decision, code_pattern
      PROMPT

      PLAN_MODE_PROMPT = <<~PLAN.freeze
        ## 🧠 Plan Mode Active

        You are in PLAN MODE. This means:
        - Reason through the problem step by step
        - You have READ-ONLY tools available — use them to explore the codebase
        - Read files, grep, glob, check git status/log/diff — gather context
        - Do NOT write, edit, execute, or modify anything
        - Outline your plan with numbered steps
        - Identify files you'd need to read or modify
        - Call out risks, edge cases, and trade-offs
        - Ask clarifying questions if the request is ambiguous
        - When the user is satisfied with the plan, they'll toggle plan mode off with /plan

        You CAN use read-only tools. You MUST NOT use any tool that writes, edits, or executes.
      PLAN

      PLAN_MODE_RISK_LEVELS = %i[read].freeze

      def build_system_prompt
        parts = [SYSTEM_PROMPT]

        parts << PLAN_MODE_PROMPT if @plan_mode
        parts << "Working directory: #{@project_root}" if @project_root

        # Inject memories from previous sessions
        memories = load_memories
        parts << "\n## Your Memories (from previous sessions)\n#{memories}" unless memories.empty?

        # Load RUBYN.md / CLAUDE.md / AGENT.md files
        rubyn_instructions = load_rubyn_md
        parts << "\n## Project Instructions\n#{rubyn_instructions}" unless rubyn_instructions.empty?

        # Inject learned instincts from previous sessions
        instincts = load_instincts
        parts << "\n## Learned Instincts (from previous sessions)\n#{instincts}" unless instincts.empty?

        # Load custom skills
        if @skill_loader
          descriptions = @skill_loader.descriptions_for_prompt
          unless descriptions.empty?
            parts << "\n## Available Skills (use load_skill tool to load full content)"
            parts << descriptions
          end
        end

        # List deferred tools so the LLM knows they exist
        deferred = deferred_tool_names
        unless deferred.empty?
          parts << "\n## Additional Tools Available"
          parts << "These tools are available but not loaded yet. Just call them by name and they will work:"
          parts << deferred.map { |n| "- #{n}" }.join("\n")
        end

        parts.join("\n")
      end

      def deferred_tool_names
        all_names = @tool_executor.tool_definitions.map { |t| t[:name] || t["name"] }
        active_names = tool_definitions.map { |t| t[:name] || t["name"] }
        all_names - active_names
      end

      def load_memories
        return "" unless @project_root

        db = DB::Connection.instance
        search = Memory::Search.new(db, project_path: @project_root)
        recent = search.recent(limit: 20)

        return "" if recent.empty?

        recent.map { |m|
          category = m.respond_to?(:category) ? m.category : (m[:category] || m["category"])
          content = m.respond_to?(:content) ? m.content : (m[:content] || m["content"])
          "[#{category}] #{content}"
        }.join("\n")
      rescue StandardError
        ""
      end

      def load_instincts
        return "" unless @project_root

        db = DB::Connection.instance
        Learning::Injector.call(db: db, project_path: @project_root)
      rescue StandardError
        ""
      end

      # ── Instinct reinforcement ───────────────────────────────────

      POSITIVE_PATTERNS = /\b(yes that fixed it|that worked|perfect|thanks|exactly|great|nailed it|that.s right|correct)\b/i.freeze
      NEGATIVE_PATTERNS = /\b(no[, ]+use|wrong|that.s not right|instead use|don.t do that|actually[, ]+use|incorrect)\b/i.freeze

      def check_user_feedback(user_input)
        return unless @project_root

        db = DB::Connection.instance
        recent_instincts = db.query(
          "SELECT id FROM instincts WHERE project_path = ? ORDER BY updated_at DESC LIMIT 5",
          [@project_root]
        ).to_a

        return if recent_instincts.empty?

        if user_input.match?(POSITIVE_PATTERNS)
          recent_instincts.first(2).each do |row|
            Learning::InstinctMethods.reinforce_in_db(row["id"], db, helpful: true)
          end
        elsif user_input.match?(NEGATIVE_PATTERNS)
          recent_instincts.first(2).each do |row|
            Learning::InstinctMethods.reinforce_in_db(row["id"], db, helpful: false)
          end
        end
      rescue StandardError
        # Non-critical; don't interrupt the conversation
      end

      # Load instruction files from multiple locations.
      # Detects RUBYN.md, CLAUDE.md, and AGENT.md — so projects that already
      # have CLAUDE.md or AGENT.md work out of the box with Rubyn Code.
      INSTRUCTION_FILES = %w[RUBYN.md CLAUDE.md AGENT.md].freeze

      def load_rubyn_md
        found = []

        if @project_root
          # Walk UP from project root to find parent instruction files
          walk_up_for_instructions(@project_root, found)

          # Project root
          INSTRUCTION_FILES.each do |name|
            collect_instruction(File.join(@project_root, name), found)
          end
          collect_instruction(File.join(@project_root, ".rubyn-code", "RUBYN.md"), found)

          # One level of child directories
          INSTRUCTION_FILES.each do |name|
            Dir.glob(File.join(@project_root, "*", name)).each do |path|
              collect_instruction(path, found)
            end
          end
        end

        # User global
        collect_instruction(File.join(Config::Defaults::HOME_DIR, "RUBYN.md"), found)

        found.uniq.join("\n\n")
      end

      def walk_up_for_instructions(start_dir, found)
        dir = File.dirname(start_dir)
        home = File.expand_path("~")

        while dir.length >= home.length
          INSTRUCTION_FILES.each do |name|
            collect_instruction(File.join(dir, name), found)
          end
          break if dir == home
          dir = File.dirname(dir)
        end
      end

      def collect_instruction(path, found)
        return unless File.exist?(path) && File.file?(path)

        content = File.read(path, encoding: "utf-8")
                      .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                      .strip
        return if content.empty?

        found << "# From #{path}\n#{content}"
      end

      # Core tools always included. Others load on first use.
      CORE_TOOLS = %w[
        read_file write_file edit_file glob grep bash
        spawn_agent background_run
      ].freeze

      def tool_definitions
        all_tools = @tool_executor.tool_definitions
        return all_tools if all_tools.size <= CORE_TOOLS.size

        @discovered_tools ||= Set.new

        all_tools.select { |t|
          name = t[:name] || t["name"]
          CORE_TOOLS.include?(name) || @discovered_tools.include?(name)
        }
      end

      def discover_tool(name)
        @discovered_tools ||= Set.new
        @discovered_tools.add(name)
      end

      def read_only_tool_definitions
        Tools::Registry.all
                        .select { |t| PLAN_MODE_RISK_LEVELS.include?(t::RISK_LEVEL) }
                        .map(&:to_schema)
      end

      # ── Tool processing ──────────────────────────────────────────────

      def process_tool_calls(tool_calls)
        aggregate_chars = 0
        budget = Config::Defaults::MAX_MESSAGE_TOOL_RESULTS_CHARS

        tool_calls.each do |tool_call|
          tool_name  = field(tool_call, :name)
          tool_input = field(tool_call, :input) || {}
          tool_id    = field(tool_call, :id)

          decision = Permissions::Policy.check(
            tool_name: tool_name,
            tool_input: tool_input,
            tier: @permission_tier,
            deny_list: @deny_list
          )

          @on_tool_call&.call(tool_name, tool_input) rescue nil

          result, is_error = execute_with_permission(decision, tool_name, tool_input, tool_id)

          # Enforce per-message aggregate tool result budget
          aggregate_chars += result.to_s.length
          if aggregate_chars > budget
            remaining = [budget - (aggregate_chars - result.to_s.length), 500].max
            result = "#{result.to_s[0, remaining]}\n\n[truncated — tool result budget exceeded (#{budget} chars/message)]"
            RubynCode::Debug.token("Tool result budget exceeded: #{aggregate_chars}/#{budget} chars")
          end

          @on_tool_result&.call(tool_name, result, is_error) rescue nil

          @stall_detector.record(tool_name, tool_input)
          # CRITICAL: always add tool_result to conversation — without this the
          # API will reject the next request with "tool_use without tool_result"
          @conversation.add_tool_result(tool_id, tool_name, result, is_error: is_error)
        end
      end

      def execute_with_permission(decision, tool_name, tool_input, tool_id)
        case decision
        when :deny
          ["Tool '#{tool_name}' is blocked by the deny list.", true]
        when :ask
          if prompt_user(tool_name, tool_input)
            execute_tool(tool_name, tool_input)
          else
            ["User denied permission for '#{tool_name}'.", true]
          end
        when :allow
          execute_tool(tool_name, tool_input)
        else
          ["Unknown permission decision: #{decision}", true]
        end
      end

      def execute_tool(tool_name, tool_input)
        # Auto-discover tools on first use so they appear in future calls
        discover_tool(tool_name)

        @hook_runner.fire(:pre_tool_use, tool_name: tool_name, tool_input: tool_input)

        result = @tool_executor.execute(tool_name, symbolize_keys(tool_input))
        @hook_runner.fire(:post_tool_use, tool_name: tool_name, tool_input: tool_input, result: result)

        [result.to_s, false]
      rescue StandardError => e
        ["Error executing #{tool_name}: #{e.message}", true]
      end

      def prompt_user(tool_name, tool_input)
        risk = resolve_tool_risk(tool_name)

        if risk == :destructive
          Permissions::Prompter.confirm_destructive(tool_name, tool_input)
        else
          Permissions::Prompter.confirm(tool_name, tool_input)
        end
      end

      def resolve_tool_risk(tool_name)
        tool_class = Tools::Registry.get(tool_name)
        tool_class.risk_level
      rescue ToolNotFoundError
        :unknown
      end

      # ── Maintenance ──────────────────────────────────────────────────

      def run_maintenance(iteration)
        run_compaction
        check_budget
        check_stall_detection
      end

      def run_compaction
        before = @conversation.length
        est = @context_manager.estimated_tokens(@conversation.messages)
        RubynCode::Debug.token("context=#{est} tokens (~#{before} messages, threshold=#{Config::Defaults::CONTEXT_THRESHOLD_TOKENS})")

        @context_manager.check_compaction!(@conversation)

        after = @conversation.length
        if after < before
          new_est = @context_manager.estimated_tokens(@conversation.messages)
          RubynCode::Debug.loop_tick("Compacted: #{before} -> #{after} messages (#{est} -> #{new_est} tokens)")
        end
      rescue NoMethodError
        # context_manager does not implement check_compaction! yet
      end

      def check_budget
        return unless @budget_enforcer

        @budget_enforcer.check!
      rescue BudgetExceededError
        raise
      rescue NoMethodError
        # budget_enforcer does not implement check! yet
      end

      def check_stall_detection
        return unless @stall_detector.stalled?

        nudge = @stall_detector.nudge_message
        @conversation.add_user_message(nudge)
        @stall_detector.reset!
      end

      def drain_background_notifications
        return unless @background_manager

        notifications = @background_manager.drain_notifications
        return if notifications.nil? || notifications.empty?

        summary = notifications.map { |n| format_background_notification(n) }.join("\n\n")
        @conversation.add_user_message("[Background job results]\n#{summary}")
      rescue NoMethodError
        # background_manager does not support drain_notifications yet
      end

      def has_pending_background_jobs?
        return false unless @background_manager

        @background_manager.active_count > 0
      rescue NoMethodError
        false
      end

      def format_background_notification(notification)
        case notification
        when Hash
          status = notification[:status] || 'unknown'
          job_id = notification[:job_id]&.[](0..7) || 'unknown'
          duration = notification[:duration] ? "#{'%.1f' % notification[:duration]}s" : 'unknown'
          result = notification[:result] || '(no output)'
          "Job #{job_id} [#{status}] (#{duration}):\n#{result}"
        else
          notification.to_s
        end
      end

      # ── Output token recovery (3-tier, matches Claude Code) ──────────
      #
      # Tier 1: Silent escalation (8K → 32K) — handled in send_message
      # Tier 2: Multi-turn recovery — inject continuation message, retry up to 3x
      # Tier 3: Surface what we have — return partial response after exhausting retries

      def truncated?(response)
        reason = if response.respond_to?(:stop_reason)
                   response.stop_reason
                 elsif response.is_a?(Hash)
                   response[:stop_reason] || response["stop_reason"]
                 end
        reason == "max_tokens"
      end

      def recover_truncated_response(response)
        @max_tokens_override ||= Config::Defaults::ESCALATED_MAX_OUTPUT_TOKENS

        @conversation.add_assistant_message(response_content(response))

        max_retries = Config::Defaults::MAX_OUTPUT_TOKENS_RECOVERY_LIMIT

        max_retries.times do |attempt|
          @output_recovery_count += 1
          RubynCode::Debug.recovery("Tier 2: Recovery attempt #{attempt + 1}/#{max_retries}")

          @conversation.add_user_message(
            "Output token limit hit. Resume directly — no apology, no recap, " \
            "just continue exactly where you left off."
          )

          response = call_llm

          unless truncated?(response)
            RubynCode::Debug.recovery("Recovery successful on attempt #{attempt + 1}")
            break
          end

          RubynCode::Debug.recovery("Still truncated after attempt #{attempt + 1}")
          @conversation.add_assistant_message(response_content(response))
        end

        if truncated?(response)
          RubynCode::Debug.recovery("Tier 3: Exhausted #{max_retries} recovery attempts, returning partial response")
        end

        response
      end

      # ── Response helpers ─────────────────────────────────────────────

      def extract_tool_calls(response)
        get_content(response).select { |block| block_type(block) == "tool_use" }
      end

      def response_content(response)
        get_content(response)
      end

      def extract_response_text(response)
        blocks = get_content(response)
        blocks.select { |b| block_type(b) == "text" }
              .map { |b| b.respond_to?(:text) ? b.text : (b[:text] || b["text"]) }
              .compact.join("\n")
      end

      def get_content(response)
        case response
        when ->(r) { r.respond_to?(:content) }
          Array(response.content)
        when Hash
          Array(response[:content] || response["content"])
        else
          []
        end
      end

      def block_type(block)
        if block.respond_to?(:type)
          block.type.to_s
        elsif block.is_a?(Hash)
          (block[:type] || block["type"]).to_s
        end
      end

      def track_usage(response)
        usage = if response.respond_to?(:usage)
                  response.usage
                elsif response.is_a?(Hash)
                  response[:usage] || response["usage"]
                end
        return unless usage

        input_tokens = usage.respond_to?(:input_tokens) ? usage.input_tokens : usage[:input_tokens]
        output_tokens = usage.respond_to?(:output_tokens) ? usage.output_tokens : usage[:output_tokens]
        cache_create = usage.respond_to?(:cache_creation_input_tokens) ? usage.cache_creation_input_tokens.to_i : 0
        cache_read = usage.respond_to?(:cache_read_input_tokens) ? usage.cache_read_input_tokens.to_i : 0
        cache_info = cache_create > 0 || cache_read > 0 ? " cache_create=#{cache_create} cache_read=#{cache_read}" : ""
        RubynCode::Debug.token("in=#{input_tokens} out=#{output_tokens}#{cache_info}")

        @context_manager.track_usage(usage)
      rescue NoMethodError
        # context_manager does not implement track_usage yet
      end

      def update_task_budget(response)
        usage = response.respond_to?(:usage) ? response.usage : nil
        return unless usage

        output = usage.respond_to?(:output_tokens) ? usage.output_tokens.to_i : 0
        input = usage.respond_to?(:input_tokens) ? usage.input_tokens.to_i : 0

        # Initialize on first response, then decrement
        @task_budget_remaining ||= TASK_BUDGET_TOTAL
        @task_budget_remaining = [@task_budget_remaining - input - output, 0].max

        RubynCode::Debug.token("task_budget_remaining=#{@task_budget_remaining}/#{TASK_BUDGET_TOTAL}")
      end

      def max_iterations_warning
        warning = "Reached maximum iteration limit (#{MAX_ITERATIONS}). " \
                  "The conversation may be incomplete. Please review the current state " \
                  "and continue if needed."
        @conversation.add_assistant_message([{ type: "text", text: warning }])
        warning
      end

      # Extract a field from a Data object or Hash
      def field(obj, key)
        if obj.respond_to?(key)
          obj.send(key)
        elsif obj.is_a?(Hash)
          obj[key] || obj[key.to_s]
        end
      end

      def symbolize_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym)
      end
    end
  end
end
