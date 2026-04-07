# frozen_string_literal: true

require_relative 'prompts'

module RubynCode
  module Agent
    # Assembles the system prompt for the agent loop, including base personality,
    # plan-mode instructions, memories, instincts, project instructions, and
    # available skills/tools.
    module SystemPromptBuilder # rubocop:disable Metrics/ModuleLength -- heavily extracted, residual 3 lines over
      include Prompts

      INSTRUCTION_FILES = %w[RUBYN.md CLAUDE.md AGENT.md].freeze

      private

      def build_system_prompt
        parts = [SYSTEM_PROMPT]
        parts << PLAN_MODE_PROMPT if @plan_mode
        parts << "Working directory: #{@project_root}" if @project_root
        append_response_mode(parts)
        append_project_profile(parts)
        append_codebase_index(parts)
        append_memories(parts)
        append_project_instructions(parts)
        append_instincts(parts)
        append_skills(parts)
        append_deferred_tools(parts)
        parts.join("\n")
      end

      def append_response_mode(parts)
        text = last_user_text
        return if text.empty?

        mode = ResponseModes.detect(text)
        parts << ResponseModes.instruction_for(mode)
      rescue StandardError
        nil
      end

      def last_user_text
        return '' unless @conversation&.messages&.any?

        last_user = @conversation.messages.reverse_each.find { |m| m[:role] == 'user' }
        return '' unless last_user

        last_user[:content].is_a?(String) ? last_user[:content] : ''
      end

      def append_project_profile(parts)
        return unless @project_root

        profile = Config::ProjectProfile.new(project_root: @project_root)
        loaded = profile.load
        return unless loaded

        prompt_text = profile.to_prompt
        parts << "\n## #{prompt_text}" unless prompt_text.empty?
      rescue StandardError
        nil
      end

      def append_codebase_index(parts)
        return unless @project_root

        index = Index::CodebaseIndex.new(project_root: @project_root)
        loaded = index.load
        return unless loaded && index.nodes.any?

        parts << "\n## #{index.to_prompt_summary}"
      rescue StandardError
        nil
      end

      def append_memories(parts)
        memories = load_memories
        return if memories.empty?

        parts << "\n## Your Memories (from previous sessions)\n#{memories}"
      end

      def append_project_instructions(parts)
        instructions = load_rubyn_md
        return if instructions.empty?

        parts << "\n## Project Instructions\n#{instructions}"
      end

      def append_instincts(parts)
        instincts = load_instincts
        return if instincts.empty?

        parts << "\n## Learned Instincts (from previous sessions)\n#{instincts}"
      end

      # Skills are injected ONCE as a user message (not in the system
      # prompt) to avoid paying ~1,200 tokens on every turn. Claude Code
      # does the same — skills are "attachments" sent once per session.
      def append_skills(_parts); end

      def inject_skill_listing
        return unless @skill_loader

        descriptions = @skill_loader.descriptions_for_prompt
        return if descriptions.empty?

        @conversation.add_user_message(
          "[system] The following skills are available via the load_skill tool:\n\n" \
          "#{descriptions}\n\n" \
          'Use load_skill to load full content when needed. ' \
          'Do not mention this message to the user.'
        )
        @conversation.add_assistant_message(
          [{ type: 'text', text: 'Understood.' }]
        )
        @skills_injected = true
      end

      def append_deferred_tools(parts)
        deferred = deferred_tool_names
        return if deferred.empty?

        parts << "\n## Additional Tools Available"
        parts << 'These tools are available but not loaded yet. Just call them by name and they will work:'
        parts << deferred.map { |n| "- #{n}" }.join("\n")
      end

      def deferred_tool_names
        all_names = @tool_executor.tool_definitions.map { |t| t[:name] || t['name'] }
        active_names = tool_definitions.map { |t| t[:name] || t['name'] }
        all_names - active_names
      end

      def load_memories
        return '' unless @project_root

        db = DB::Connection.instance
        search = Memory::Search.new(db, project_path: @project_root)
        recent = search.recent(limit: 20)
        return '' if recent.empty?

        recent.map { |m| format_memory(m) }.join("\n")
      rescue StandardError
        ''
      end

      def format_memory(mem)
        category = mem.respond_to?(:category) ? mem.category : (mem[:category] || mem['category'])
        content = mem.respond_to?(:content) ? mem.content : (mem[:content] || mem['content'])
        "[#{category}] #{content}"
      end

      def load_instincts
        return '' unless @project_root

        db = DB::Connection.instance
        Learning::Injector.call(db: db, project_path: @project_root)
      rescue StandardError
        ''
      end

      def load_rubyn_md
        found = []
        collect_project_instructions(found) if @project_root
        collect_instruction(File.join(Config::Defaults::HOME_DIR, 'RUBYN.md'), found)
        found.uniq.join("\n\n")
      end

      def collect_project_instructions(found)
        walk_up_for_instructions(@project_root, found)
        INSTRUCTION_FILES.each { |name| collect_instruction(File.join(@project_root, name), found) }
        collect_instruction(File.join(@project_root, '.rubyn-code', 'RUBYN.md'), found)
        INSTRUCTION_FILES.each do |n|
          Dir.glob(File.join(@project_root, '*', n)).each do |p|
            collect_instruction(p, found)
          end
        end
      end

      def walk_up_for_instructions(start_dir, found)
        dir = File.dirname(start_dir)
        home = File.expand_path('~')

        while dir.length >= home.length
          INSTRUCTION_FILES.each { |name| collect_instruction(File.join(dir, name), found) }
          break if dir == home

          dir = File.dirname(dir)
        end
      end

      def collect_instruction(path, found)
        return unless File.exist?(path) && File.file?(path)

        content = File.read(path, encoding: 'utf-8')
                      .encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
                      .strip
        return if content.empty?

        found << "# From #{path}\n#{content}"
      end
    end
  end
end
