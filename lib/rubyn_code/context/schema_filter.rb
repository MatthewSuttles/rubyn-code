# frozen_string_literal: true

module RubynCode
  module Context
    # Extracts only the relevant table definitions from db/schema.rb
    # based on which models are currently in context. Loading the full
    # schema for a large Rails app can be 5-10K tokens; filtering to
    # relevant tables typically reduces this to 200-500 tokens.
    module SchemaFilter
      TABLE_PATTERN = /create_table\s+"([^"]+)"/
      END_PATTERN = /\A\s+end\s*\z/

      class << self
        # Returns schema definitions for only the specified table names.
        #
        # @param schema_path [String] path to db/schema.rb
        # @param table_names [Array<String>] table names to include
        # @return [String] filtered schema content
        def filter(schema_path, table_names:)
          return '' if table_names.empty?
          return '' unless File.exist?(schema_path)

          lines = File.readlines(schema_path)
          extract_tables(lines, table_names.to_set(&:to_s))
        end

        # Derives table names from model class names using Rails conventions.
        #
        # @param model_names [Array<String>] e.g., ["User", "OrderItem"]
        # @return [Array<String>] e.g., ["users", "order_items"]
        def tableize(model_names)
          model_names.map { |name| "#{name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase}s" }
        end

        # Convenience: filter schema by model names instead of table names.
        def filter_for_models(schema_path, model_names:)
          tables = tableize(model_names)
          filter(schema_path, table_names: tables)
        end

        private

        def extract_tables(lines, table_set)
          result = []
          capturing = false

          lines.each do |line|
            match = TABLE_PATTERN.match(line)
            capturing = true if match && table_set.include?(match[1])

            result << line if capturing

            if capturing && END_PATTERN.match?(line)
              capturing = false
              result << "\n"
            end
          end

          result.join
        end
      end
    end
  end
end
