# frozen_string_literal: true

module RubynCode
  module Rules
    # Registry for rule classes. Each rule subclass registers itself after
    # definition, mirroring the pattern used by RubynCode::Tools::Registry.
    #
    # Usage:
    #   RubynCode::Rules::Registry.register(MyRule)
    #   RubynCode::Rules::Registry.all  # => [MyRule, ...]
    module Registry
      @rules = {}

      class << self
        # Register a rule class by its ID constant.
        #
        # @param rule_class [Class] a subclass of RubynCode::Rules::Base
        def register(rule_class)
          id = rule_class.id
          @rules[id] = rule_class
        end

        # Return all registered rule classes.
        #
        # @return [Array<Class>]
        def all
          @rules.values
        end

        # Look up a rule by ID.
        #
        # @param id [String]
        # @return [Class]
        def get(id)
          @rules.fetch(id) do
            raise KeyError, "Unknown rule: #{id}. Available: #{rule_ids.join(', ')}"
          end
        end

        # Return all registered rule IDs, sorted.
        #
        # @return [Array<String>]
        def rule_ids
          @rules.keys.sort
        end

        # Clear all registered rules. Used in tests.
        def reset!
          @rules = {}
        end

        # Auto-load all rule files under lib/rubyn_code/rules/**/*.rb,
        # skipping base.rb and registry.rb.
        def load_all!
          rule_files = Dir[File.join(__dir__, '**', '*.rb')]
          rule_files.each do |file|
            basename = File.basename(file, '.rb')
            next if %w[base registry].include?(basename)

            require file
          end
        end
      end
    end
  end
end
