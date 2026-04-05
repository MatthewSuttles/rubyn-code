# frozen_string_literal: true

module RubynCode
  module Tools
    class Executor
      attr_reader :project_root
      attr_accessor :llm_client, :background_worker, :on_agent_status, :db, :ask_user_callback

      def initialize(project_root:)
        @project_root = File.expand_path(project_root)
        @injections = {}
        Registry.load_all!
      end

      def execute(tool_name, params) # rubocop:disable Metrics/AbcSize -- maps tool errors to results
        tool = build_tool(tool_name)
        filtered = filter_params(tool, params)
        tool.truncate(tool.execute(**filtered).to_s)
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

      def error_result(message)
        message
      end
    end
  end
end
