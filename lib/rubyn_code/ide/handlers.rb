# frozen_string_literal: true

require_relative 'handlers/initialize_handler'
require_relative 'handlers/prompt_handler'
require_relative 'handlers/cancel_handler'
require_relative 'handlers/review_handler'
require_relative 'handlers/approve_tool_use_handler'
require_relative 'handlers/accept_edit_handler'
require_relative 'handlers/shutdown_handler'
require_relative 'handlers/config_get_handler'
require_relative 'handlers/config_set_handler'
require_relative 'handlers/models_list_handler'
require_relative 'handlers/session_reset_handler'
require_relative 'handlers/session_list_handler'
require_relative 'handlers/session_resume_handler'
require_relative 'handlers/session_fork_handler'

module RubynCode
  module IDE
    module Handlers
      # Method name => Handler class mapping.
      REGISTRY = {
        'initialize' => InitializeHandler,
        'prompt' => PromptHandler,
        'cancel' => CancelHandler,
        'review' => ReviewHandler,
        'approveToolUse' => ApproveToolUseHandler,
        'acceptEdit' => AcceptEditHandler,
        'shutdown' => ShutdownHandler,
        'config/get' => ConfigGetHandler,
        'config/set' => ConfigSetHandler,
        'models/list' => ModelsListHandler,
        'session/reset' => SessionResetHandler,
        'session/list' => SessionListHandler,
        'session/resume' => SessionResumeHandler,
        'session/fork' => SessionForkHandler
      }.freeze

      # Short name => method name mapping (for handler_instance lookups).
      SHORT_NAMES = {
        prompt: 'prompt',
        cancel: 'cancel',
        review: 'review',
        approve_tool_use: 'approveToolUse',
        accept_edit: 'acceptEdit',
        shutdown: 'shutdown',
        initialize: 'initialize',
        config_get: 'config/get',
        config_set: 'config/set',
        models_list: 'models/list',
        session_reset: 'session/reset',
        session_list: 'session/list',
        session_resume: 'session/resume',
        session_fork: 'session/fork'
      }.freeze

      # Register all handlers on the given server instance.
      #
      # @param server [RubynCode::IDE::Server] the IDE server
      def self.register_all(server)
        instances = {}

        REGISTRY.each do |method, handler_class|
          handler = handler_class.new(server)
          instances[method] = handler

          server.on(method) do |params, _id|
            handler.call(params)
          end
        end

        server.handler_instances = instances
      end
    end
  end
end
