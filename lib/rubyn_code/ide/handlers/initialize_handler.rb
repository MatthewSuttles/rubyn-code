# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "initialize" JSON-RPC request from the IDE extension.
      #
      # Accepts workspace path, extension metadata, and client capabilities.
      # Sets the working directory and returns server capabilities so the
      # extension knows what features are available.
      class InitializeHandler
        def initialize(server)
          @server = server
        end

        def call(params) # rubocop:disable Metrics/MethodLength -- builds full capability handshake response
          workspace = params['workspacePath']
          extension_version = params['extensionVersion']
          client_caps = params['capabilities'] || {}

          if workspace && Dir.exist?(workspace)
            Dir.chdir(workspace)
            @server.workspace_path = workspace
          end

          @server.extension_version = extension_version
          @server.client_capabilities = client_caps

          tool_count  = tool_count!
          skill_count = skill_count!

          {
            'serverVersion' => RubynCode::VERSION,
            'protocolVersion' => '1.0',
            'workspacePath' => Dir.pwd,
            'capabilities' => {
              'tools' => tool_count,
              'skills' => skill_count,
              'streaming' => true,
              'review' => true,
              'memory' => true,
              'teams' => true,
              'toolApproval' => true,
              'editApproval' => true
            }
          }
        end

        private

        def tool_count!
          Tools::Registry.load_all!
          Tools::Registry.tool_names.size
        rescue StandardError
          0
        end

        def skill_count!
          dirs = default_skill_dirs
          catalog = Skills::Catalog.new(dirs)
          catalog.available.size
        rescue StandardError
          0
        end

        def default_skill_dirs
          dirs = [File.expand_path('../../../../skills', __dir__)]
          if @server.workspace_path
            project_skills = File.join(@server.workspace_path, '.rubyn-code', 'skills')
            dirs << project_skills if Dir.exist?(project_skills)
          end
          user_skills = File.join(Config::Defaults::HOME_DIR, 'skills')
          dirs << user_skills if Dir.exist?(user_skills)
          dirs
        end
      end
    end
  end
end
