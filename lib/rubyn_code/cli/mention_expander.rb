# frozen_string_literal: true

module RubynCode
  module CLI
    # Expands `@path/to/file` mentions in user input into inline file content,
    # mirroring Claude Code / Codex `@`-mentions. The original text is kept and
    # the referenced files are appended as labeled, fenced blocks so the agent
    # sees both the request and the files it points at.
    #
    # Conservative by design: only existing, readable, reasonably-sized regular
    # files inside the project are expanded. Unresolved mentions (and things
    # that merely look like mentions, e.g. email addresses) are left untouched.
    class MentionExpander
      # A mention is an "@" that doesn't follow a word char or another "@"
      # (so emails like foo@bar.com don't match), followed by a path-ish run.
      MENTION = /(?<![\w@])@([^\s@]+)/
      TRAILING_PUNCT = /[).,;:!?'"]+\z/
      MAX_FILE_BYTES = 64 * 1024
      MAX_FILES = 10

      # @param project_root [String]
      def initialize(project_root:)
        @project_root = project_root
      end

      # @param input [String] raw user input
      # @return [Array(String, Array<String>)] expanded text + resolved rel paths
      def expand(input)
        return [input, []] unless input.is_a?(String) && input.include?('@')

        resolved = scan(input)
        return [input, []] if resolved.empty?

        blocks = resolved.map { |rel, abs| file_block(rel, abs) }
        ["#{input}\n\n#{blocks.join("\n\n")}", resolved.map(&:first)]
      end

      private

      # @return [Array<Array(String, String)>] unique [rel, abs] pairs, in order
      def scan(input)
        seen = {}
        input.scan(MENTION).each do |(raw)|
          rel = raw.sub(TRAILING_PUNCT, '')
          next if rel.empty?

          abs = resolve(rel)
          next unless abs && !seen.key?(abs)

          seen[abs] = rel
          break if seen.size >= MAX_FILES
        end
        seen.map { |abs, rel| [rel, abs] }
      end

      # Resolve a mention to an absolute path inside the project, or nil.
      def resolve(rel)
        abs = File.expand_path(rel, @project_root)
        return nil unless inside_project?(abs)
        return nil unless File.file?(abs)

        abs
      rescue StandardError
        nil
      end

      def inside_project?(abs)
        root = File.expand_path(@project_root)
        abs == root || abs.start_with?("#{root}#{File::SEPARATOR}")
      end

      def file_block(rel, abs)
        body = read_truncated(abs)
        <<~BLOCK.strip
          @#{rel}:
          ```
          #{body}
          ```
        BLOCK
      end

      def read_truncated(abs)
        content = File.read(abs, MAX_FILE_BYTES + 1)
        return content if content.bytesize <= MAX_FILE_BYTES

        "#{content.byteslice(0, MAX_FILE_BYTES)}\n… [truncated]"
      rescue StandardError => e
        "[could not read file: #{e.message}]"
      end
    end
  end
end
