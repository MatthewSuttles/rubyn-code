# frozen_string_literal: true

require 'json'
require 'json_schemer'

module RubynCode
  module Config
    class Validator
      SCHEMA_PATH = File.expand_path('schema.json', __dir__)

      def initialize
        @raw_schema = JSON.parse(File.read(SCHEMA_PATH))
        @schemer = JSONSchemer.schema(@raw_schema)
      end

      # Validates a single config key/value pair against the schema.
      #
      # @param key [String] the config key
      # @param value [Object] the value to validate
      # @return [Hash] { valid: true/false, errors: [String] }
      def validate(key, value)
        # If the key has no schema definition, accept any value
        properties = @raw_schema.fetch('properties', {})
        unless properties.key?(key.to_s)
          return { valid: true, errors: [] }
        end

        doc = { key.to_s => value }
        errors = @schemer.validate(doc).select { |e| e['data_pointer'] == "/#{key}" }

        if errors.empty?
          { valid: true, errors: [] }
        else
          messages = errors.map { |e| format_error(key, e) }
          { valid: false, errors: messages }
        end
      end

      private

      def format_error(key, error)
        detail = error['type']
        schema_node = error.fetch('schema', {})

        parts = ["#{key}: invalid value"]
        parts << "(expected #{detail})" if detail

        if schema_node.key?('minimum') || schema_node.key?('maximum')
          range_parts = []
          range_parts << "min #{schema_node['minimum']}" if schema_node.key?('minimum')
          range_parts << "max #{schema_node['maximum']}" if schema_node.key?('maximum')
          parts << "[#{range_parts.join(', ')}]"
        end

        if schema_node.key?('enum')
          parts << "allowed: #{schema_node['enum'].join(', ')}"
        end

        parts.join(' ')
      end
    end
  end
end
