# frozen_string_literal: true

module RubynCode
  module Skills
    # Parses Gemfiles to extract gem names for skill pack matching.
    # Handles standard gem declarations and grouped gems.
    #
    # Recognized patterns:
    #   gem 'stripe'
    #   gem 'stripe', '~> 8.0'
    #   gem 'pundit', require: false
    #   gem 'sidekiq', '>= 6.0', group: :workers
    #
    # Does NOT match comments or source declarations.
    class GemfileParser
      GEM_PATTERN = /
        ^\s*gem\s+
        ['"]([^'"]+)['"]
      /x

      # Extract unique gem names from Gemfile content.
      #
      # @param content [String] raw Gemfile content
      # @return [Array<String>] gem names (lowercase)
      def self.gems(content)
        new(content).gems
      end

      def initialize(content)
        @content = content
      end

      def gems
        return [] if @content.to_s.strip.empty?

        @content.scan(GEM_PATTERN).flatten.map { |m| m.strip.downcase }.uniq
      end
    end
  end
end
