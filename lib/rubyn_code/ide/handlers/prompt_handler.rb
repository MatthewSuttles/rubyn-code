# frozen_string_literal: true

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
          @sessions = {} # sessionId => Thread
        end

        def call(params)
          text       = params["text"] || ""
          context    = params["context"] || {}
          session_id = params["sessionId"] || SecureRandom.uuid

          # Cancel any existing agent thread for this session
          cancel_session(session_id)

          # Spawn the agent loop in a background thread
          @sessions[session_id] = Thread.new do
            run_agent(session_id, text, context)
          end

          { "accepted" => true, "sessionId" => session_id }
        end

        # Called by CancelHandler to stop a running session.
        def cancel_session(session_id)
          thread = @sessions.delete(session_id)
          return unless thread&.alive?

          thread.raise(Interrupt)
          thread.join(2) # give it a moment to clean up
        end

        private

        def run_agent(session_id, text, context)
          @server.notify("agent/status", {
            "sessionId" => session_id,
            "status"    => "thinking"
          })

          workspace = context["workspacePath"] || @server.workspace_path || Dir.pwd
          agent_loop = build_agent_loop(session_id, workspace)

          enriched_input = build_enriched_input(text, context)

          @server.notify("agent/status", {
            "sessionId" => session_id,
            "status"    => "streaming"
          })

          response = agent_loop.send_message(enriched_input)

          @server.notify("agent/status", {
            "sessionId" => session_id,
            "status"    => "done"
          })

          @server.notify("stream/text", {
            "sessionId" => session_id,
            "text"      => response,
            "final"     => true
          })
        rescue Interrupt
          @server.notify("agent/status", {
            "sessionId" => session_id,
            "status"    => "cancelled"
          })
        rescue StandardError => e
          $stderr.puts "[PromptHandler] error: #{e.message}"
          $stderr.puts e.backtrace&.first(5)&.join("\n")
          @server.notify("agent/status", {
            "sessionId" => session_id,
            "status"    => "error",
            "error"     => e.message
          })
        ensure
          @sessions.delete(session_id)
        end

        def build_agent_loop(session_id, workspace)
          llm_client      = LLM::Client.new
          conversation    = Agent::Conversation.new
          tool_executor   = Tools::Executor.new(project_root: workspace)
          context_manager = Context::Manager.new(llm_client: llm_client)
          hook_registry   = Hooks::Registry.new
          hook_runner     = Hooks::Runner.new(registry: hook_registry)
          stall_detector  = Agent::LoopDetector.new

          Hooks::BuiltIn.register_all!(hook_registry)

          tool_executor.llm_client = llm_client

          Agent::Loop.new(
            llm_client:      llm_client,
            tool_executor:   tool_executor,
            context_manager: context_manager,
            hook_runner:     hook_runner,
            conversation:    conversation,
            permission_tier: :allow_read,
            deny_list:       Permissions::DenyList.new,
            stall_detector:  stall_detector,
            on_tool_call:    build_tool_call_callback(session_id),
            on_tool_result:  build_tool_result_callback(session_id),
            on_text:         build_text_callback(session_id),
            project_root:    workspace
          )
        end

        def build_tool_call_callback(session_id)
          lambda { |name, params|
            @server.notify("agent/status", {
              "sessionId" => session_id,
              "status"    => "tool_use"
            })
            @server.notify("tool/use", {
              "sessionId" => session_id,
              "tool"      => name,
              "params"    => params
            })
          }
        end

        def build_tool_result_callback(session_id)
          lambda { |name, result, _is_error = false|
            @server.notify("tool/result", {
              "sessionId" => session_id,
              "tool"      => name,
              "result"    => result.to_s[0, 4096]
            })
            @server.notify("agent/status", {
              "sessionId" => session_id,
              "status"    => "thinking"
            })
          }
        end

        def build_text_callback(session_id)
          lambda { |text|
            @server.notify("agent/status", {
              "sessionId" => session_id,
              "status"    => "streaming"
            })
            @server.notify("stream/text", {
              "sessionId" => session_id,
              "text"      => text,
              "final"     => false
            })
          }
        end

        def build_enriched_input(text, context)
          parts = []

          if context["activeFile"]
            parts << "[Active file: #{context['activeFile']}]"
          end

          if context["selection"]
            sel = context["selection"]
            range = "lines #{sel['startLine']}-#{sel['endLine']}"
            parts << "[Selection (#{range}):\n#{sel['text']}\n]"
          end

          if context["openFiles"]&.any?
            parts << "[Open files: #{context['openFiles'].join(', ')}]"
          end

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
