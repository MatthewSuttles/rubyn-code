# frozen_string_literal: true

module RubynCode
  module Permissions
    class DenyList
      attr_reader :names, :prefixes

      # @param names [Array<String>] exact tool names to deny
      # @param prefixes [Array<String>] tool name prefixes to deny
      def initialize(names: [], prefixes: [])
        @names    = Set.new(names.map(&:to_s))
        @prefixes = Set.new(prefixes.map(&:to_s))
      end

      # Returns true if the given tool name is blocked by an exact name match
      # or by a prefix match.
      #
      # @param tool_name [String]
      # @return [Boolean]
      def blocks?(tool_name)
        name = tool_name.to_s
        return true if @names.include?(name)

        @prefixes.any? { |prefix| name.start_with?(prefix) }
      end

      # @param name [String] exact tool name to add to the deny list
      # @return [self]
      def add_name(name)
        @names.add(name.to_s)
        self
      end

      # @param prefix [String] tool name prefix to add to the deny list
      # @return [self]
      def add_prefix(prefix)
        @prefixes.add(prefix.to_s)
        self
      end

      # @param name [String] exact tool name to remove from the deny list
      # @return [self]
      def remove_name(name)
        @names.delete(name.to_s)
        self
      end
    end
  end
end
