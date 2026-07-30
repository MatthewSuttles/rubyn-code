# frozen_string_literal: true

require 'prism'

module RubynCode
  module Index
    # Prism-based symbol and call extractor for a single Ruby file.
    # Returns classes/modules and methods with real line spans, plus
    # method-to-method call sites the regex pass can't see. Used by
    # CodebaseIndex, with the regex extractors as a parse-error fallback.
    class PrismExtractor < Prism::Visitor
      Result = Struct.new(:classes, :defs, :calls)

      # @return [Result, nil] nil when the file doesn't parse
      def self.extract(content)
        parsed = Prism.parse(content)
        return nil unless parsed.success?

        visitor = new
        visitor.visit(parsed.value)
        Result.new(visitor.classes, visitor.defs, visitor.calls)
      rescue StandardError
        nil
      end

      attr_reader :classes, :defs, :calls

      def initialize
        super
        @namespace = []
        @current_def = nil
        @classes = [] # { name:, kind:, line:, end_line: }
        @defs    = [] # { name:, owner:, line:, end_line:, params: }
        @calls   = [] # { from:, to:, line: }
      end

      def visit_class_node(node)
        record_namespace(node, 'class') { super }
      end

      def visit_module_node(node)
        record_namespace(node, 'module') { super }
      end

      def visit_def_node(node)
        @defs << {
          name: node.name.to_s,
          owner: @namespace.join('::'),
          line: node.location.start_line,
          end_line: node.location.end_line,
          params: node.parameters ? "(#{node.parameters.slice})" : nil
        }
        previous = @current_def
        @current_def = node.name.to_s
        super
        @current_def = previous
      end

      # ponytail: resolution is by method name, not receiver type — a call to
      # `user.save` links to any `save` defined in the project. Real receiver
      # inference needs type analysis; name matching covers the common case.
      def visit_call_node(node)
        @calls << { from: @current_def, to: node.name.to_s, line: node.location.start_line } if @current_def
        super
      end

      private

      # The block continues the walk into child nodes (the caller's `super`).
      def record_namespace(node, kind)
        name = node.constant_path.slice
        @classes << {
          name: name, kind: kind,
          line: node.location.start_line, end_line: node.location.end_line
        }
        @namespace.push(name)
        yield
        @namespace.pop
      end
    end
  end
end
