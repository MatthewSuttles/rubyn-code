# frozen_string_literal: true

require "yaml"

module RubynCode
  module Hooks
    class UserHooks
      # Load hooks from YAML config files.
      #
      # Format:
      # pre_tool_use:
      #   - tool: bash
      #     match: "rm -rf"
      #     action: deny
      #     reason: "Destructive delete blocked"
      #   - tool: write_file
      #     path: "db/migrate/**"
      #     action: deny
      #     reason: "Use rails generate migration"
      # post_tool_use:
      #   - tool: write_file
      #     action: log
      #
      # @param registry [Hooks::Registry]
      # @param project_root [String] the project root directory
      # @return [void]
      def self.load!(registry, project_root:)
        paths = [
          File.join(project_root, ".rubyn-code", "hooks.yml"),
          File.join(Config::Defaults::HOME_DIR, "hooks.yml")
        ]

        paths.each do |path|
          next unless File.exist?(path)

          config = YAML.safe_load_file(path) || {}
          register_hooks(registry, config)
        end
      end

      class << self
        private

        def register_hooks(registry, config)
          register_pre_tool_use_hooks(registry, config["pre_tool_use"] || [])
          register_post_tool_use_hooks(registry, config["post_tool_use"] || [])
        end

        def register_pre_tool_use_hooks(registry, hook_configs)
          hook_configs.each do |hook_config|
            registry.on(:pre_tool_use) do |tool_name:, tool_input:, **|
              next unless matches?(hook_config, tool_name, tool_input)

              case hook_config["action"]
              when "deny"
                { deny: true, reason: hook_config["reason"] || "Blocked by hooks.yml" }
              end
            end
          end
        end

        def register_post_tool_use_hooks(registry, hook_configs)
          hook_configs.each do |hook_config|
            registry.on(:post_tool_use) do |tool_name:, result:, **|
              next result unless hook_config["tool"].nil? || hook_config["tool"] == tool_name

              if hook_config["action"] == "log"
                log_dir = ".rubyn-code"
                FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
                File.open(File.join(log_dir, "audit.log"), "a") do |f|
                  f.puts "[#{Time.now}] #{tool_name}: #{result.to_s[0..200]}"
                end
              end

              result
            end
          end
        end

        def matches?(config, tool_name, params)
          return false if config["tool"] && config["tool"] != tool_name
          return false if config["match"] && !params.to_s.include?(config["match"])
          return false if config["path"] && !File.fnmatch?(config["path"], params[:path].to_s)

          true
        end
      end
    end
  end
end
