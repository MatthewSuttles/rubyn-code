# frozen_string_literal: true

require 'set'

module RubynCode
  module IDE
    module Handlers
      # Handles the "prompt" JSON-RPC request — the main chat entry point.
      #
      # Returns immediately with { "accepted" => true } and spawns a
      # background thread that runs the agent loop. As the agent works,
      # it emits stream/text, tool/use, tool/result, and agent/status
      # notifications over the JSON-RPC transport.
      class PromptHandler
        def initialize(server)
          @server = server
          @sessions = {}       # sessionId => Thread
          @conversations = {}  # sessionId => Agent::Conversation (persists across prompts)
          @started_sessions = Set.new # tracks which sessions have fired session_start
        end

        # Called by SessionResumeHandler to inject a restored conversation
        # into the cache so the next prompt continues from the loaded history.
        def inject_conversation(session_id, conversation)
          cancel_session(session_id)
          @conversations[session_id] = conversation
        end

        # Called by SessionResetHandler when the user clicks "New Session"
        # in the chat UI. Drops the cached conversation for this session so
        # the next prompt starts fresh — parity with the CLI's `/new`.
        def reset_session(session_id)
          cancel_session(session_id)
          @conversations.delete(session_id)
          @started_sessions.delete(session_id)
        end

        def call(params)
          text       = params['text'] || ''
          context    = params['context'] || {}
          session_id = params['sessionId'] || SecureRandom.uuid

          # Cancel any existing agent thread for this session
          cancel_session(session_id)

          # Spawn the agent loop in a background thread
          @sessions[session_id] = Thread.new do
            run_agent(session_id, text, context)
          end

          { 'accepted' => true, 'sessionId' => session_id }
        end

        # Called by CancelHandler to stop a running session.
        def cancel_session(session_id)
          thread = @sessions.delete(session_id)
          return unless thread&.alive?

          thread.raise(Interrupt)
          thread.join(2) # give it a moment to clean up
        end

        private

        # -- orchestrates agent lifecycle with notifications
        def run_agent(session_id, text, context)
          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'thinking'
                         })

          # Fire IDE hooks for prompt lifecycle
          ide_hook_runner = build_ide_hook_runner
          unless @started_sessions.include?(session_id)
            @started_sessions.add(session_id)
            ide_hook_runner.fire(:session_start, session_id: session_id)
          end
          ide_hook_runner.fire(:user_prompt_submit, session_id: session_id, text: text)

          workspace = context['workspacePath'] || @server.workspace_path || Dir.pwd
          agent_loop = build_agent_loop(session_id, workspace)

          enriched_input = build_enriched_input(text, context)

          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'streaming'
                         })

          response = agent_loop.send_message(enriched_input)

          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'done'
                         })

          @server.notify('stream/text', {
                           'sessionId' => session_id,
                           'text' => response,
                           'final' => true
                         })
        rescue Interrupt
          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'cancelled'
                         })
        rescue StandardError => e
          warn "[PromptHandler] error: #{e.message}"
          warn e.backtrace&.first(5)&.join("\n")
          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'error',
                           'error' => e.message
                         })
        ensure
          @sessions.delete(session_id)
        end

        def build_agent_loop(session_id, workspace)
          llm_client      = LLM::Client.new
          # Reuse the conversation across prompts in the same session so the
          # model has multi-turn memory — same model the CLI REPL uses. A
          # fresh Agent::Loop is built per prompt (cheap, bundle of refs),
          # but the conversation (messages array) persists. `session/reset`
          # drops the cached entry; the next prompt starts a fresh one.
          conversation    = @conversations[session_id] ||= Agent::Conversation.new

          # Register IDE-only tools (diagnostics, symbols) when running in IDE mode.
          Tools::Registry.load_ide_tools! if @server.ide_client

          tool_executor   = Tools::Executor.new(project_root: workspace, ide_client: @server.ide_client)
          context_manager = Context::Manager.new(llm_client: llm_client)
          hook_registry   = Hooks::Registry.new
          hook_runner     = Hooks::Runner.new(registry: hook_registry)
          stall_detector  = Agent::LoopDetector.new

          Hooks::BuiltIn.register_all!(hook_registry)

          tool_executor.llm_client = llm_client

          adapter = build_tool_output_adapter
          tool_wrapper = lambda do |name, input, &blk|
            adapter.wrap_execution(name, input, &blk)
          end

          Agent::Loop.new(
            llm_client: llm_client,
            tool_executor: tool_executor,
            context_manager: context_manager,
            hook_runner: hook_runner,
            conversation: conversation,
            # Gating happens in the ToolOutput adapter (per-tool, via JSON-RPC).
            # The policy tier must not intercept — it has no way to prompt the
            # user in IDE mode and would otherwise fall back to the TTY prompter
            # which corrupts the JSON-RPC stream on stdout.
            permission_tier: :unrestricted,
            deny_list: Permissions::DenyList.new,
            stall_detector: stall_detector,
            tool_wrapper: tool_wrapper,
            on_text: build_text_callback(session_id),
            project_root: workspace,
            ide_client: @server.ide_client
          )
        end

        # Install a ToolOutput adapter on the server so AcceptEdit /
        # ApproveToolUse handlers can route responses back to this session.
        def build_tool_output_adapter
          adapter = IDE::Adapters::ToolOutput.new(@server, permission_mode: @server.permission_mode,
                                                           hook_runner: build_ide_hook_runner)
          @server.tool_output_adapter = adapter
          adapter
        end

        def build_text_callback(session_id)
          lambda { |text|
            @server.notify('agent/status', {
                             'sessionId' => session_id,
                             'status' => 'streaming'
                           })
            @server.notify('stream/text', {
                             'sessionId' => session_id,
                             'text' => text,
                             'final' => false
                           })
          }
        end

        def build_ide_hook_runner
          registry = Hooks::Registry.new
          Hooks::BuiltIn.register_all!(registry)
          Hooks::Runner.new(registry: registry)
        end

        # -- assembles context parts from multiple optional fields
        def build_enriched_input(text, context)
          parts = []

          parts << "[Active file: #{context['activeFile']}]" if context['activeFile']

          if context['selection']
            sel = context['selection']
            range = "lines #{sel['startLine']}-#{sel['endLine']}"
            parts << "[Selection (#{range}):\n#{sel['text']}\n]"
          end

          parts << "[Open files: #{context['openFiles'].join(', ')}]" if context['openFiles']&.any?

          if parts.any?
            "#{parts.join("\n")}\n\n#{text}"
          else
            text
          end
        end
      end
    end
  end
end
