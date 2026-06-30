# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # A slash command defined by a user markdown file (loaded by
      # CustomLoader). Unlike the built-in commands — which are registered as
      # classes — this is a ready instance: the Registry dispatches it directly.
      #
      # Executing it renders the template (argument / bash substitution) and
      # sends the result to the agent as a normal prompt.
      class CustomCommand
        # @return [String] command name without the leading slash
        attr_reader :name
        # @return [String] one-line description for /help
        attr_reader :description
        # @return [String, nil] argument hint shown next to the name in /help
        attr_reader :argument_hint
        # @return [Array<String>, nil] tool names the command restricts to
        attr_reader :allowed_tools
        # @return [String, nil] model override for this prompt
        attr_reader :model
        # @return [String, nil] originating file path
        attr_reader :source

        def initialize(name:, description:, body:, # rubocop:disable Metrics/ParameterLists -- explicit kwargs document the frontmatter surface
                       source: nil,
                       argument_hint: nil, allowed_tools: nil, model: nil)
          @name = name
          @description = description
          @template = CommandTemplate.new(body)
          @argument_hint = argument_hint
          @allowed_tools = allowed_tools
          @model = model
          @source = source
        end

        def command_name = "/#{@name}"
        def aliases = [].freeze
        def hidden? = false
        def all_names = [command_name].freeze

        # Render the help label, including [hint] when frontmatter provides one.
        # The argument_hint is expected to be the placeholder text already wrapped
        # in [ ] (e.g. "[env]") — we don't add another set of brackets.
        def help_label
          hint = @argument_hint.to_s.strip
          hint.empty? ? description : "#{description}  #{hint}"
        end

        # @return [Boolean] true if the frontmatter restricted the tool set
        def restricts_tools?
          !@allowed_tools.nil? && !@allowed_tools.empty?
        end

        # @return [Boolean] true if the frontmatter overrode the model
        def overrides_model?
          !@model.to_s.strip.empty?
        end

        # @param args [Array<String>]
        # @param ctx [Commands::Context]
        # @return [nil]
        def execute(args, ctx)
          rendered = @template.render(args)
          if restricts_tools?
            ctx.with_allowed_tools(@allowed_tools) do
              ctx.with_optional_model(@model) do
                ctx.send_message(rendered)
              end
            end
          elsif overrides_model?
            ctx.with_optional_model(@model) do
              ctx.send_message(rendered)
            end
          else
            ctx.send_message(rendered)
          end
          nil
        end
      end
    end
  end
end
