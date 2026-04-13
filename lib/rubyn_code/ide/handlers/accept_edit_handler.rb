# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "acceptEdit" JSON-RPC request.
      #
      # The extension sends this after the user accepts or rejects a proposed
      # file edit surfaced via a file/edit or file/create notification. All
      # pending-edit state lives in the per-session ToolOutput adapter; this
      # handler is a thin delegate so the server has something to register at
      # the method name.
      class AcceptEditHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          edit_id  = params['editId']
          accepted = params['accepted']

          return { 'applied' => false, 'error' => 'Missing editId' } unless edit_id

          adapter = @server.tool_output_adapter
          return { 'applied' => false, 'error' => 'No active session' } unless adapter

          resolved = adapter.resolve_edit(edit_id, accepted ? true : false)
          return { 'applied' => false, 'error' => "No pending edit: #{edit_id}" } unless resolved

          { 'applied' => accepted ? true : false }
        end
      end
    end
  end
end
