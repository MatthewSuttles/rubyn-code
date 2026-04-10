# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "shutdown" JSON-RPC request.
      #
      # Triggers session persistence, signals the server to stop its
      # read loop, and returns confirmation.
      class ShutdownHandler
        def initialize(server)
          @server = server
        end

        def call(_params)
          $stderr.puts "[ShutdownHandler] shutdown requested"

          save_session!
          @server.stop!

          { "shutdown" => true }
        end

        private

        def save_session!
          return unless defined?(RubynCode::Memory::SessionPersistence)

          persistence = @server.session_persistence
          persistence&.save
        rescue StandardError => e
          $stderr.puts "[ShutdownHandler] session save failed: #{e.message}"
        end
      end
    end
  end
end
