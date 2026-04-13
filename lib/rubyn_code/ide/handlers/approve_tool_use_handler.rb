# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "approveToolUse" JSON-RPC request.
      #
      # The extension sends this after the user approves or denies a tool
      # invocation surfaced with requiresApproval=true. All pending-approval
      # state lives in the per-session ToolOutput adapter; this handler is a
      # thin delegate so the server has something registered at the method name.
      class ApproveToolUseHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          request_id = params['requestId']
          approved   = params['approved']

          return { 'resolved' => false, 'error' => 'Missing requestId' } unless request_id

          adapter = @server.tool_output_adapter
          return { 'resolved' => false, 'error' => 'No active session' } unless adapter

          resolved = adapter.resolve_approval(request_id, approved ? true : false)
          return { 'resolved' => false, 'error' => "No pending request: #{request_id}" } unless resolved

          { 'resolved' => true, 'requestId' => request_id }
        end
      end
    end
  end
end
