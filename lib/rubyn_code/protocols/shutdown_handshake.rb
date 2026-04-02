# frozen_string_literal: true

module RubynCode
  module Protocols
    # Graceful shutdown protocol for agent teammates.
    #
    # Implements a cooperative handshake where a coordinator requests
    # shutdown and the target agent acknowledges after saving state.
    module ShutdownHandshake
      # Default timeout in seconds when waiting for a shutdown response.
      TIMEOUT = 10

      class << self
        # Initiates a shutdown request to a teammate and waits for acknowledgement.
        #
        # @param mailbox [Teams::Mailbox] the team mailbox
        # @param from [String] the requesting agent name
        # @param to [String] the target agent name to shut down
        # @param timeout [Integer] seconds to wait for response (default: 10)
        # @return [Symbol] :acknowledged or :timeout
        def initiate(mailbox:, from:, to:, timeout: TIMEOUT)
          mailbox.send(
            from: from,
            to: to,
            content: "shutdown_request",
            message_type: "shutdown_request"
          )

          deadline = Time.now + timeout

          loop do
            messages = mailbox.read_inbox(from)
            response = messages.find do |msg|
              msg[:from] == to && msg[:message_type] == "shutdown_response"
            end

            return :acknowledged if response

            return :timeout if Time.now >= deadline

            sleep(0.25)
          end
        end

        # Sends a shutdown response (approval or denial) from the target agent.
        #
        # @param mailbox [Teams::Mailbox] the team mailbox
        # @param from [String] the responding agent name
        # @param to [String] the agent that requested the shutdown
        # @param approve [Boolean] whether to approve the shutdown (default: true)
        # @return [String] the message id
        def respond(mailbox:, from:, to:, approve: true)
          content = approve ? "shutdown_approved" : "shutdown_denied"

          mailbox.send(
            from: from,
            to: to,
            content: content,
            message_type: "shutdown_response"
          )
        end

        # Performs a full graceful shutdown for an agent: saves state,
        # sends acknowledgement, and sets status to offline.
        #
        # @param agent_name [String] the agent being shut down
        # @param mailbox [Teams::Mailbox] the team mailbox
        # @param session_persistence [#save_session] persistence layer for saving session state
        # @param conversation [Agent::Conversation] the agent's conversation to persist
        # @param requester [String, nil] the agent that requested shutdown (for acknowledgement)
        # @return [void]
        def graceful_shutdown(agent_name, mailbox:, session_persistence:, conversation:, requester: nil)
          # Step 1: Save current session state
          save_state(agent_name, session_persistence, conversation)

          # Step 2: Send shutdown acknowledgement if there is a requester
          if requester
            respond(mailbox: mailbox, from: agent_name, to: requester, approve: true)
          end

          # Step 3: Broadcast offline status to all listeners
          mailbox.send(
            from: agent_name,
            to: "_system",
            content: "#{agent_name} is now offline",
            message_type: "status_change"
          )
        end

        private

        # Saves the agent's session state via the persistence layer.
        #
        # @param agent_name [String]
        # @param session_persistence [#save_session]
        # @param conversation [Agent::Conversation]
        # @return [void]
        def save_state(agent_name, session_persistence, conversation)
          session_persistence.save_session(
            agent_name: agent_name,
            messages: conversation.messages
          )
        rescue StandardError => e
          $stderr.puts "[ShutdownHandshake] Warning: failed to save state for '#{agent_name}': #{e.message}"
        end
      end
    end
  end
end
