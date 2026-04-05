# frozen_string_literal: true

module RubynCode
  module Agent
    # Manages background job polling, waiting, and notification draining
    # for the agent loop.
    module BackgroundJobHandler
      private

      def wait_for_background_jobs
        max_wait = 300 # 5 minutes max
        poll_interval = 3

        RubynCode::Debug.agent(
          'Waiting for background jobs to finish ' \
          "(polling every #{poll_interval}s, max #{max_wait}s)"
        )

        elapsed = poll_until_done(max_wait, poll_interval)
        drain_background_notifications
        RubynCode::Debug.agent("Background wait done (#{elapsed}s)")
      end

      def poll_until_done(max_wait, poll_interval)
        elapsed = 0
        while elapsed < max_wait && pending_background_jobs?
          sleep poll_interval
          elapsed += poll_interval
          drain_background_notifications
        end
        elapsed
      end

      def drain_background_notifications
        return unless @background_manager

        notifications = @background_manager.drain_notifications
        return if notifications.nil? || notifications.empty?

        summary = notifications.map { |n| format_background_notification(n) }.join("\n\n")
        @conversation.add_user_message("[Background job results]\n#{summary}")
      rescue NoMethodError
        # background_manager does not support drain_notifications yet
      end

      def pending_background_jobs?
        return false unless @background_manager

        @background_manager.active_count.positive?
      rescue NoMethodError
        false
      end

      def format_background_notification(notification)
        return notification.to_s unless notification.is_a?(Hash)

        status   = notification[:status] || 'unknown'
        job_id   = notification[:job_id]&.[](0..7) || 'unknown'
        duration = format_duration(notification[:duration])
        result   = notification[:result] || '(no output)'
        "Job #{job_id} [#{status}] (#{duration}):\n#{result}"
      end

      def format_duration(dur)
        return 'unknown' unless dur

        format('%.1fs', dur)
      end
    end
  end
end
