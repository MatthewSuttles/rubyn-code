# frozen_string_literal: true

require 'yaml'

module RubynCode
  module SubAgents
    # Resolves sub-agent types by name. Ships the built-in `explore` and
    # `worker` agents and discovers user-defined ones from markdown files,
    # mirroring Claude Code's `.claude/agents/*.md`:
    #
    #   <project>/.rubyn-code/agents/*.md   (project-local, takes priority)
    #   ~/.rubyn-code/agents/*.md           (user-global)
    #
    # Frontmatter (all optional except a sensible default name):
    #   name: reviewer
    #   description: Reviews a diff for bugs
    #   tools: read_file, grep, glob, bash   # omit → access-based default set
    #   access: read                         # read | write (default: write)
    # The markdown body becomes the agent's system prompt.
    class Catalog
      FRONTMATTER = /\A---\s*\n(.+?\n)---\s*\n(.*)\z/m
      NAME = /\A[a-z0-9][a-z0-9_-]*\z/i

      BASE_PROMPT = 'You are a Rubyn sub-agent. Complete your task efficiently and ' \
                    'return a clear summary of what you found or did.'
      EXPLORE_PROMPT = "#{BASE_PROMPT}\nYou have read-only access. Search, read files, and analyze. " \
                       'Do NOT attempt to write or modify anything.'.freeze
      WORKER_PROMPT = "#{BASE_PROMPT}\nYou have full read/write access. Make the changes needed, " \
                      'run tests if appropriate, and report what you did.'.freeze

      def initialize(project_root: nil, home_dir: Config::Defaults::HOME_DIR)
        @project_root = project_root
        @home_dir = home_dir
        @custom = load_custom
      end

      # @param name [String, Symbol]
      # @return [AgentType, nil]
      def get(name)
        key = name.to_s
        builtin[key] || @custom[key]
      end

      # @return [Array<AgentType>] all known agents (built-ins first)
      def all
        builtin.values + @custom.values
      end

      # @return [Array<String>]
      def custom_names = @custom.keys

      private

      def builtin
        {
          'explore' => AgentType.new(
            name: 'explore', description: 'Read-only research/reading agent',
            system_prompt: EXPLORE_PROMPT, tool_names: nil, access: :read,
            max_iterations: Config::Defaults::MAX_EXPLORE_AGENT_ITERATIONS
          ),
          'worker' => AgentType.new(
            name: 'worker', description: 'Full read/write coding agent',
            system_prompt: WORKER_PROMPT, tool_names: nil, access: :write,
            max_iterations: Config::Defaults::MAX_SUB_AGENT_ITERATIONS
          )
        }
      end

      def load_custom
        dirs = [
          @project_root && File.join(@project_root, '.rubyn-code', 'agents'),
          File.join(@home_dir, 'agents')
        ].compact

        dirs.flat_map { |dir| load_dir(dir) }
            .each_with_object({}) { |agent, acc| acc[agent.name] ||= agent }
      end

      def load_dir(dir)
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, '*.md')).filter_map { |path| build(path) }
      end

      def build(path)
        frontmatter, body = parse(File.read(path))
        name = (frontmatter['name'] || File.basename(path, '.md')).to_s.strip
        return nil unless name.match?(NAME) && !builtin.key?(name)

        access = frontmatter['access'].to_s.downcase == 'read' ? :read : :write
        desc = frontmatter['description'].to_s
        AgentType.new(
          name: name,
          description: desc.empty? ? "Custom agent: #{name}" : desc,
          system_prompt: body.empty? ? BASE_PROMPT : body,
          tool_names: parse_tools(frontmatter['tools']),
          access: access,
          max_iterations: default_iterations(access)
        )
      rescue StandardError => e
        RubynCode::Debug.warn("Failed to load custom agent #{path}: #{e.message}")
        nil
      end

      def parse(content)
        match = FRONTMATTER.match(content)
        return [{}, content.to_s.strip] unless match

        [YAML.safe_load(match[1]) || {}, match[2].to_s.strip]
      end

      def parse_tools(value)
        case value
        when Array then value.map(&:to_s)
        when String then value.split(/[,\s]+/).reject(&:empty?)
        end
      end

      def default_iterations(access)
        access == :read ? Config::Defaults::MAX_EXPLORE_AGENT_ITERATIONS : Config::Defaults::MAX_SUB_AGENT_ITERATIONS
      end
    end
  end
end
