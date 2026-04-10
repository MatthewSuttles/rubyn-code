# frozen_string_literal: true

module RubynCode
  module IDE
    module Adapters
      # Wraps the existing tool execution pipeline for IDE mode.
      #
      # Emits JSON-RPC notifications before/after tool execution, gates
      # destructive operations behind approval from the IDE client, and
      # intercepts file writes so the editor can show a diff before
      # committing changes to disk.
      class ToolOutput
        APPROVAL_TIMEOUT = 60 # seconds

        READ_ONLY_TOOLS = %w[
          read_file glob grep
          git_status git_diff git_log git_commit
          memory_search web_fetch web_search
        ].freeze

        FILE_WRITE_TOOLS = %w[write_file edit_file].freeze

        def initialize(server, yolo: false)
          @server = server
          @yolo   = yolo
          @mutex  = Mutex.new

          # { request_id => { cv: ConditionVariable, approved: nil|true|false } }
          @pending_approvals = {}

          # { edit_id => { cv: ConditionVariable, accepted: nil|true|false } }
          @pending_edits = {}
        end

        # Main entry point. Wraps a tool call, emitting IDE notifications
        # and gating execution behind approval when required.
        #
        #   adapter.wrap_execution("write_file", { path: "foo.rb", content: "..." }) do
        #     executor.execute("write_file", params)
        #   end
        #
        def wrap_execution(tool_name, args, &original_execute)
          request_id = generate_id

          if read_only?(tool_name)
            return execute_and_notify(request_id, tool_name, args, &original_execute)
          end

          if tool_name == "run_specs"
            return execute_streaming(request_id, tool_name, args, &original_execute)
          end

          if file_write?(tool_name)
            return execute_with_edit_gate(request_id, tool_name, args, &original_execute)
          end

          # bash and other mutating tools: emit tool/use, optionally wait for approval
          execute_with_approval(request_id, tool_name, args, &original_execute)
        end

        # Called by ApproveToolUseHandler when the IDE client responds.
        def resolve_approval(request_id, approved)
          @mutex.synchronize do
            pending = @pending_approvals[request_id]
            return unless pending

            pending[:approved] = approved
            pending[:cv].signal
          end
        end

        # Called by AcceptEditHandler when the IDE client responds.
        def resolve_edit(edit_id, accepted)
          @mutex.synchronize do
            pending = @pending_edits[edit_id]
            return unless pending

            pending[:accepted] = accepted
            pending[:cv].signal
          end
        end

        private

        # ── Read-only tools ──────────────────────────────────────────────

        def execute_and_notify(request_id, tool_name, args)
          emit_tool_use(request_id, tool_name, args, requires_approval: false)
          result = yield
          emit_tool_result(request_id, tool_name, result, success: true)
          result
        rescue StandardError => e
          emit_tool_result(request_id, tool_name, e.message, success: false)
          raise
        end

        # ── Streaming tools (run_specs) ──────────────────────────────────

        def execute_streaming(request_id, tool_name, args)
          emit_tool_use(request_id, tool_name, args, requires_approval: false)
          result = yield
          emit_tool_result(request_id, tool_name, result, success: true)
          result
        rescue StandardError => e
          emit_tool_result(request_id, tool_name, e.message, success: false)
          raise
        end

        # ── File write tools (write_file, edit_file) ─────────────────────

        def execute_with_edit_gate(request_id, tool_name, args)
          emit_tool_use(request_id, tool_name, args, requires_approval: false)

          if @yolo
            result = yield
            emit_tool_result(request_id, tool_name, result, success: true)
            return result
          end

          # Emit a file/edit or file/create notification and wait for acceptance
          edit_id = generate_id
          notification_method = file_exists?(tool_name, args) ? "file/edit" : "file/create"

          @server.notify(notification_method, {
            "editId"   => edit_id,
            "toolName" => tool_name,
            "path"     => args["path"] || args[:path],
            "args"     => args
          })

          accepted = wait_for_edit(edit_id)

          unless accepted
            summary = "Edit denied by IDE user (#{notification_method})"
            emit_tool_result(request_id, tool_name, summary, success: false)
            return summary
          end

          result = yield
          emit_tool_result(request_id, tool_name, result, success: true)
          result
        rescue StandardError => e
          emit_tool_result(request_id, tool_name, e.message, success: false)
          raise
        end

        # ── Approval-gated tools (bash, etc.) ────────────────────────────

        def execute_with_approval(request_id, tool_name, args)
          requires_approval = !@yolo
          emit_tool_use(request_id, tool_name, args, requires_approval: requires_approval)

          if @yolo
            result = yield
            emit_tool_result(request_id, tool_name, result, success: true)
            return result
          end

          approved = wait_for_approval(request_id)

          unless approved
            summary = "Tool execution denied by IDE user"
            emit_tool_result(request_id, tool_name, summary, success: false)
            return summary
          end

          result = yield
          emit_tool_result(request_id, tool_name, result, success: true)
          result
        rescue StandardError => e
          emit_tool_result(request_id, tool_name, e.message, success: false)
          raise
        end

        # ── Notifications ────────────────────────────────────────────────

        def emit_tool_use(request_id, tool_name, args, requires_approval:)
          @server.notify("tool/use", {
            "requestId"        => request_id,
            "toolName"         => tool_name,
            "args"             => args,
            "requiresApproval" => requires_approval
          })
        end

        def emit_tool_result(request_id, tool_name, result, success:)
          summary = result.is_a?(String) ? result[0, 500] : result.to_s[0, 500]

          @server.notify("tool/result", {
            "requestId" => request_id,
            "toolName"  => tool_name,
            "success"   => success,
            "summary"   => summary
          })
        end

        # ── Blocking waits ───────────────────────────────────────────────

        def wait_for_approval(request_id)
          cv = ConditionVariable.new

          @mutex.synchronize do
            @pending_approvals[request_id] = { cv: cv, approved: nil }
          end

          @mutex.synchronize do
            deadline = Time.now + APPROVAL_TIMEOUT
            while @pending_approvals[request_id][:approved].nil?
              remaining = deadline - Time.now
              break if remaining <= 0

              cv.wait(@mutex, remaining)
            end

            approved = @pending_approvals.delete(request_id)[:approved]
            # Auto-deny on timeout
            approved.nil? ? false : approved
          end
        end

        def wait_for_edit(edit_id)
          cv = ConditionVariable.new

          @mutex.synchronize do
            @pending_edits[edit_id] = { cv: cv, accepted: nil }
          end

          @mutex.synchronize do
            deadline = Time.now + APPROVAL_TIMEOUT
            while @pending_edits[edit_id][:accepted].nil?
              remaining = deadline - Time.now
              break if remaining <= 0

              cv.wait(@mutex, remaining)
            end

            accepted = @pending_edits.delete(edit_id)[:accepted]
            # Auto-deny on timeout
            accepted.nil? ? false : accepted
          end
        end

        # ── Helpers ──────────────────────────────────────────────────────

        def read_only?(tool_name)
          READ_ONLY_TOOLS.include?(tool_name)
        end

        def file_write?(tool_name)
          FILE_WRITE_TOOLS.include?(tool_name)
        end

        def file_exists?(tool_name, args)
          return true if tool_name == "edit_file"

          path = args["path"] || args[:path]
          path && File.exist?(path)
        end

        def generate_id
          "#{Time.now.to_i}-#{SecureRandom.hex(4)}"
        end
      end
    end
  end
end
