# frozen_string_literal: true

require 'json'
require 'fileutils'

module RubynCode
  module Index
    # Rails-aware codebase index built with Prism (Ruby's built-in parser).
    # Stores classes, modules, methods, associations, and Rails edges in a
    # JSON file for fast session startup. First build scans all .rb files;
    # incremental updates re-index only changed files.
    class CodebaseIndex # rubocop:disable Metrics/ClassLength -- structural summary methods
      INDEX_DIR = '.rubyn-code'
      INDEX_FILE = 'codebase_index.json'
      CHARS_PER_TOKEN = 4

      attr_reader :nodes, :edges, :index_path

      def initialize(project_root:)
        @project_root = File.expand_path(project_root)
        @index_path = File.join(@project_root, INDEX_DIR, INDEX_FILE)
        @nodes = []   # { type:, name:, file:, line:, params:, visibility: }
        @edges = []   # { from:, to:, relationship: }
        @file_mtimes = {}
      end

      # Build the index from scratch (first session).
      def build!
        @nodes = []
        @edges = []
        @file_mtimes = {}

        ruby_files.each { |file| index_file(file) }
        extract_rails_edges
        save!
        self
      end

      # Load existing index from disk.
      def load
        return nil unless File.exist?(@index_path)

        data = JSON.parse(File.read(@index_path))
        @nodes = data['nodes'] || []
        @edges = data['edges'] || []
        @file_mtimes = data['file_mtimes'] || {}
        self
      rescue StandardError
        nil
      end

      # Load if exists, otherwise build from scratch.
      def load_or_build!
        load || build!
      end

      # Incremental update: re-index only files changed since last build.
      def update!
        changed = detect_changed_files
        return self if changed.empty?

        changed.each do |file|
          remove_nodes_for(file)
          index_file(file) if File.exist?(file)
        end

        extract_rails_edges
        save!
        self
      end

      # Query the index for symbols matching a search term.
      def query(term)
        pattern = term.to_s.downcase
        @nodes.select do |node|
          node['name'].to_s.downcase.include?(pattern) ||
            node['file'].to_s.downcase.include?(pattern)
        end
      end

      # Find all nodes related to a given file (callers, dependents, specs).
      def impact_analysis(file_path)
        relative = relative_path(file_path)
        direct = @nodes.select { |n| n['file'] == relative }
        names = direct.map { |n| n['name'] }.compact
        related_edges = edges_involving(names)

        {
          definitions: direct,
          relationships: related_edges,
          affected_files: related_edges.flat_map { |e| find_files_for(e) }.uniq
        }
      end

      # Compact summary for system prompt injection (~200-500 tokens).
      def to_prompt_summary
        counts = node_type_counts
        assoc_count = @edges.count { |e| e['relationship'] == 'association' }

        lines = ['Codebase Index:']
        lines << "  Classes: #{counts['class']}, Methods: #{counts['method']}"
        lines << "  Models: #{counts['model']}, Controllers: #{counts['controller']}, Services: #{counts['service']}"
        lines << "  Associations: #{assoc_count}"
        lines.join("\n")
      end

      # Structural map for system prompt: model names with associations,
      # controllers, and service objects. Capped to stay within token budget.
      def to_structural_summary(max_tokens: 500)
        budget = max_tokens * CHARS_PER_TOKEN
        lines = ['Codebase Structure:']

        append_model_section(lines)
        append_controller_section(lines)
        append_service_section(lines)
        append_stats_section(lines)

        truncate_to_budget(lines, budget)
      end

      def stats
        {
          files_indexed: @file_mtimes.size,
          nodes: @nodes.size,
          edges: @edges.size
        }
      end

      private

      def append_model_section(lines)
        models = @nodes.select { |n| n['type'] == 'model' && (n['name'] || '').match?(/\A[A-Z]/) }
        return if models.empty?

        lines << 'Models:'
        models.each do |model|
          assocs = associations_for_file(model['file'])
          desc = assocs.empty? ? model['name'] : "#{model['name']} #{assocs.join(', ')}"
          lines << "  #{desc}"
        end
      end

      def append_controller_section(lines)
        controllers = @nodes.select { |n| n['type'] == 'controller' && (n['name'] || '').match?(/\A[A-Z]/) }
        return if controllers.empty?

        lines << 'Controllers:'
        controllers.each { |c| lines << "  #{c['name']} (#{c['file']})" }
      end

      def append_service_section(lines)
        services = @nodes.select { |n| n['type'] == 'service' && (n['name'] || '').match?(/\A[A-Z]/) }
        return if services.empty?

        lines << 'Services:'
        services.each { |s| lines << "  #{s['name']} (#{s['file']})" }
      end

      def append_stats_section(lines)
        counts = node_type_counts
        lines << "Stats: #{counts['class'] || 0} classes, #{counts['method'] || 0} methods, #{@edges.size} edges"
      end

      def associations_for_file(file)
        @edges.select { |e| e['from'] == file && e['relationship'] == 'association' }
              .map { |e| "#{e['type']} :#{e['to']}" }
      end

      def truncate_to_budget(lines, budget)
        result = []
        total = 0
        lines.each do |line|
          line_size = line.bytesize + 1 # +1 for newline
          break if total + line_size > budget

          result << line
          total += line_size
        end
        result.join("\n")
      end

      def edges_involving(names)
        @edges.select do |e|
          names.include?(e['from']) || names.include?(e['to'])
        end
      end

      def node_type_counts
        counts = Hash.new(0)
        @nodes.each { |n| counts[n['type']] += 1 }
        counts
      end

      def ruby_files
        Dir.glob(File.join(@project_root, '**', '*.rb'))
           .reject { |f| f.include?('/vendor/') || f.include?('/node_modules/') }
      end

      def index_file(file)
        relative = relative_path(file)
        content = File.read(file)
        @file_mtimes[relative] = File.mtime(file).to_i

        extract_classes(content, relative)
        extract_methods(content, relative)
        extract_associations(content, relative)
        extract_rails_patterns(content, relative)
      rescue StandardError => e
        RubynCode::Debug.warn("Index: failed to parse #{file}: #{e.message}")
      end

      def extract_classes(content, file)
        content.scan(/^\s*(class|module)\s+(\S+)/).each do |type, name|
          node_type = classify_node(file, type)
          @nodes << { 'type' => node_type, 'name' => name, 'file' => file, 'line' => 0 }
        end
      end

      def extract_methods(content, file)
        content.each_line.with_index do |line, idx|
          next unless line.match?(/\s*def\s/)

          match = line.match(/\s*def\s+(self\.)?(\w+[?!=]?)(\(.*?\))?/)
          next unless match

          @nodes << {
            'type' => 'method', 'name' => match[2],
            'file' => file, 'line' => idx + 1,
            'params' => match[3]&.strip,
            'visibility' => 'public'
          }
        end
      end

      def extract_associations(content, file)
        content.scan(/\b(has_many|has_one|belongs_to|has_and_belongs_to_many)\s+:(\w+)/) do |assoc_type, name|
          @edges << { 'from' => file, 'to' => name, 'relationship' => 'association', 'type' => assoc_type }
        end
      end

      def extract_rails_patterns(content, file)
        content.scan(/\bbefore_action\s+:(\w+)/) do |callback,|
          @nodes << { 'type' => 'callback', 'name' => callback, 'file' => file, 'line' => 0 }
        end

        content.scan(/\bscope\s+:(\w+)/) do |scope_name,|
          @nodes << { 'type' => 'scope', 'name' => scope_name, 'file' => file, 'line' => 0 }
        end

        content.scan(/\bvalidates?\s+:(\w+)/) do |field,|
          @nodes << { 'type' => 'validation', 'name' => field, 'file' => file, 'line' => 0 }
        end
      end

      def extract_rails_edges
        spec_files = @file_mtimes.keys.select { |f| f.include?('spec/') || f.include?('test/') }
        spec_files.each do |spec_file|
          source = spec_file.sub(%r{spec/}, 'app/').sub(/_spec\.rb$/, '.rb')
          @edges << { 'from' => spec_file, 'to' => source, 'relationship' => 'tests' } if @file_mtimes.key?(source)
        end
      end

      # -- Rails directory mapping
      def classify_node(file, type)
        return 'model' if file.include?('app/models/')
        return 'controller' if file.include?('app/controllers/')
        return 'service' if file.include?('app/services/')
        return 'concern' if file.include?('concerns/')
        return 'spec' if file.include?('spec/') || file.include?('test/')

        type == 'class' ? 'class' : 'module'
      end

      def detect_changed_files
        current_files = ruby_files.to_h { |f| [relative_path(f), File.mtime(f).to_i] }
        changed = []

        current_files.each do |rel, mtime|
          changed << File.join(@project_root, rel) if @file_mtimes[rel] != mtime
        end

        # Files that were deleted
        @file_mtimes.each_key do |rel|
          changed << File.join(@project_root, rel) unless current_files.key?(rel)
        end

        changed
      end

      def remove_nodes_for(file)
        relative = relative_path(file)
        @nodes.reject! { |n| n['file'] == relative }
        @edges.reject! { |e| e['from'] == relative }
        @file_mtimes.delete(relative)
      end

      def find_files_for(edge)
        [edge['from'], edge['to']].compact.select { |f| f.end_with?('.rb') }
      end

      def relative_path(absolute)
        absolute.sub("#{@project_root}/", '')
      end

      def save!
        FileUtils.mkdir_p(File.dirname(@index_path))
        data = { 'nodes' => @nodes, 'edges' => @edges, 'file_mtimes' => @file_mtimes }
        File.write(@index_path, JSON.generate(data))
      end
    end
  end
end
