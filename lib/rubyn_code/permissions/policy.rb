# frozen_string_literal: true

module RubynCode
  module Permissions
    module Policy
      # Determine whether a tool invocation should be allowed, denied, or
      # requires user confirmation.
      #
      # @param tool_name [String]
      # @param tool_input [Hash]
      # @param tier [Symbol] one of Tier::ALL
      # @param deny_list [DenyList]
      # @return [Symbol] :allow, :deny, or :ask
      # Tool calls that are always auto-approved regardless of permission tier
      ALWAYS_ALLOW = %w[
        read_file glob grep git_status git_diff git_log
        memory_search memory_write load_skill compact
        task web_search web_fetch ask_user
      ].to_set.freeze

      def self.check(tool_name:, tool_input:, tier:, deny_list:)
        return :deny if deny_list.blocks?(tool_name)
        return :allow if ALWAYS_ALLOW.include?(tool_name)

        risk = resolve_risk(tool_name)

        return :ask if risk == :destructive

        case tier
        when Tier::ASK_ALWAYS
          :ask
        when Tier::ALLOW_READ
          risk == :read ? :allow : :ask
        when Tier::AUTONOMOUS
          risk == :external ? :ask : :allow
        when Tier::UNRESTRICTED
          :allow
        else
          :ask
        end
      end

      # Resolve the risk level for a tool by looking it up in the registry.
      # Falls back to :unknown if the tool class cannot be found, which will
      # be treated conservatively (requires confirmation in most tiers).
      #
      # @param tool_name [String]
      # @return [Symbol] :read, :write, :external, :destructive, or :unknown
      def self.resolve_risk(tool_name)
        tool_class = Tools::Registry.get(tool_name)
        tool_class.risk_level
      rescue ToolNotFoundError
        :unknown
      end

      private_class_method :resolve_risk
    end
  end
end
