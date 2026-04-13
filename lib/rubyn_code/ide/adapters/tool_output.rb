# frozen_string_literal: true

require 'securerandom'

module RubynCode
  module IDE
    module Adapters
      # Wraps every tool invocation in IDE mode. Emits JSON-RPC notifications
      # that the VS Code extension consumes, precomputes file edits so the
      # editor can render a diff before any write touches disk, and gates
      # mutating operations behind acceptance/approval from the IDE client.
      #
      # Gating policy (when yolo is off):
      #   - read-only tools  → run immediately, emit tool/use + tool/result
      #   - file write tools → emit file/edit or file/create with proposed
      #                        content, wait for acceptEdit, then run
      #   - other mutating   → emit tool/use with requiresApproval, wait for
      #                        approveToolUse, then run
      #
      # When yolo is on the adapter still emits notifications (so the UI
      # reflects what's happening) but skips the approval round-trip.
      class ToolOutput
        APPROVAL_TIMEOUT = 60 # seconds

        READ_ONLY_TOOLS = %w[
          read_file glob grep
          git_status git_diff git_log git_commit
          memory_search web_fetch web_search
          run_specs
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
        # and gating execution behind acceptance when required.
        #
        #   adapter.wrap_execution("write_file", { path: "foo.rb", content: "..." }) do
        #     executor.execute("write_file", params)
        #   end
        #
        def wrap_execution(tool_name, args, &block)
          request_id = generate_id
          args = stringify_keys(args)

          return execute_and_notify(request_id, tool_name, args, &block) if read_only?(tool_name)
          return execute_with_edit_gate(request_id, tool_name, args, &block) if file_write?(tool_name)

          # bash and other mutating tools: emit tool/use, optionally wait for approval
          execute_with_approval(request_id, tool_name, args, &block)
        end

        # Called by ApproveToolUseHandler when the IDE client responds.
        def resolve_approval(request_id, approved)
          @mutex.synchronize do
            pending = @pending_approvals[request_id]
            return false unless pending

            pending[:approved] = approved
            pending[:cv].signal
            true
          end
        end

        # Called by AcceptEditHandler when the IDE client responds.
        def resolve_edit(edit_id, accepted)
          @mutex.synchronize do
            pending = @pending_edits[edit_id]
            return false unless pending

            pending[:accepted] = accepted
            pending[:cv].signal
            true
          end
        end

        private

        # ── Read-only and streaming paths ────────────────────────────────

        def execute_and_notify(request_id, tool_name, args)
          emit_tool_use(request_id, tool_name, args, requires_approval: false)
          result = yield
          emit_tool_result(request_id, tool_name, result, success: true, args: args)
          result
        rescue StandardError => e
          emit_tool_result(request_id, tool_name, e.message, success: false, args: args)
          raise
        end

        # ── File write tools (write_file, edit_file) ─────────────────────

        def execute_with_edit_gate(request_id, tool_name, args, &)
          emit_tool_use(request_id, tool_name, args, requires_approval: false)

          preview = compute_preview(tool_name, args)
          return emit_error(request_id, tool_name, preview[:error]) if preview[:error]

          # Always emit the file/edit or file/create notification so the
          # extension can surface the change — opens a diff editor in normal
          # mode or flashes "Rubyn auto-applied…" and applies via workspace
          # edit in yolo mode. Either way the user sees what changed.
          accepted = notify_and_await_edit(preview, args)
          return deny_edit(request_id, tool_name, preview[:type]) unless accepted

          apply_edit(request_id, tool_name, args, &)
        end

        def compute_preview(tool_name, args)
          tool = build_tool(tool_name)
          sym_args = symbolize_keys(args)
          result = tool.preview_content(**sym_args)
          { content: result[:content], type: result[:type] }
        rescue StandardError => e
          { error: e.message }
        end

        def build_tool(tool_name)
          klass = Tools::Registry.get(tool_name)
          klass.new(project_root: @server.workspace_path || Dir.pwd)
        end

        def notify_and_await_edit(preview, args)
          edit_id = generate_id
          path = args['path']
          method = preview[:type] == 'create' ? 'file/create' : 'file/edit'

          params = { 'editId' => edit_id, 'path' => path, 'content' => preview[:content] }
          params['type'] = preview[:type] if method == 'file/edit'

          @server.notify(method, params)
          wait_for_edit(edit_id)
        end

        def apply_edit(request_id, tool_name, args)
          result = yield
          emit_tool_result(request_id, tool_name, result, success: true, args: args)
          result
        rescue StandardError => e
          emit_tool_result(request_id, tool_name, e.message, success: false, args: args)
          raise
        end

        def deny_edit(request_id, tool_name, type)
          summary = "User rejected this #{type}. Do not retry the same content."
          emit_tool_result(request_id, tool_name, summary, success: false)
          raise RubynCode::UserDeniedError, summary
        end

        def emit_error(request_id, tool_name, message)
          summary = "Error: #{message}"
          emit_tool_result(request_id, tool_name, summary, success: false)
          summary
        end

        # ── Approval-gated tools (bash, etc.) ────────────────────────────

        def execute_with_approval(request_id, tool_name, args)
          requires_approval = !@yolo
          emit_tool_use(request_id, tool_name, args, requires_approval: requires_approval)

          if @yolo
            result = yield
            emit_tool_result(request_id, tool_name, result, success: true, args: args)
            return result
          end

          approved = wait_for_approval(request_id)
          unless approved
            summary = 'User refused this tool invocation. Do not retry the same call.'
            emit_tool_result(request_id, tool_name, summary, success: false, args: args)
            raise RubynCode::UserDeniedError, summary
          end

          result = yield
          emit_tool_result(request_id, tool_name, result, success: true, args: args)
          result
        rescue StandardError => e
          emit_tool_result(request_id, tool_name, e.message, success: false, args: args)
          raise
        end

        # ── Notifications ────────────────────────────────────────────────

        def emit_tool_use(request_id, tool_name, args, requires_approval:)
          @server.notify('tool/use', {
                           'requestId' => request_id,
                           'tool' => tool_name,
                           'args' => args,
                           'requiresApproval' => requires_approval
                         })
        end

        def emit_tool_result(request_id, tool_name, result, success:, args: {})
          @server.notify('tool/result', {
                           'requestId' => request_id,
                           'tool' => tool_name,
                           'success' => success,
                           'summary' => build_summary(tool_name, result, success, args)
                         })
        end

        # Ask the tool class for its one-line summary ("Edited foo.rb (1
        # replacement)", "grep pattern (12 lines)", etc.). Tools that don't
        # override Base.summarize return "", and the UI renders a clean
        # "Done". The full tool output always lives in the conversation —
        # summary is display-only. On failure we include the error so the
        # user can see what went wrong.
        def build_summary(tool_name, result, success, args)
          return result.to_s[0, 500] unless success

          klass = tool_class(tool_name)
          return '' unless klass

          klass.summarize(result.to_s, args || {}).to_s[0, 500]
        rescue StandardError
          ''
        end

        def tool_class(tool_name)
          Tools::Registry.get(tool_name)
        rescue ToolNotFoundError
          nil
        end

        # ── Blocking waits ───────────────────────────────────────────────

        def wait_for_approval(request_id)
          cv = ConditionVariable.new
          @mutex.synchronize { @pending_approvals[request_id] = { cv: cv, approved: nil } }

          @mutex.synchronize do
            deadline = Time.now + APPROVAL_TIMEOUT
            while @pending_approvals[request_id][:approved].nil?
              remaining = deadline - Time.now
              break if remaining <= 0

              cv.wait(@mutex, remaining)
            end
            approved = @pending_approvals.delete(request_id)[:approved]
            approved.nil? ? false : approved # auto-deny on timeout
          end
        end

        def wait_for_edit(edit_id)
          cv = ConditionVariable.new
          @mutex.synchronize { @pending_edits[edit_id] = { cv: cv, accepted: nil } }

          @mutex.synchronize do
            deadline = Time.now + APPROVAL_TIMEOUT
            while @pending_edits[edit_id][:accepted].nil?
              remaining = deadline - Time.now
              break if remaining <= 0

              cv.wait(@mutex, remaining)
            end
            accepted = @pending_edits.delete(edit_id)[:accepted]
            accepted.nil? ? false : accepted # auto-deny on timeout
          end
        end

        # ── Helpers ──────────────────────────────────────────────────────

        def read_only?(tool_name)
          READ_ONLY_TOOLS.include?(tool_name)
        end

        def file_write?(tool_name)
          FILE_WRITE_TOOLS.include?(tool_name)
        end

        def stringify_keys(hash)
          return {} unless hash.is_a?(Hash)

          hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
        end

        def symbolize_keys(hash)
          hash.each_with_object({}) { |(k, v), memo| memo[k.to_sym] = v }
        end

        def generate_id
          "#{Time.now.to_i}-#{SecureRandom.hex(4)}"
        end
      end
    end
  end
end
