# frozen_string_literal: true

module RubynCode
  module SubAgents
    class Runner
      AGENT_TOOL_SETS = {
        explore: %w[read_file glob grep bash].freeze,
        general: nil # resolved at runtime to exclude sub-agent tools
      }.freeze

      SUB_AGENT_TOOLS = %w[sub_agent spawn_agent].freeze
      MAX_ITERATIONS_HARD_LIMIT = 50

      class << self
        def call(prompt:, llm_client:, project_root:, agent_type: :explore, max_iterations: 30)
          new(
            prompt: prompt,
            llm_client: llm_client,
            project_root: project_root,
            agent_type: agent_type,
            max_iterations: max_iterations
          ).run
        end
      end

      def initialize(prompt:, llm_client:, project_root:, agent_type:, max_iterations:)
        @prompt = prompt
        @llm_client = llm_client
        @project_root = File.expand_path(project_root)
        @agent_type = agent_type.to_sym
        @max_iterations = [max_iterations.to_i, MAX_ITERATIONS_HARD_LIMIT].min
      end

      def run
        conversation = build_conversation
        executor = build_executor
        tool_defs = build_tool_definitions

        iteration = 0
        final_text = ''

        loop do
          break if iteration >= @max_iterations

          response = request_llm(conversation, tool_defs)
          iteration += 1

          text_content = extract_text(response)
          tool_calls = extract_tool_calls(response)

          if tool_calls.empty?
            final_text = text_content
            break
          end

          conversation << { role: 'assistant', content: response }

          tool_results = execute_tools(executor, tool_calls)
          conversation << { role: 'user', content: tool_results }

          final_text = text_content unless text_content.empty?
        end

        Summarizer.call(final_text)
      end

      private

      def build_conversation
        [
          { role: 'user', content: @prompt }
        ]
      end

      def build_executor
        Tools::Executor.new(project_root: @project_root)
      end

      def build_tool_definitions
        allowed = allowed_tool_names
        Tools::Registry.all
                       .select { |t| allowed.include?(t.tool_name) }
                       .map(&:to_schema)
      end

      def allowed_tool_names
        preset = AGENT_TOOL_SETS[@agent_type]

        if preset
          # Only include tools that are actually registered
          registered = Tools::Registry.tool_names
          preset & registered
        else
          # :general — all registered tools minus sub-agent spawning tools
          Tools::Registry.tool_names - SUB_AGENT_TOOLS
        end
      end

      def request_llm(conversation, tool_defs)
        @llm_client.chat(
          messages: conversation,
          tools: tool_defs
        )
      end

      def extract_text(response)
        case response
        when String
          response
        when Hash
          content = response[:content] || response['content']
          extract_text_from_content(content)
        when Array
          extract_text_from_content(response)
        else
          response.to_s
        end
      end

      def extract_text_from_content(content)
        return content.to_s unless content.is_a?(Array)

        content
          .select { |block| block_type(block) == 'text' }
          .map { |block| block[:text] || block['text'] }
          .compact
          .join("\n")
      end

      def extract_tool_calls(response)
        content = case response
                  when Hash then response[:content] || response['content']
                  when Array then response
                  else return []
                  end

        return [] unless content.is_a?(Array)

        content.select { |block| block_type(block) == 'tool_use' }
      end

      def block_type(block)
        (block[:type] || block['type']).to_s
      end

      def execute_tools(executor, tool_calls)
        tool_calls.map do |call|
          tool_name = call[:name] || call['name']
          tool_input = call[:input] || call['input'] || {}
          tool_id = call[:id] || call['id']

          # Prevent recursive sub-agent spawning
          result = if SUB_AGENT_TOOLS.include?(tool_name)
                     'Error: Sub-agents cannot spawn other sub-agents.'
                   else
                     executor.execute(tool_name, tool_input)
                   end

          {
            type: 'tool_result',
            tool_use_id: tool_id,
            content: result.to_s
          }
        end
      end
    end
  end
end
