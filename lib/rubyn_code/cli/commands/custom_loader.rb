# frozen_string_literal: true

require 'yaml'

module RubynCode
  module CLI
    module Commands
      # Discovers user-defined slash commands from markdown files, mirroring
      # Claude Code's `.claude/commands/*.md`:
      #
      #   <project>/.rubyn-code/commands/*.md   (project-local, takes priority)
      #   ~/.rubyn-code/commands/*.md           (user-global)
      #
      # Each `deploy.md` becomes `/deploy`. Optional YAML frontmatter supplies
      # the `description`; otherwise the first non-empty line is used. The body
      # is the prompt template (see CommandTemplate for substitutions).
      module CustomLoader
        FRONTMATTER = /\A---\s*\n(.+?\n)---\s*\n(.*)\z/m
        NAME = /\A[a-z0-9][a-z0-9_-]*\z/i

        class << self
          # @return [Array<CustomCommand>] unique commands (project overrides user)
          def load_all(project_root:, home_dir: Config::Defaults::HOME_DIR)
            dirs = [
              project_root && File.join(project_root, '.rubyn-code', 'commands'),
              File.join(home_dir, 'commands')
            ].compact
            dirs.flat_map { |dir| load_dir(dir) }.uniq(&:command_name)
          end

          def load_dir(dir)
            return [] unless Dir.exist?(dir)

            Dir.glob(File.join(dir, '*.md')).filter_map { |path| build(path) }
          end

          private

          def build(path)
            name = File.basename(path, '.md').strip
            return nil unless name.match?(NAME)

            meta, body = parse(File.read(path))
            description = meta['description'].to_s
            description = "Custom command: /#{name}" if description.strip.empty?
            CustomCommand.new(
              name: name,
              description: description,
              body: body,
              source: path,
              argument_hint: blank_to_nil(stringify(meta['argument_hint'] || meta['argument-hint'])),
              allowed_tools: list_of_tools(meta['allowed_tools'] || meta['allowed-tools']),
              model: blank_to_nil(stringify(meta['model']))
            )
          rescue StandardError => e
            RubynCode::Debug.warn("Failed to load custom command #{path}: #{e.message}")
            nil
          end

          def parse(content)
            if (match = FRONTMATTER.match(content))
              frontmatter = YAML.safe_load(match[1]) || {}
              [frontmatter, match[2].to_s.strip]
            else
              body = content.to_s.strip
              [{ 'description' => first_line(body) }, body]
            end
          end

          def blank_to_nil(value)
            value.to_s.strip.empty? ? nil : value
          end

          def stringify(value)
            return '' if value.nil?

            # YAML's flow-style `[env]` is parsed as a single-element array.
            # Stringify the array element directly so users see exactly the
            # characters they typed.
            str = value.is_a?(Array) ? value.join : value
            str.to_s.strip
          end

          def list_of_tools(value)
            return nil if value.nil?

            arr = value.is_a?(Array) ? value : value.to_s.split(',')
            cleaned = arr.map { |name| name.to_s.strip }.reject(&:empty?)
            cleaned.empty? ? nil : cleaned
          end

          def first_line(body)
            line = body.lines.first.to_s.strip
            line.sub(/\A#+\s*/, '')[0, 80]
          end
        end
      end
    end
  end
end
