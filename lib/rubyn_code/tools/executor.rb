# frozen_string_literal: true

module RubynCode
  module Tools
    class Executor
      attr_reader :project_root, :output_compressor, :file_cache
      attr_accessor :llm_client, :background_worker, :on_agent_status, :db, :ask_user_callback,
                    :codebase_index

      def initialize(project_root:)
        @project_root = File.expand_path(project_root)
        @injections = {}
        @output_compressor = OutputCompressor.new
        @file_cache = FileCache.new
        Registry.load_all!
      end

      def execute(tool_name, params) # rubocop:disable Metrics/AbcSize -- maps tool errors to results
        # File cache intercept: serve cached reads, invalidate on writes
        cached = try_file_cache(tool_name, params)
        return cached if cached

        tool = build_tool(tool_name)
        filtered = filter_params(tool, params)
        raw = tool.truncate(tool.execute(**filtered).to_s)
        update_file_cache(tool_name, filtered, raw)
        maybe_update_codebase_index(tool_name, filtered)
        @output_compressor.compress(tool_name, raw)
      rescue ToolNotFoundError => e
        error_result("Tool error: #{e.message}")
      rescue PermissionDeniedError => e
        error_result("Permission denied: #{e.message}")
      rescue NotImplementedError => e
        error_result("Not implemented: #{e.message}")
      rescue Error => e
        error_result("Error: #{e.message}")
      rescue StandardError => e
        error_result("Unexpected error in #{tool_name}: #{e.class}: #{e.message}")
      end

      def tool_definitions
        Registry.tool_definitions
      end

      # Patterns that indicate a bash command writes to a file.
      BASH_WRITE_PATTERNS = [
        /(?:>>?)\s*(\S+)/,            # > file  or  >> file
        /\btee\s+(?:-a\s+)?(\S+)/,    # tee file  or  tee -a file
        /\bsed\s+-i\S*\s+.*\s(\S+)$/, # sed -i 's/...' file
        /\bsed\s+-i\S*\s+.*\s(\S+)\s/ # sed -i 's/...' file (mid-command)
      ].freeze

      private

      def build_tool(tool_name)
        tool_class = Registry.get(tool_name)
        tool = tool_class.new(project_root: project_root)
        inject_dependencies(tool, tool_name)
        tool
      end

      def filter_params(tool, params)
        symbolized = params.transform_keys(&:to_sym)
        allowed = tool.method(:execute).parameters
                      .select { |type, _| %i[key keyreq].include?(type) } # rubocop:disable Style/HashSlice
                      .map(&:last)
        allowed.empty? ? symbolized : symbolized.slice(*allowed)
      end

      def inject_dependencies(tool, tool_name) # rubocop:disable Metrics/CyclomaticComplexity -- tool-specific dependency injection
        case tool_name
        when 'spawn_agent', 'spawn_teammate'
          inject_agent_deps(tool)
          tool.db = @db if tool_name == 'spawn_teammate' && tool.respond_to?(:db=)
        when 'background_run'
          tool.background_worker = @background_worker if tool.respond_to?(:background_worker=)
        when 'ask_user'
          tool.prompt_callback = @ask_user_callback if tool.respond_to?(:prompt_callback=)
        end
      end

      def inject_agent_deps(tool)
        tool.llm_client = @llm_client if tool.respond_to?(:llm_client=)
        tool.on_status = @on_agent_status if tool.respond_to?(:on_status=)
      end

      # Serve read_file from cache if the file hasn't changed.
      def try_file_cache(tool_name, params)
        return nil unless tool_name == 'read_file'

        path = resolve_cache_path(params)
        return nil unless path && @file_cache.cached?(path)

        result = @file_cache.read(path)
        result[:content]
      rescue StandardError
        nil
      end

      # Cache read_file results; invalidate on write_file/edit_file.
      # Also detects bash commands that write to files (redirect, sed -i, tee).
      def update_file_cache(tool_name, params, _raw)
        path = resolve_cache_path(params)

        case tool_name
        when 'read_file'
          @file_cache.read(path) if path # populates cache
        when 'write_file', 'edit_file'
          @file_cache.on_write(path) if path
        when 'bash'
          invalidate_bash_write_targets(params)
        end
      rescue StandardError
        nil
      end

      def resolve_cache_path(params)
        p = params[:path] || params['path']
        return nil unless p

        File.expand_path(p, @project_root)
      rescue StandardError
        nil
      end

      # Trigger an incremental codebase index update after writing a Ruby file.
      # Non-blocking: if the update fails, log and continue.
      def maybe_update_codebase_index(tool_name, params)
        return unless %w[write_file edit_file].include?(tool_name)
        return unless @codebase_index

        path = resolve_cache_path(params)
        return unless path&.end_with?('.rb')

        @codebase_index.update!
      rescue StandardError => e
        RubynCode::Debug.warn("CodebaseIndex incremental update failed: #{e.message}")
      end
      
      # Detect file paths that a bash command may have written to and
      # invalidate them from the file cache.
      def invalidate_bash_write_targets(params)
        command = params[:command] || params['command']
        return unless command.is_a?(String)

        paths = extract_bash_write_paths(command)
        paths.each do |p|
          resolved = File.expand_path(p, @project_root)
          @file_cache.on_write(resolved)
        end
      end

      def extract_bash_write_paths(command)
        paths = []
        BASH_WRITE_PATTERNS.each do |pattern|
          command.scan(pattern) { |match| paths << match[0] if match[0] }
        end
        paths.uniq
      end

      def error_result(message)
        message
      end
    end
  end
end
