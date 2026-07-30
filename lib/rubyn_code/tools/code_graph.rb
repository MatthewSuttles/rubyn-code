# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    # Codegraph-style exploration over the persistent codebase index: one
    # call answers "where is X and how is it wired?" with the verbatim
    # line-numbered source of matching symbols plus their callers, callees,
    # and affected files — replacing a grep + read_file loop.
    class CodeGraph < Base
      TOOL_NAME = 'code_graph'
      DESCRIPTION = 'Explores the codebase knowledge graph. Given symbol names or keywords, returns the ' \
                    'matching definitions with verbatim line-numbered source, the methods that call them, ' \
                    'the methods they call, and the affected files (including specs). Prefer this over ' \
                    'grep/read_file when locating or understanding code — one call replaces a search loop.'
      PARAMETERS = {
        query: { type: :string, required: true,
                 description: 'Symbol names or keywords, e.g. "build_request_body" or "task budget"' },
        max_symbols: { type: :integer, required: false, default: 5,
                       description: 'Maximum matching symbols to expand (default 5)' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      MAX_SOURCE_LINES = 60
      MAX_RELATED = 15
      MATCHABLE_TYPES = %w[class module model controller service concern method].freeze

      def self.summarize(output, args)
        query = args['query'] || args[:query] || ''
        count = output.to_s.scan(/^## /).size
        "code_graph #{query} (#{count} symbols)"
      end

      def execute(query:, max_symbols: 5)
        index = Index::CodebaseIndex.new(project_root: project_root)
        index.load_or_build!

        matches = ranked_matches(index, query, max_symbols)
        return "No symbols matching '#{query}' in the codebase index." if matches.empty?

        sections = matches.map { |node| render_symbol(index, node) }
        truncate(sections.join("\n\n"))
      end

      private

      def ranked_matches(index, query, limit)
        terms = query.to_s.downcase.split(/\W+/).reject(&:empty?)
        return [] if terms.empty?

        scored = index.nodes.filter_map do |node|
          next unless MATCHABLE_TYPES.include?(node['type'])

          score = score_node(node, terms)
          [score, node] if score.positive?
        end

        scored.sort_by { |score, node| [-score, node['file'].to_s] }
              .map(&:last)
              .uniq { |n| [n['name'], n['file'], n['line']] }
              .first(limit)
      end

      def score_node(node, terms)
        name = node['name'].to_s.downcase
        file = node['file'].to_s.downcase
        score = terms.sum do |term|
          if name == term then 100
          elsif name.include?(term) then 40
          elsif file.include?(term) then 10
          else 0
          end
        end
        # A name hitting every query term beats a single exact-term match.
        score += 50 if terms.size > 1 && terms.all? { |t| name.include?(t) }
        score
      end

      def render_symbol(index, node)
        header = [node['owner'], node['name']].reject { |p| p.nil? || p.empty? }.join('#')
        lines = ["## #{header} (#{node['file']}:#{node['line']})"]
        lines << source_slice(node)
        append_call_info(lines, index, node) if node['type'] == 'method'
        append_affected_files(lines, index, node)
        lines.join("\n")
      end

      def source_slice(node)
        path = File.join(project_root, node['file'].to_s)
        return '(source unavailable)' unless File.file?(path)

        start = [node['line'].to_i, 1].max
        finish = (node['end_line'] || (start + MAX_SOURCE_LINES)).to_i
        truncated = finish > start + MAX_SOURCE_LINES
        finish = start + MAX_SOURCE_LINES if truncated

        slice = File.readlines(path)[(start - 1)..(finish - 1)] || []
        rendered = slice.each_with_index.map { |line, i| "#{(start + i).to_s.rjust(5)}| #{line.rstrip}" }
        rendered << "  ...| (truncated at #{MAX_SOURCE_LINES} lines)" if truncated
        rendered.join("\n")
      end

      def append_call_info(lines, index, node)
        callers = call_edges(index).select { |e| e['to'] == node['name'] }
        callees = call_edges(index).select { |e| e['from'] == node['file'] && e['from_method'] == node['name'] }

        unless callers.empty?
          described = callers.first(MAX_RELATED).map { |e| "#{e['from_method']} (#{e['from']}:#{e['line']})" }
          lines << "Called by: #{described.uniq.join(', ')}"
        end
        return if callees.empty?

        lines << "Calls: #{callees.map { |e| e['to'] }.uniq.first(MAX_RELATED).join(', ')}"
      end

      def append_affected_files(lines, index, node)
        caller_files = call_edges(index).select { |e| e['to'] == node['name'] }.map { |e| e['from'] }
        spec_edges = index.edges.select { |e| e['relationship'] == 'tests' && e['to'] == node['file'] }
        spec_files = spec_edges.map { |e| e['from'] }
        affected = (caller_files + spec_files).uniq - [node['file']]
        lines << "Affected files: #{affected.first(MAX_RELATED).join(', ')}" unless affected.empty?
      end

      def call_edges(index)
        @call_edges ||= index.edges.select { |e| e['relationship'] == 'calls' }
      end
    end

    Registry.register(CodeGraph)
  end
end
