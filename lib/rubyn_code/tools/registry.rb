# frozen_string_literal: true

module RubynCode
  module Tools
    module Registry
      @tools = {}

      class << self
        def register(tool_class)
          name = tool_class.tool_name
          @tools[name] = tool_class
        end

        def get(name)
          @tools.fetch(name) do
            raise ToolNotFoundError, "Unknown tool: #{name}. Available: #{tool_names.join(', ')}"
          end
        end

        def all
          @tools.values
        end

        def tool_definitions
          @tools.values.map(&:to_schema)
        end

        def tool_names
          @tools.keys.sort
        end

        def reset!
          @tools = {}
        end

        def load_all!
          tool_files = Dir[File.join(__dir__, '*.rb')]
          tool_files.each do |file|
            basename = File.basename(file, '.rb')
            next if %w[base registry schema executor].include?(basename)

            require_relative basename
          end
        end
      end
    end
  end
end
