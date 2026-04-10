# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "acceptEdit" JSON-RPC request.
      #
      # When the agent proposes a file edit, the IDE can present it as a
      # diff for user review. This handler resolves the pending edit
      # condition variable, signalling the agent to apply or skip the change.
      class AcceptEditHandler
        def initialize(server)
          @server = server
          @pending = {}    # editId => { mutex:, cond:, accepted: }
          @mutex = Mutex.new
        end

        def call(params)
          edit_id  = params["editId"]
          accepted = params["accepted"]

          unless edit_id
            return { "applied" => false, "error" => "Missing editId" }
          end

          entry = @mutex.synchronize { @pending[edit_id] }

          unless entry
            return { "applied" => false, "error" => "No pending edit: #{edit_id}" }
          end

          entry[:mutex].synchronize do
            entry[:accepted] = accepted
            entry[:cond].signal
          end

          @mutex.synchronize { @pending.delete(edit_id) }

          { "applied" => accepted }
        end

        # Register a pending edit for user approval. Called by the agent
        # thread when a file edit needs IDE-side confirmation.
        #
        # @param edit_id [String] unique identifier for this edit
        # @param file_path [String] absolute path to the file being edited
        # @param diff [String] the proposed diff or content change
        # @return [Boolean] whether the edit was accepted
        def wait_for_acceptance(edit_id, file_path, diff)
          entry = {
            mutex:    Mutex.new,
            cond:     ConditionVariable.new,
            accepted: nil
          }

          @mutex.synchronize { @pending[edit_id] = entry }

          @server.notify("edit/proposed", {
            "editId"   => edit_id,
            "filePath" => file_path,
            "diff"     => diff
          })

          # Block until the IDE extension responds
          entry[:mutex].synchronize do
            entry[:cond].wait(entry[:mutex]) while entry[:accepted].nil?
          end

          entry[:accepted]
        end

        # Check if there are any pending edits.
        def pending?
          @mutex.synchronize { !@pending.empty? }
        end
      end
    end
  end
end
