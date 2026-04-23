# frozen_string_literal: true

module RubynCode
  module Rules
    module Callbacks
      # CB001 — after_save Where after_commit Needed
      #
      # Detects after_save callbacks that perform external side effects such as
      # enqueuing background jobs, sending emails, or calling external APIs.
      # These operations should use after_commit instead, because after_save
      # runs inside the database transaction — if the transaction rolls back,
      # the side effect has already fired on uncommitted data.
      #
      # Positive examples:
      #   after_save :enqueue_sync_job
      #   after_save { UserMailer.welcome(self).deliver_later }
      #   after_save :notify_external_api
      #
      # Negative examples (safe):
      #   after_commit :enqueue_sync_job
      #   after_save :update_cached_name   # no external side effect
      #   after_save :set_defaults          # local mutation only
      class Cb001AfterSaveVsCommit < Base
        ID = "CB001"
        CATEGORY = :callbacks
        SEVERITY = :high
        RAILS_VERSIONS = [">= 5.0"].freeze
        CONFIDENCE_FLOOR = 0.8

        # Patterns that indicate external side effects inside a callback body
        # or in a method likely called by the callback.
        SIDE_EFFECT_PATTERNS = [
          # Background jobs
          /\.perform_later/,
          /\.perform_async/,
          /\.perform_in/,
          /\.set\(.*\)\.perform_later/,
          /Delayed::Job/,
          /\.delay\b/,
          /\.enqueue\b/,

          # Mailers
          /Mailer\b.*\.deliver/,
          /\.deliver_later/,
          /\.deliver_now/,

          # HTTP / external API calls
          /HTTParty\b/,
          /Faraday\b/,
          /RestClient\b/,
          /Net::HTTP\b/,
          /\.post\b/,
          /\.put\b/,
          /URI\.parse/,

          # Webhooks / notifications
          /webhook/i,
          /notify_external/i,
          /push_notification/i,
          /broadcast/i,

          # ActionCable
          /ActionCable/,
          /\.broadcast_to\b/,

          # Event bus / pub-sub
          /\.publish\b/,
          /EventBus/i,
          /ActiveSupport::Notifications\.instrument/
        ].freeze

        # Method name fragments that strongly suggest side effects when used
        # as after_save callback method names.
        SIDE_EFFECT_METHOD_NAMES = [
          /enqueue/i,
          /send_email/i,
          /send_notification/i,
          /deliver/i,
          /notify/i,
          /broadcast/i,
          /sync_to/i,
          /push_to/i,
          /publish/i,
          /post_to/i,
          /call_api/i,
          /webhook/i,
          /trigger_/i
        ].freeze

        class << self
          # Applies to changed Ruby files under app/models/.
          #
          # @param diff_data [Hash] must contain :changed_files array of file paths
          # @return [Boolean]
          def applies_to?(diff_data)
            changed_files = diff_data.fetch(:changed_files, [])
            changed_files.any? { |f| model_file?(f) }
          end

          # Returns the prompt text for LLM-based evaluation.
          #
          # @return [String]
          def prompt_module
            <<~PROMPT
              Detect `after_save` callbacks in Rails models that perform external
              side effects. External side effects include: enqueuing background jobs,
              sending emails or notifications, making HTTP requests, broadcasting
              via ActionCable, or publishing events.

              These callbacks should use `after_commit` instead, because `after_save`
              runs inside the database transaction. If the transaction rolls back,
              the side effect will have already executed on uncommitted data.

              Flag the callback if:
              1. The inline block contains a side-effect call.
              2. The referenced method name strongly implies a side effect
                 (e.g. enqueue_*, send_email_*, notify_*, broadcast_*).
              3. The method body (if visible in the diff) contains a side-effect call.

              Do NOT flag:
              - `after_commit` callbacks (already correct).
              - `after_save` callbacks that only mutate local attributes or
                update associations without external calls.
              - `after_save` with `on:` option used purely for data transforms.
            PROMPT
          end

          # Validates a finding by confirming the flagged line actually contains
          # an after_save with a side-effect indicator.
          #
          # @param finding  [Hash] :line_content, :line_number, :file_path
          # @param diff_data [Hash] :changed_files, :file_contents
          # @return [Boolean]
          def validate(finding, diff_data)
            line_content = finding.fetch(:line_content, "")
            file_path = finding.fetch(:file_path, "")

            return false unless model_file?(file_path)
            return false unless after_save_declaration?(line_content)

            # Check inline block for side effects
            return true if inline_side_effect?(line_content)

            # Check if the callback method name implies side effects
            method_name = extract_callback_method(line_content)
            return true if method_name && side_effect_method_name?(method_name)

            # Check if the method body is available in the diff
            if method_name
              file_contents = diff_data.fetch(:file_contents, {})
              body = file_contents.fetch(file_path, "")
              return true if method_body_has_side_effect?(body, method_name)
            end

            false
          end

          private

          # @param path [String]
          # @return [Boolean]
          def model_file?(path)
            path.match?(%r{app/models/.*\.rb\z})
          end

          # @param line [String]
          # @return [Boolean]
          def after_save_declaration?(line)
            line.match?(/\bafter_save\b/)
          end

          # Checks if an inline block on the after_save line contains a
          # side-effect pattern.
          #
          # @param line [String]
          # @return [Boolean]
          def inline_side_effect?(line)
            SIDE_EFFECT_PATTERNS.any? { |pattern| line.match?(pattern) }
          end

          # Extracts the symbol method name from an after_save declaration.
          # e.g. "after_save :enqueue_sync_job" => "enqueue_sync_job"
          #
          # @param line [String]
          # @return [String, nil]
          def extract_callback_method(line)
            match = line.match(/\bafter_save\s+:(\w+)/)
            match&.[](1)
          end

          # Checks if the method name itself suggests a side effect.
          #
          # @param method_name [String]
          # @return [Boolean]
          def side_effect_method_name?(method_name)
            SIDE_EFFECT_METHOD_NAMES.any? { |pattern| method_name.match?(pattern) }
          end

          # Scans the file body for the method definition and checks its
          # contents for side-effect patterns.
          #
          # @param body [String]
          # @param method_name [String]
          # @return [Boolean]
          def method_body_has_side_effect?(body, method_name)
            return false if body.empty?

            # Extract method body between def method_name ... end
            method_regex = /def\s+#{Regexp.escape(method_name)}\b(.*?)(?=\n\s*(?:def\s|\z|end\b))/m
            match = body.match(method_regex)
            return false unless match

            method_body = match[1]
            SIDE_EFFECT_PATTERNS.any? { |pattern| method_body.match?(pattern) }
          end
        end
      end
    end
  end
end

RubynCode::Rules::Registry.register(RubynCode::Rules::Callbacks::Cb001AfterSaveVsCommit)
