# frozen_string_literal: true

module RubynCode
  module SubAgents
    module Summarizer
      DEFAULT_MAX_LENGTH = 2000
      TRUNCATION_SUFFIX = "\n\n[... output truncated ...]"

      class << self
        def call(text, max_length: DEFAULT_MAX_LENGTH)
          return "" if text.nil? || text.empty?

          text = text.to_s.strip

          return text if text.length <= max_length

          truncate_with_context(text, max_length)
        end

        private

        def truncate_with_context(text, max_length)
          usable = max_length - TRUNCATION_SUFFIX.length
          return text[0, max_length] if usable <= 0

          # Keep the beginning (context setup) and end (final result) of the output.
          # The end usually contains the most relevant conclusion.
          head_size = (usable * 0.4).to_i
          tail_size = usable - head_size

          head = text[0, head_size]
          tail = text[-tail_size, tail_size]

          # Trim to nearest newline boundaries when possible to avoid mid-line cuts.
          head = trim_to_last_newline(head)
          tail = trim_to_first_newline(tail)

          "#{head}#{TRUNCATION_SUFFIX}\n\n#{tail}"
        end

        def trim_to_last_newline(text)
          last_nl = text.rindex("\n")
          return text unless last_nl && last_nl > (text.length * 0.5)

          text[0..last_nl]
        end

        def trim_to_first_newline(text)
          first_nl = text.index("\n")
          return text unless first_nl && first_nl < (text.length * 0.3)

          text[(first_nl + 1)..]
        end
      end
    end
  end
end
