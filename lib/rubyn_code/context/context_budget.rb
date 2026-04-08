# frozen_string_literal: true

module RubynCode
  module Context
    # Budget-aware context loader that prioritizes which related files
    # to load fully vs. as signatures-only. Prevents context bloat by
    # capping auto-loaded context at a configurable token budget.
    class ContextBudget
      CHARS_PER_TOKEN = 4
      DEFAULT_BUDGET = 4000 # tokens

      # Rails convention-based priority for related files.
      # Lower number = higher priority = loaded first.
      PRIORITY_MAP = {
        'spec' => 1, # tests for the file
        'factory' => 2,  # FactoryBot factories
        'service' => 3,  # service objects
        'model' => 4, # related models
        'controller' => 5,  # controllers
        'serializer' => 6,  # serializers
        'concern' => 7, # concerns/mixins
        'helper' => 8, # helpers
        'migration' => 9 # migrations
      }.freeze

      attr_reader :loaded_files, :signature_files, :tokens_used

      def initialize(budget: DEFAULT_BUDGET, codebase_index: nil)
        @budget = budget
        @codebase_index = codebase_index
        @loaded_files = []
        @signature_files = []
        @tokens_used = 0
      end

      # Load context for a primary file, filling budget with related files.
      # Returns array of { file:, content:, mode: :full|:signatures }
      #
      # When a codebase_index is available and no related_files are supplied,
      # uses impact_analysis to auto-discover related files (specs,
      # associated models, controllers, etc.).
      def load_for(file_path, related_files: [])
        results = []

        # Primary file always loads fully
        primary_content = safe_read(file_path)
        return results unless primary_content

        primary_tokens = estimate_tokens(primary_content)
        @tokens_used = primary_tokens
        @loaded_files << file_path
        results << { file: file_path, content: primary_content, mode: :full }

        # Auto-discover related files from the index when none supplied
        related_files = discover_related_files(file_path) if related_files.empty? && @codebase_index

        # Sort related files by priority and fill remaining budget
        sorted = prioritize(related_files)
        remaining = @budget - @tokens_used
        remaining = load_full_files(sorted, results, remaining)
        load_signature_files(sorted, results, remaining)

        results
      end

      # Extract method signatures and class structure without method bodies.
      # Much more compact than full source — typically 10-20% of original size.
      def extract_signatures(content)
        signatures = []
        indent_stack = []

        content.lines.each do |line|
          process_signature_line(line, signatures, indent_stack)
        end

        signatures.join
      end

      # Returns budget utilization stats.
      def stats
        {
          budget: @budget,
          tokens_used: @tokens_used,
          utilization: @budget.positive? ? (@tokens_used.to_f / @budget).round(3) : 0.0,
          full_files: @loaded_files.size,
          signature_files: @signature_files.size
        }
      end

      private

      def discover_related_files(file_path)
        analysis = @codebase_index.impact_analysis(file_path)
        analysis[:affected_files].reject { |f| f == file_path }
      rescue StandardError
        []
      end

      def load_full_files(sorted, results, remaining)
        sorted.each do |rel_path|
          content = safe_read(rel_path)
          next unless content

          size = estimate_tokens(content)
          next unless size <= remaining

          results << { file: rel_path, content: content, mode: :full }
          @loaded_files << rel_path
          @tokens_used += size
          remaining -= size
        end
        remaining
      end

      def load_signature_files(sorted, results, remaining)
        sorted.each do |rel_path|
          next if @loaded_files.include?(rel_path)

          content = safe_read(rel_path)
          next unless content

          sigs = extract_signatures(content)
          sig_size = estimate_tokens(sigs)
          next unless sig_size <= remaining

          results << { file: rel_path, content: sigs, mode: :signatures }
          @signature_files << rel_path
          @tokens_used += sig_size
          remaining -= sig_size
        end
      end

      def process_signature_line(line, signatures, indent_stack) # rubocop:disable Metrics/AbcSize -- signature extraction dispatch
        stripped = line.strip
        if signature_line?(stripped)
          signatures << line
          indent_stack << current_indent(line) if block_opener?(stripped)
        elsif stripped == 'end' && indent_stack.any? && current_indent(line) <= indent_stack.last
          signatures << line
          indent_stack.pop
        elsif class_or_module_line?(stripped)
          signatures << line
          indent_stack << current_indent(line)
        end
      end

      def prioritize(files)
        files.sort_by do |path|
          basename = File.basename(path, '.*').downcase
          priority = PRIORITY_MAP.find { |key, _| basename.include?(key) }&.last || 10
          priority
        end
      end

      def signature_line?(stripped)
        stripped.match?(/\A\s*(def\s|attr_|include\s|extend\s|has_|belongs_|validates|scope\s|delegate\s)/)
      end

      def class_or_module_line?(stripped)
        stripped.match?(/\A\s*(class|module)\s/)
      end

      def block_opener?(stripped)
        stripped.match?(/\Adef\s/)
      end

      def current_indent(line)
        line.match(/\A(\s*)/)[1].length
      end

      def safe_read(path)
        File.read(path)
      rescue StandardError
        nil
      end

      def estimate_tokens(text)
        (text.bytesize.to_f / CHARS_PER_TOKEN).ceil
      end
    end
  end
end
