# frozen_string_literal: true

module RubynCode
  module SubAgents
    # A sub-agent type: the built-in `explore`/`worker`, or a user-defined
    # agent loaded from .rubyn-code/agents/*.md. Captures everything
    # spawn_agent needs to run it — display name, system prompt, the tool
    # allowlist (nil = access-based default), access level, and turn budget.
    AgentType = Data.define(:name, :description, :system_prompt, :tool_names, :access, :max_iterations) do
      # @return [Boolean] read-only agents may only call read-risk tools
      def read_only? = access == :read

      # @return [Boolean]
      def custom? = !%w[explore worker].include?(name)
    end
  end
end
