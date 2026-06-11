# frozen_string_literal: true

module RubynCode
  module Teams
    # Discovery service for active agents in the system.
    #
    # Provides a unified view of all agents (main loop, sub-agents, teammates)
    # with status, lineage, and messaging capabilities.
    class AgentRegistry
      # @param manager [Manager] the teammate manager
      # @param mailbox [Mailbox] the team mailbox
      def initialize(manager:, mailbox:)
        @manager = manager
        @mailbox = mailbox
      end

      # Returns a snapshot of all registered agents with their status
      # and unread message counts.
      #
      # @return [Array<Hash>] agent snapshots
      def snapshot
        @manager.list.map { |t| agent_snapshot(t) }
      end

      # Returns only active agents.
      #
      # @return [Array<Hash>] active agent snapshots
      def active
        @manager.active_teammates.map { |t| agent_snapshot(t) }
      end

      # Returns the full agent tree starting from all root agents.
      #
      # @return [Array<Hash>] nested tree structures
      def forest
        @manager.roots.map { |root| build_display_tree(root) }
      end

      # Returns lineage (ancestors) for a given agent.
      #
      # @param agent_id [String] the agent's ID
      # @return [Array<Teammate>] ordered from root to immediate parent
      def lineage(agent_id)
        ancestors = []
        current = @manager.find_by_id(agent_id)
        return ancestors unless current

        while current&.parent_agent_id
          parent = @manager.find_by_id(current.parent_agent_id)
          break unless parent

          ancestors.unshift(parent)
          current = parent
        end

        ancestors
      end

      # Returns a formatted status report of all agents.
      #
      # @return [String] human-readable status report
      def status_report
        agents = snapshot
        return 'No agents registered.' if agents.empty?

        lines = ['Agent Registry Status:', '']
        agents.each do |agent|
          icon = status_icon(agent[:status])
          parent_info = agent[:parent_agent_id] ? " (child of #{agent[:parent_agent_id][0, 8]})" : ' (root)'
          lines << "  #{icon} #{agent[:name]} [#{agent[:role]}] — #{agent[:status]}#{parent_info}"
          lines << "    Unread: #{agent[:unread_count]}" if agent[:unread_count].positive?
        end
        lines.join("\n")
      end

      private

      # Builds a snapshot hash for a single agent.
      #
      # @param teammate [Teammate]
      # @return [Hash]
      def agent_snapshot(teammate)
        {
          id: teammate.id,
          name: teammate.name,
          role: teammate.role,
          status: teammate.status,
          parent_agent_id: teammate.parent_agent_id,
          unread_count: @mailbox.unread_count(teammate.name),
          created_at: teammate.created_at
        }
      end

      # Recursively builds a display tree with snapshot data.
      #
      # @param agent [Teammate]
      # @return [Hash]
      def build_display_tree(agent)
        children = @manager.children_of(agent.id)
        {
          **agent_snapshot(agent),
          children: children.map { |child| build_display_tree(child) }
        }
      end

      # Returns a status icon for display.
      #
      # @param status [String]
      # @return [String]
      def status_icon(status)
        case status
        when 'active' then '🟢'
        when 'idle'   then '🟡'
        when 'offline' then '⚫'
        else '❓'
        end
      end
    end
  end
end
