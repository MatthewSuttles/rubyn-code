# frozen_string_literal: true

module RubynCode
  module Tools
    # Shared, thread-safe checklist store. The Agent::Loop owns one instance and
    # exposes it to (a) the renderer so the user sees what's in flight, and
    # (b) the TodoWrite tool so the model can mutate it.
    class TodoStore
      include MonitorMixin

      Item = Data.define(:content, :status, :active_form)

      def initialize
        super
        @items = []
      end

      def replace(items)
        synchronize do
          @items = items.map do |item|
            Item.new(
              content: item['content'] || item[:content],
              status: item['status'] || item[:status],
              active_form: (item['active_form'] || item[:active_form]).to_s
            )
          end
        end
      end

      def current
        synchronize { @items.map(&:to_h) }
      end

      def clear
        synchronize { @items = [] }
      end

      def empty?
        current.empty?
      end

      def render
        current.map do |item|
          mark =
            case item[:status]
            when 'completed' then '☑'
            when 'in_progress' then '[~]'
            else '[ ]'
            end
          "#{mark} #{item[:content]}"
        end.join("\n")
      end
    end
  end
end
