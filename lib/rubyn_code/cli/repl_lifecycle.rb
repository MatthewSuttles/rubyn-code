# frozen_string_literal: true

module RubynCode
  module CLI
    # Session persistence, shutdown, and learning extraction for the REPL.
    module ReplLifecycle
      GOODBYE_MESSAGES = [
        'Freezing strings and saving memories... See ya! 💎',
        'Memoizing this session... Until next time! 🧠',
        'Committing learnings to memory... Later! 🤙',
        'Saving state, yielding control... Bye for now! 👋',
        'Session.save! && Rubyn.sleep... Catch you later! 😴',
        "GC.start on this session... Stay Ruby, friend! \u270C\uFE0F",
        "Writing instincts to disk... Don't forget me! 💾",
        "at_exit { puts 'Thanks for coding with Rubyn!' } 🎸"
      ].freeze

      private

      def current_session_id
        @current_session_id ||= SecureRandom.hex(16)
      end

      def save_session!
        @session_persistence.save_session(
          session_id: current_session_id,
          project_path: @project_root,
          messages: @conversation.messages,
          model: Config::Defaults::DEFAULT_MODEL
        )
      end

      def resume_session!
        data = @session_persistence.load_session(@session_id)
        return unless data

        @conversation.replace!(data[:messages])
        @renderer.info("Resumed session #{@session_id[0..7]}")
      end

      def shutdown!
        return if @shutdown_complete

        @shutdown_complete = true
        @spinner.stop
        puts
        @renderer.info(GOODBYE_MESSAGES.sample)
        @renderer.info('Saving session...')
        save_session!
        @background_worker&.shutdown!
        disconnect_mcp_clients!
        extract_learnings_if_needed
        decay_instincts
        @renderer.info("Session saved. Rubyn out. \u270C\uFE0F")
      rescue StandardError
        # Best effort on shutdown
      end

      def extract_learnings_if_needed
        return unless @conversation.length > 5

        @renderer.info('Extracting learnings from this session...')
        Learning::Extractor.call(@conversation.messages, llm_client: @llm_client, project_path: @project_root)
        @renderer.success('Instincts saved.')
      rescue StandardError => e
        RubynCode::Debug.warn("Instinct extraction skipped: #{e.message}")
      end

      def decay_instincts
        Learning::InstinctMethods.decay_all(DB::Connection.instance, project_path: @project_root)
      rescue StandardError
        # Silent — decay is best-effort
      end
    end
  end
end
