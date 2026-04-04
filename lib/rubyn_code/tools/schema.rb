# frozen_string_literal: true

module RubynCode
  module Tools
    module Schema
      TYPE_MAP = {
        string: 'string',
        integer: 'integer',
        number: 'number',
        boolean: 'boolean',
        array: 'array',
        object: 'object'
      }.freeze

      class << self
        def build(params_hash)
          return { type: 'object', properties: {}, required: [] } if params_hash.empty?

          properties = {}
          required = []

          params_hash.each do |name, spec|
            name_str = name.to_s
            prop = build_property(spec)
            properties[name_str] = prop

            required << name_str if spec[:required]
          end

          schema = {
            type: 'object',
            properties: properties
          }
          schema[:required] = required unless required.empty?
          schema
        end

        private

        def build_property(spec)
          prop = {}

          type = spec[:type] || :string
          prop[:type] = TYPE_MAP.fetch(type, type.to_s)

          prop[:description] = spec[:description] if spec[:description]
          prop[:default] = spec[:default] if spec.key?(:default)
          prop[:enum] = spec[:enum] if spec[:enum]

          prop[:items] = build_property(spec[:items]) if spec[:items]

          prop
        end
      end
    end
  end
end
