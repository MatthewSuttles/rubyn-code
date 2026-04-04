# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::SpawnAgent do
  let(:llm_client) { instance_double('LLMClient') }
  let(:status_calls) { [] }
  let(:on_status) { ->(type, msg) { status_calls << [type, msg] } }

  # Helper to build a text-only LLM response
  def make_text_response(text)
    text_block = instance_double('TextBlock', type: 'text', text: text)
    instance_double('Response', content: [text_block], stop_reason: 'end_turn')
  end

  # Helper to build a tool-use LLM response
  def make_tool_response(tool_name, input, id: 'tool_123')
    tool_block = instance_double(
      'ToolUseBlock',
      type: 'tool_use',
      name: tool_name,
      input: input,
      id: id
    )
    instance_double('Response', content: [tool_block], stop_reason: 'tool_use')
  end

  # Helper to build a response with both text and tool_use blocks
  def make_mixed_response(text, tool_name, input, id: 'tool_123')
    text_block = instance_double('TextBlock', type: 'text', text: text)
    tool_block = instance_double(
      'ToolUseBlock',
      type: 'tool_use',
      name: tool_name,
      input: input,
      id: id
    )
    instance_double('Response', content: [text_block, tool_block], stop_reason: 'tool_use')
  end

  def build_tool(project_root:)
    tool = described_class.new(project_root: project_root)
    tool.llm_client = llm_client
    tool.on_status = on_status
    tool
  end

  before do
    allow(RubynCode::SubAgents::Summarizer).to receive(:call) { |text, **_| text }
    allow(RubynCode::Tools::Registry).to receive(:tool_definitions).and_return([
      { name: 'read_file', description: 'Read a file', input_schema: {} },
      { name: 'glob', description: 'Glob files', input_schema: {} },
      { name: 'grep', description: 'Search files', input_schema: {} },
      { name: 'bash', description: 'Run command', input_schema: {} },
      { name: 'load_skill', description: 'Load skill', input_schema: {} },
      { name: 'memory_search', description: 'Search memory', input_schema: {} },
      { name: 'write_file', description: 'Write a file', input_schema: {} },
      { name: 'edit_file', description: 'Edit a file', input_schema: {} },
      { name: 'spawn_agent', description: 'Spawn agent', input_schema: {} },
      { name: 'send_message', description: 'Send message', input_schema: {} },
      { name: 'read_inbox', description: 'Read inbox', input_schema: {} },
      { name: 'compact', description: 'Compact', input_schema: {} },
      { name: 'memory_write', description: 'Write memory', input_schema: {} }
    ])
  end

  describe '#execute' do
    context 'basic execution' do
      it 'returns result with "Sub-Agent Result" header for text-only LLM response' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('I found 3 files.'))

          tool = build_tool(project_root: dir)
          result = tool.execute(prompt: 'Find all Ruby files')

          expect(result).to include('## Sub-Agent Result (explore)')
          expect(result).to include('I found 3 files.')
        end
      end

      it 'defaults to explore agent type' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('Done.'))

          tool = build_tool(project_root: dir)
          result = tool.execute(prompt: 'Explore the codebase')

          expect(result).to include('Sub-Agent Result (explore)')
        end
      end

      it 'accepts worker agent type' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('Written.'))

          tool = build_tool(project_root: dir)
          result = tool.execute(prompt: 'Write a file', agent_type: 'worker')

          expect(result).to include('Sub-Agent Result (worker)')
        end
      end

      it 'calls status callback with :started and :done' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('Done.'))

          tool = build_tool(project_root: dir)
          tool.execute(prompt: 'Do something')

          expect(status_calls).to include([:started, 'Spawning explore agent...'])
          expect(status_calls).to include([:done, 'Agent finished (0 tool calls).'])
        end
      end
    end

    context 'tool execution loop' do
      let(:fake_read_file_class) do
        Class.new(RubynCode::Tools::Base) do
          const_set(:TOOL_NAME, 'read_file')
          const_set(:DESCRIPTION, 'Read a file')
          const_set(:PARAMETERS, {}.freeze)
          const_set(:RISK_LEVEL, :read)

          def execute(**_params)
            'file contents here'
          end
        end
      end

      let(:fake_write_file_class) do
        Class.new(RubynCode::Tools::Base) do
          const_set(:TOOL_NAME, 'write_file')
          const_set(:DESCRIPTION, 'Write a file')
          const_set(:PARAMETERS, {}.freeze)
          const_set(:RISK_LEVEL, :write)

          def execute(**_params)
            'file written'
          end
        end
      end

      it 'executes tool calls from LLM response, appends results' do
        with_temp_project do |dir|
          allow(RubynCode::Tools::Registry).to receive(:get)
            .with('read_file').and_return(fake_read_file_class)

          tool_response = make_tool_response('read_file', { 'path' => 'foo.rb' }, id: 'tc_1')
          text_response = make_text_response('Found the file contents.')

          allow(llm_client).to receive(:chat).and_return(tool_response, text_response)

          tool = build_tool(project_root: dir)
          result = tool.execute(prompt: 'Read foo.rb')

          expect(result).to include('Sub-Agent Result (explore)')
          expect(result).to include('Found the file contents.')
          expect(status_calls).to include([:tool, 'read_file'])
          expect(status_calls).to include([:done, 'Agent finished (1 tool calls).'])
        end
      end

      it 'blocks recursive spawn_agent calls with error' do
        with_temp_project do |dir|
          # Registry.get will be called but the spawn_agent check comes first
          spawn_agent_class = Class.new(RubynCode::Tools::Base) do
            const_set(:TOOL_NAME, 'spawn_agent')
            const_set(:DESCRIPTION, 'Spawn')
            const_set(:PARAMETERS, {}.freeze)
            const_set(:RISK_LEVEL, :execute)
          end

          allow(RubynCode::Tools::Registry).to receive(:get)
            .with('spawn_agent').and_return(spawn_agent_class)

          tool_response = make_tool_response('spawn_agent', { 'prompt' => 'nested' }, id: 'tc_spawn')
          text_response = make_text_response('Cannot spawn.')

          allow(llm_client).to receive(:chat).and_return(tool_response, text_response)

          tool = build_tool(project_root: dir)
          result = tool.execute(prompt: 'Try to spawn', agent_type: 'worker')

          # It should still complete (the error is added as a tool result, not raised)
          expect(result).to include('Sub-Agent Result (worker)')
        end
      end

      it 'blocks non-read tools for explore agents' do
        with_temp_project do |dir|
          allow(RubynCode::Tools::Registry).to receive(:get)
            .with('write_file').and_return(fake_write_file_class)

          tool_response = make_tool_response('write_file', { 'path' => 'x.rb', 'content' => 'hi' }, id: 'tc_write')
          text_response = make_text_response('Could not write.')

          allow(llm_client).to receive(:chat).and_return(tool_response, text_response)

          tool = build_tool(project_root: dir)
          result = tool.execute(prompt: 'Write a file', agent_type: 'explore')

          expect(result).to include('Sub-Agent Result (explore)')
        end
      end

      it 'handles tool execution errors gracefully' do
        with_temp_project do |dir|
          error_tool_class = Class.new(RubynCode::Tools::Base) do
            const_set(:TOOL_NAME, 'read_file')
            const_set(:DESCRIPTION, 'Read')
            const_set(:PARAMETERS, {}.freeze)
            const_set(:RISK_LEVEL, :read)

            def execute(**_params)
              raise StandardError, 'file not found'
            end
          end

          allow(RubynCode::Tools::Registry).to receive(:get)
            .with('read_file').and_return(error_tool_class)

          tool_response = make_tool_response('read_file', { 'path' => 'missing.rb' }, id: 'tc_err')
          text_response = make_text_response('File was not found.')

          allow(llm_client).to receive(:chat).and_return(tool_response, text_response)

          tool = build_tool(project_root: dir)
          result = tool.execute(prompt: 'Read missing file')

          # Should not raise — errors are caught and added as tool results
          expect(result).to include('Sub-Agent Result (explore)')
          expect(result).to include('File was not found.')
        end
      end
    end

    context 'iteration limits' do
      it 'returns INCOMPLETE result when hitting max iterations' do
        with_temp_project do |dir|
          stub_const('RubynCode::Config::Defaults::MAX_EXPLORE_AGENT_ITERATIONS', 1)

          allow(RubynCode::Tools::Registry).to receive(:get).with('read_file').and_return(
            Class.new(RubynCode::Tools::Base) do
              const_set(:TOOL_NAME, 'read_file')
              const_set(:DESCRIPTION, 'Read')
              const_set(:PARAMETERS, {}.freeze)
              const_set(:RISK_LEVEL, :read)

              def execute(**_params)
                'contents'
              end
            end
          )

          # First call: tool use (iteration 0 -> executes tool -> iteration becomes 1)
          # Second call: iteration >= max, asks for summary -> returns text
          tool_response = make_tool_response('read_file', { 'path' => 'a.rb' }, id: 'tc_limit')
          summary_response = make_text_response('Partial summary of work.')

          allow(llm_client).to receive(:chat).and_return(tool_response, summary_response)

          tool = build_tool(project_root: dir)
          result = tool.execute(prompt: 'Read everything')

          expect(result).to include('INCOMPLETE')
          expect(result).to include('Partial summary of work.')
        end
      end

      it 'asks LLM for final summary at turn limit' do
        with_temp_project do |dir|
          stub_const('RubynCode::Config::Defaults::MAX_EXPLORE_AGENT_ITERATIONS', 1)

          allow(RubynCode::Tools::Registry).to receive(:get).with('read_file').and_return(
            Class.new(RubynCode::Tools::Base) do
              const_set(:TOOL_NAME, 'read_file')
              const_set(:DESCRIPTION, 'Read')
              const_set(:PARAMETERS, {}.freeze)
              const_set(:RISK_LEVEL, :read)

              def execute(**_params)
                'contents'
              end
            end
          )

          tool_response = make_tool_response('read_file', { 'path' => 'a.rb' }, id: 'tc_sum')
          summary_response = make_text_response('Final summary.')

          chat_calls = []
          allow(llm_client).to receive(:chat) do |**kwargs|
            chat_calls << kwargs
            if chat_calls.size == 1
              tool_response
            else
              summary_response
            end
          end

          tool = build_tool(project_root: dir)
          tool.execute(prompt: 'Read everything')

          # The second call should have empty tools (summary request)
          expect(chat_calls.last[:tools]).to eq([])
        end
      end
    end

    context 'tools filtering' do
      it 'explore agents get only read-only tools' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('Done.'))

          tool = build_tool(project_root: dir)

          # Call execute to trigger tools_for_type
          # We verify by checking what tools are passed to llm_client.chat
          chat_args = nil
          allow(llm_client).to receive(:chat) do |**kwargs|
            chat_args = kwargs
            make_text_response('Done.')
          end

          tool.execute(prompt: 'Explore', agent_type: 'explore')

          tool_names = chat_args[:tools].map { |t| t[:name] }
          expect(tool_names).to contain_exactly('read_file', 'glob', 'grep', 'bash', 'load_skill', 'memory_search')
          expect(tool_names).not_to include('write_file', 'edit_file', 'spawn_agent')
        end
      end

      it 'worker agents get all tools except blocked ones' do
        with_temp_project do |dir|
          chat_args = nil
          allow(llm_client).to receive(:chat) do |**kwargs|
            chat_args = kwargs
            make_text_response('Done.')
          end

          tool = build_tool(project_root: dir)
          tool.execute(prompt: 'Work', agent_type: 'worker')

          tool_names = chat_args[:tools].map { |t| t[:name] }
          blocked = %w[spawn_agent send_message read_inbox compact memory_write]
          blocked.each do |blocked_name|
            expect(tool_names).not_to include(blocked_name)
          end
          expect(tool_names).to include('read_file', 'glob', 'grep', 'bash', 'write_file', 'edit_file')
        end
      end
    end

    context 'integration with Summarizer' do
      it 'passes result through SubAgents::Summarizer with max_length: 3000' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('Raw result text.'))
          allow(RubynCode::SubAgents::Summarizer).to receive(:call)
            .with('Raw result text.', max_length: 3000)
            .and_return('Summarized result.')

          tool = build_tool(project_root: dir)
          result = tool.execute(prompt: 'Do something')

          expect(RubynCode::SubAgents::Summarizer).to have_received(:call)
            .with('Raw result text.', max_length: 3000)
          expect(result).to include('Summarized result.')
        end
      end
    end
  end
end
