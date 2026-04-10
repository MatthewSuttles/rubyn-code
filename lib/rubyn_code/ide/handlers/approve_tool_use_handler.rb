# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "approveToolUse" JSON-RPC request.
      #
      # When the IDE extension requires user approval before a tool runs
      # (e.g. file writes, shell commands), the server parks the tool
      # execution on a ConditionVariable. This handler resolves that
      # pending approval so the agent can proceed.
      class ApproveToolUseHandler
        def initialize(server)
          @server = server
          @pending = {}    # requestId => { mutex:, cond:, approved: }
          @mutex = Mutex.new
        end

        def call(params)
          request_id = params["requestId"]
          approved   = params["approved"]

          unless request_id
            return { "resolved" => false, "error" => "Missing requestId" }
          end

          entry = @mutex.synchronize { @pending[request_id] }

          unless entry
            return { "resolved" => false, "error" => "No pending request: #{request_id}" }
          end

          entry[:mutex].synchronize do
            entry[:approved] = approved
            entry[:cond].signal
          end

          @mutex.synchronize { @pending.delete(request_id) }

          { "resolved" => true, "requestId" => request_id }
        end

        # Register a pending tool approval. Called by the agent thread
        # before executing a tool that requires user confirmation.
        #
        # @param request_id [String] unique identifier for this approval
        # @param tool_name [String] name of the tool awaiting approval
        # @param tool_params [Hash] parameters the tool will receive
        # @return [Boolean] whether the tool use was approved
        def wait_for_approval(request_id, tool_name, tool_params)
          entry = {
            mutex:    Mutex.new,
            cond:     ConditionVariable.new,
            approved: nil
          }

          @mutex.synchronize { @pending[request_id] = entry }

          @server.notify("tool/approval_required", {
            "requestId" => request_id,
            "tool"      => tool_name,
            "params"    => tool_params
          })

          # Block until the IDE extension responds
          entry[:mutex].synchronize do
            entry[:cond].wait(entry[:mutex]) while entry[:approved].nil?
          end

          entry[:approved]
        end

        # Check if there are any pending approvals.
        def pending?
          @mutex.synchronize { !@pending.empty? }
        end
      end
    end
  end
end
