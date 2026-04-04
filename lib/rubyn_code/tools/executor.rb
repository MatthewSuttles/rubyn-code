# frozen_string_literal: true

module RubynCode
  module Tools
    class Executor
      attr_reader :project_root
      attr_accessor :llm_client, :background_worker, :on_agent_status, :db

      def initialize(project_root:)
        @project_root = File.expand_path(project_root)
        @injections = {}
        Registry.load_all!
      end

      def execute(tool_name, params)
        tool_class = Registry.get(tool_name)
        tool = tool_class.new(project_root: project_root)

        # Inject dependencies for tools that need them
        inject_dependencies(tool, tool_name)

        symbolized = params.transform_keys(&:to_sym)
        # Filter to only params the tool's execute method accepts — LLM may send extra keys
        allowed = tool.method(:execute).parameters
                      .select { |type, _| type == :key || type == :keyreq }
                      .map(&:last)
        filtered = allowed.empty? ? symbolized : symbolized.slice(*allowed)
        result = tool.execute(**filtered)
        tool.truncate(result.to_s)
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

      def inject_dependencies(tool, tool_name)
        case tool_name
        when "spawn_agent"
          tool.llm_client = @llm_client if tool.respond_to?(:llm_client=)
          tool.on_status = @on_agent_status if tool.respond_to?(:on_status=)
        when "spawn_teammate"
          tool.llm_client = @llm_client if tool.respond_to?(:llm_client=)
          tool.on_status = @on_agent_status if tool.respond_to?(:on_status=)
          tool.db = @db if tool.respond_to?(:db=)
        when "background_run"
          tool.background_worker = @background_worker if tool.respond_to?(:background_worker=)
        end
      end

      def error_result(message)
        message
      end
    end
  end
end
