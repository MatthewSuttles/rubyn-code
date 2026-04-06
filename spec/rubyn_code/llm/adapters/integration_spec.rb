# frozen_string_literal: true

require 'spec_helper'

# Phase 5: Full round-trip integration tests for each LLM provider.
#
# These tests verify that each adapter correctly:
# 1. Translates messages to provider-specific format
# 2. Sends HTTP requests with correct headers and body
# 3. Parses responses into normalized LLM::Response objects
# 4. Handles streaming SSE with on_text callbacks
# 5. Maps tool_use calls and tool_results correctly
# 6. Normalizes stop reasons, usage, and error handling
#
# All HTTP is stubbed via WebMock. No real API calls.
RSpec.describe 'LLM Adapter Integration', :aggregate_failures do # -- integration suite
  let(:anthropic_url) { 'https://api.anthropic.com/v1/messages' }
  let(:openai_url) { 'https://api.openai.com/v1/chat/completions' }
  let(:groq_url) { 'https://api.groq.com/openai/v1/chat/completions' }

  let(:simple_messages) { [{ role: 'user', content: 'Hello' }] }
  let(:system_prompt) { 'You are a helpful assistant.' }

  let(:tool_schema) do
    [{
      name: 'read_file',
      description: 'Read a file from disk',
      input_schema: {
        type: 'object',
        properties: { path: { type: 'string', description: 'File path' } },
        required: ['path']
      }
    }]
  end

  # Messages that include a tool_result (Anthropic internal format)
  let(:tool_result_messages) do
    [
      { role: 'user', content: 'Read foo.rb for me' },
      { role: 'assistant', content: [
        { type: 'text', text: 'Reading the file...' },
        { type: 'tool_use', id: 'toolu_001', name: 'read_file', input: { 'path' => 'foo.rb' } }
      ] },
      { role: 'user', content: [
        { type: 'tool_result', tool_use_id: 'toolu_001', content: 'puts "hello"' }
      ] }
    ]
  end

  before do
    allow(RubynCode::Auth::TokenStore).to receive_messages(valid?: true, load: {
                                                             access_token: 'sk-ant-api01-test-key',
                                                             expires_at: Time.now + 3600,
                                                             source: :env
                                                           })
  end

  # ===========================================================================
  # Shared examples for cross-provider normalization
  # ===========================================================================

  shared_examples 'a normalized text response' do
    it 'returns a Response with a TextBlock' do
      expect(response).to be_a(RubynCode::LLM::Response)
      expect(response.content.size).to be >= 1
      expect(response.content.first).to be_a(RubynCode::LLM::TextBlock)
      expect(response.text).to eq(expected_text)
    end

    it 'normalizes stop_reason to end_turn' do
      expect(response.stop_reason).to eq('end_turn')
    end

    it 'includes usage data' do
      expect(response.usage).to be_a(RubynCode::LLM::Usage)
      expect(response.usage.input_tokens).to be > 0
      expect(response.usage.output_tokens).to be > 0
    end

    it 'is not a tool_use response' do
      expect(response.tool_use?).to be false
      expect(response.tool_calls).to be_empty
    end
  end

  shared_examples 'a normalized tool_use response' do
    it 'returns a Response with a ToolUseBlock' do
      expect(response).to be_a(RubynCode::LLM::Response)
      tool_blocks = response.tool_calls
      expect(tool_blocks.size).to eq(1)
      expect(tool_blocks.first).to be_a(RubynCode::LLM::ToolUseBlock)
      expect(tool_blocks.first.name).to eq('read_file')
      expect(tool_blocks.first.input).to eq({ 'path' => 'foo.rb' })
    end

    it 'normalizes stop_reason to tool_use' do
      expect(response.stop_reason).to eq('tool_use')
    end

    it 'is a tool_use response' do
      expect(response.tool_use?).to be true
    end
  end

  # ===========================================================================
  # Anthropic Adapter
  # ===========================================================================

  describe 'Anthropic adapter' do
    let(:adapter) { RubynCode::LLM::Adapters::Anthropic.new }

    describe 'text response round-trip' do
      let(:expected_text) { 'Hello! How can I help you today?' }

      let(:response) do
        stub_request(:post, anthropic_url)
          .to_return(status: 200, body: JSON.generate(anthropic_text_response(expected_text)))

        adapter.chat(messages: simple_messages, model: 'claude-sonnet-4-20250514', max_tokens: 1024)
      end

      include_examples 'a normalized text response'

      it 'sends correct Anthropic headers' do
        stub_request(:post, anthropic_url)
          .with(headers: { 'anthropic-version' => '2023-06-01', 'x-api-key' => 'sk-ant-api01-test-key' })
          .to_return(status: 200, body: JSON.generate(anthropic_text_response('OK')))

        adapter.chat(messages: simple_messages, model: 'claude-sonnet-4-20250514', max_tokens: 1024)
      end

      it 'sends system prompt as top-level param (not in messages)' do
        stub_request(:post, anthropic_url)
          .with do |req|
          body = JSON.parse(req.body)
          body.key?('system') && body['messages'].none? do |m|
            m['role'] == 'system'
          end
        end
          .to_return(status: 200, body: JSON.generate(anthropic_text_response('OK')))

        adapter.chat(messages: simple_messages, system: system_prompt, model: 'claude-sonnet-4-20250514',
                     max_tokens: 1024)
      end
    end

    describe 'tool_use response round-trip' do
      let(:response) do
        body = anthropic_tool_use_response(
          tool_name: 'read_file', tool_input: { 'path' => 'foo.rb' },
          text_prefix: 'Let me read that file.'
        )
        stub_request(:post, anthropic_url)
          .to_return(status: 200, body: JSON.generate(body))

        adapter.chat(messages: simple_messages, tools: tool_schema,
                     model: 'claude-sonnet-4-20250514', max_tokens: 1024)
      end

      include_examples 'a normalized tool_use response'

      it 'includes the text prefix alongside the tool call' do
        text_blocks = response.content.select { |b| b.type == 'text' }
        expect(text_blocks.first.text).to eq('Let me read that file.')
      end
    end

    describe 'multi-turn tool round-trip' do
      it 'sends tool_results in Anthropic format and gets final text response' do
        stub_request(:post, anthropic_url)
          .with do |req|
          body = JSON.parse(req.body)
          body['messages'].any? do |m|
            m['content'].is_a?(Array) && m['content'].any? do |b|
              b['type'] == 'tool_result'
            end
          end
        end
          .to_return(status: 200, body: JSON.generate(
            anthropic_text_response('The file contains a hello world program.')
          ))

        response = adapter.chat(
          messages: tool_result_messages,
          tools: tool_schema,
          model: 'claude-sonnet-4-20250514',
          max_tokens: 1024
        )

        expect(response.text).to eq('The file contains a hello world program.')
        expect(response.stop_reason).to eq('end_turn')
      end
    end

    describe 'streaming text round-trip' do
      it 'streams text via on_text callback and returns normalized Response' do
        allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(
          { access_token: 'sk-ant-oat-test-streaming', expires_at: Time.now + 3600, source: :keychain }
        )

        streamed_chunks = []
        stream_body = anthropic_stream_events('Hello from streaming!')

        stub_request(:post, anthropic_url)
          .to_return(status: 200, body: stream_body)

        response = adapter.chat(
          messages: simple_messages, model: 'claude-sonnet-4-20250514', max_tokens: 1024,
          on_text: ->(text) { streamed_chunks << text }
        )

        expect(streamed_chunks).to include('Hello from streaming!')
        expect(response).to be_a(RubynCode::LLM::Response)
        expect(response.content.first).to be_a(RubynCode::LLM::TextBlock)
        expect(response.content.first.text).to eq('Hello from streaming!')
        expect(response.stop_reason).to eq('end_turn')
      end
    end

    describe 'streaming tool_use round-trip' do
      it 'accumulates tool input from stream and returns ToolUseBlock' do
        allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(
          { access_token: 'sk-ant-oat-test-tool-stream', expires_at: Time.now + 3600, source: :keychain }
        )

        stream_body = anthropic_stream_tool_use_events(
          tool_name: 'read_file',
          tool_input_json: '{"path":"bar.rb"}'
        )

        stub_request(:post, anthropic_url)
          .to_return(status: 200, body: stream_body)

        response = adapter.chat(
          messages: simple_messages, tools: tool_schema,
          model: 'claude-sonnet-4-20250514', max_tokens: 1024,
          on_text: ->(_text) {}
        )

        expect(response.tool_use?).to be true
        expect(response.tool_calls.first.name).to eq('read_file')
        expect(response.tool_calls.first.input).to eq({ 'path' => 'bar.rb' })
      end
    end

    describe 'error handling' do
      it 'raises AuthExpiredError on 401' do
        stub_request(:post, anthropic_url)
          .to_return(status: 401, body: JSON.generate(anthropic_error_response(401).last))

        expect do
          adapter.chat(messages: simple_messages, model: 'claude-sonnet-4-20250514', max_tokens: 1024)
        end.to raise_error(RubynCode::LLM::Client::AuthExpiredError, /Authentication expired/)
      end

      it 'raises PromptTooLongError on 413' do
        stub_request(:post, anthropic_url)
          .to_return(status: 413, body: JSON.generate({ 'error' => { 'type' => 'request_too_large',
                                                                     'message' => 'Too many tokens' } }))

        expect do
          adapter.chat(messages: simple_messages, model: 'claude-sonnet-4-20250514', max_tokens: 1024)
        end.to raise_error(RubynCode::LLM::Client::PromptTooLongError, /Prompt too long/)
      end

      it 'retries on 429 then succeeds' do
        allow(adapter).to receive(:sleep)

        stub_request(:post, anthropic_url)
          .to_return(
            { status: 429,
              body: JSON.generate({ 'error' => { 'type' => 'rate_limit_error', 'message' => 'Slow down' } }) },
            { status: 200, body: JSON.generate(anthropic_text_response('Retried successfully')) }
          )

        response = adapter.chat(messages: simple_messages, model: 'claude-sonnet-4-20250514', max_tokens: 1024)
        expect(response.text).to eq('Retried successfully')
      end
    end
  end

  # ===========================================================================
  # OpenAI Adapter
  # ===========================================================================

  describe 'OpenAI adapter' do
    let(:adapter) { RubynCode::LLM::Adapters::OpenAI.new(api_key: 'sk-test-openai-key') }

    describe 'text response round-trip' do
      let(:expected_text) { 'Hello! How can I help you today?' }

      let(:response) do
        stub_request(:post, openai_url)
          .to_return(status: 200, body: JSON.generate(openai_text_response(expected_text)))

        adapter.chat(messages: simple_messages, model: 'gpt-4o', max_tokens: 1024)
      end

      include_examples 'a normalized text response'

      it 'sends correct OpenAI headers' do
        stub_request(:post, openai_url)
          .with(headers: { 'Authorization' => 'Bearer sk-test-openai-key', 'Content-Type' => 'application/json' })
          .to_return(status: 200, body: JSON.generate(openai_text_response('OK')))

        adapter.chat(messages: simple_messages, model: 'gpt-4o', max_tokens: 1024)
      end

      it 'sends system prompt as a system role message' do
        stub_request(:post, openai_url)
          .with do |req|
          msgs = JSON.parse(req.body)['messages']
          msgs.first['role'] == 'system' && msgs.first['content'] == system_prompt
        end
          .to_return(status: 200, body: JSON.generate(openai_text_response('OK')))

        adapter.chat(messages: simple_messages, system: system_prompt, model: 'gpt-4o', max_tokens: 1024)
      end

      it 'translates Anthropic tool schemas to OpenAI function format' do
        stub_request(:post, openai_url)
          .with do |req|
            body = JSON.parse(req.body)
            tools = body['tools']
            tools&.first&.dig('type') == 'function' &&
              tools.first.dig('function', 'name') == 'read_file' &&
              tools.first.dig('function', 'parameters', 'type') == 'object'
          end
          .to_return(status: 200, body: JSON.generate(openai_text_response('No files to read.')))

        adapter.chat(messages: simple_messages, tools: tool_schema, model: 'gpt-4o', max_tokens: 1024)
      end
    end

    describe 'tool_use response round-trip' do
      let(:response) do
        body = openai_tool_call_response(
          tool_name: 'read_file', tool_input: { 'path' => 'foo.rb' },
          text_content: 'Let me read that file.'
        )
        stub_request(:post, openai_url)
          .to_return(status: 200, body: JSON.generate(body))

        adapter.chat(messages: simple_messages, tools: tool_schema, model: 'gpt-4o', max_tokens: 1024)
      end

      include_examples 'a normalized tool_use response'

      it 'includes the text content alongside the tool call' do
        text_blocks = response.content.select { |b| b.type == 'text' }
        expect(text_blocks.first.text).to eq('Let me read that file.')
      end
    end

    describe 'multi-turn tool round-trip with message translation' do
      it 'translates Anthropic-format tool_results to OpenAI role:tool messages' do
        stub_request(:post, openai_url)
          .with do |req|
            msgs = JSON.parse(req.body)['messages']
            # Should have: user, assistant (with tool_calls), tool (with tool_call_id)
            tool_msg = msgs.find { |m| m['role'] == 'tool' }
            assistant_msg = msgs.find { |m| m['role'] == 'assistant' && m['tool_calls'] }
            tool_msg && tool_msg['tool_call_id'] == 'toolu_001' &&
              tool_msg['content'] == 'puts "hello"' &&
              assistant_msg && assistant_msg['tool_calls'].first.dig('function', 'name') == 'read_file'
          end
          .to_return(status: 200, body: JSON.generate(
            openai_text_response('The file contains a hello world program.')
          ))

        response = adapter.chat(
          messages: tool_result_messages,
          tools: tool_schema,
          model: 'gpt-4o',
          max_tokens: 1024
        )

        expect(response.text).to eq('The file contains a hello world program.')
        expect(response.stop_reason).to eq('end_turn')
      end
    end

    describe 'streaming text round-trip' do
      it 'streams text via on_text callback and returns normalized Response' do
        streamed_chunks = []
        stream_body = openai_stream_events('Hello from OpenAI streaming!')

        stub_request(:post, openai_url)
          .to_return(status: 200, body: stream_body)

        response = adapter.chat(
          messages: simple_messages, model: 'gpt-4o', max_tokens: 1024,
          on_text: ->(text) { streamed_chunks << text }
        )

        expect(streamed_chunks).to include('Hello from OpenAI streaming!')
        expect(response).to be_a(RubynCode::LLM::Response)
        expect(response.content.first).to be_a(RubynCode::LLM::TextBlock)
        expect(response.content.first.text).to eq('Hello from OpenAI streaming!')
        expect(response.stop_reason).to eq('end_turn')
      end
    end

    describe 'streaming tool_use round-trip' do
      it 'accumulates tool input from stream and returns ToolUseBlock' do
        stream_body = openai_stream_tool_use_events(
          tool_name: 'read_file',
          tool_input_json: '{"path":"bar.rb"}'
        )

        stub_request(:post, openai_url)
          .to_return(status: 200, body: stream_body)

        response = adapter.chat(
          messages: simple_messages, tools: tool_schema,
          model: 'gpt-4o', max_tokens: 1024,
          on_text: ->(_text) {}
        )

        expect(response.tool_use?).to be true
        expect(response.tool_calls.first.name).to eq('read_file')
        expect(response.tool_calls.first.input).to eq({ 'path' => 'bar.rb' })
      end
    end

    describe 'error handling' do
      it 'raises AuthExpiredError on 401' do
        stub_request(:post, openai_url)
          .to_return(status: 401, body: JSON.generate(openai_error_response(401).last))

        expect do
          adapter.chat(messages: simple_messages, model: 'gpt-4o', max_tokens: 1024)
        end.to raise_error(RubynCode::LLM::Client::AuthExpiredError, /Authentication expired/)
      end

      it 'raises PromptTooLongError on 413' do
        stub_request(:post, openai_url)
          .to_return(
            status: 413,
            body: JSON.generate({ 'error' => { 'message' => 'Maximum context length exceeded' } })
          )

        expect do
          adapter.chat(messages: simple_messages, model: 'gpt-4o', max_tokens: 1024)
        end.to raise_error(RubynCode::LLM::Client::PromptTooLongError, /Prompt too long/)
      end

      it 'retries on 429 then succeeds' do
        allow(adapter).to receive(:sleep)

        stub_request(:post, openai_url)
          .to_return(
            { status: 429, body: JSON.generate({ 'error' => { 'message' => 'Rate limit exceeded' } }) },
            { status: 200, body: JSON.generate(openai_text_response('Retried successfully')) }
          )

        response = adapter.chat(messages: simple_messages, model: 'gpt-4o', max_tokens: 1024)
        expect(response.text).to eq('Retried successfully')
      end

      it 'raises AuthExpiredError when no API key is configured' do
        keyless_adapter = RubynCode::LLM::Adapters::OpenAI.new

        stub_request(:post, openai_url).to_return(status: 200, body: '{}')
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('OPENAI_API_KEY') { |&blk| blk.call }

        expect do
          keyless_adapter.chat(messages: simple_messages, model: 'gpt-4o', max_tokens: 1024)
        end.to raise_error(RubynCode::LLM::Client::AuthExpiredError, /No OpenAI API key/)
      end
    end
  end

  # ===========================================================================
  # OpenAI-Compatible Adapter (Groq)
  # ===========================================================================

  describe 'OpenAI-compatible adapter (Groq)' do
    let(:adapter) do
      RubynCode::LLM::Adapters::OpenAICompatible.new(
        provider: 'groq',
        base_url: 'https://api.groq.com/openai/v1',
        api_key: 'gsk-test-groq-key',
        available_models: %w[llama-3.3-70b-versatile mixtral-8x7b-32768]
      )
    end

    describe 'text response round-trip' do
      let(:expected_text) { 'Hello from Groq!' }

      let(:response) do
        stub_request(:post, groq_url)
          .to_return(status: 200, body: JSON.generate(openai_text_response(expected_text, id: 'chatcmpl-groq001')))

        adapter.chat(messages: simple_messages, model: 'llama-3.3-70b-versatile', max_tokens: 1024)
      end

      include_examples 'a normalized text response'

      it 'sends requests to the custom base_url' do
        stub_request(:post, groq_url)
          .with(headers: { 'Authorization' => 'Bearer gsk-test-groq-key' })
          .to_return(status: 200, body: JSON.generate(openai_text_response('OK')))

        adapter.chat(messages: simple_messages, model: 'llama-3.3-70b-versatile', max_tokens: 1024)
      end
    end

    describe 'tool_use response round-trip' do
      let(:response) do
        body = openai_tool_call_response(tool_name: 'read_file', tool_input: { 'path' => 'foo.rb' })
        stub_request(:post, groq_url)
          .to_return(status: 200, body: JSON.generate(body))

        adapter.chat(messages: simple_messages, tools: tool_schema,
                     model: 'llama-3.3-70b-versatile', max_tokens: 1024)
      end

      include_examples 'a normalized tool_use response'
    end

    describe 'multi-turn tool round-trip with message translation' do
      it 'translates Anthropic-format tool_results to OpenAI format for compatible providers' do
        stub_request(:post, groq_url)
          .with do |req|
            msgs = JSON.parse(req.body)['messages']
            tool_msg = msgs.find { |m| m['role'] == 'tool' }
            tool_msg && tool_msg['tool_call_id'] == 'toolu_001'
          end
          .to_return(status: 200, body: JSON.generate(openai_text_response('File analyzed.')))

        response = adapter.chat(
          messages: tool_result_messages, tools: tool_schema,
          model: 'llama-3.3-70b-versatile', max_tokens: 1024
        )

        expect(response.text).to eq('File analyzed.')
      end
    end

    describe 'streaming text round-trip' do
      it 'streams via custom base_url' do
        streamed_chunks = []
        stream_body = openai_stream_events('Groq streaming!')

        stub_request(:post, groq_url)
          .to_return(status: 200, body: stream_body)

        response = adapter.chat(
          messages: simple_messages, model: 'llama-3.3-70b-versatile', max_tokens: 1024,
          on_text: ->(text) { streamed_chunks << text }
        )

        expect(streamed_chunks).to include('Groq streaming!')
        expect(response.content.first.text).to eq('Groq streaming!')
      end
    end

    describe 'provider identity' do
      it 'reports the custom provider name' do
        expect(adapter.provider_name).to eq('groq')
      end

      it 'reports the configured models' do
        expect(adapter.models).to eq(%w[llama-3.3-70b-versatile mixtral-8x7b-32768])
      end
    end

    describe 'local provider auth' do
      it 'skips API key requirement for localhost providers' do
        local_adapter = RubynCode::LLM::Adapters::OpenAICompatible.new(
          provider: 'ollama', base_url: 'http://localhost:11434/v1', available_models: ['llama3']
        )

        stub_request(:post, 'http://localhost:11434/v1/chat/completions')
          .to_return(status: 200, body: JSON.generate(openai_text_response('Local model says hi')))

        response = local_adapter.chat(messages: simple_messages, model: 'llama3', max_tokens: 1024)
        expect(response.text).to eq('Local model says hi')
      end
    end
  end

  # ===========================================================================
  # Client facade round-trip
  # ===========================================================================

  describe 'Client facade' do
    describe 'delegates to Anthropic by default' do
      let(:client) { RubynCode::LLM::Client.new(model: 'claude-sonnet-4-20250514') }

      it 'sends request through Anthropic adapter and returns normalized response' do
        stub_request(:post, anthropic_url)
          .to_return(status: 200, body: JSON.generate(anthropic_text_response('Hello from Claude')))

        response = client.chat(messages: simple_messages)
        expect(response.text).to eq('Hello from Claude')
        expect(response.stop_reason).to eq('end_turn')
      end
    end

    describe 'delegates to OpenAI after provider switch' do
      let(:client) { RubynCode::LLM::Client.new(model: 'claude-sonnet-4-20250514') }

      it 'switches to OpenAI and gets normalized response' do
        client.switch_provider!('openai', model: 'gpt-4o')
        client.adapter.instance_variable_set(:@api_key, 'sk-test-key')

        stub_request(:post, openai_url)
          .to_return(status: 200, body: JSON.generate(openai_text_response('Hello from GPT')))

        response = client.chat(messages: simple_messages)
        expect(response.text).to eq('Hello from GPT')
        expect(response.stop_reason).to eq('end_turn')
      end
    end

    describe '#stream convenience method' do
      let(:client) { RubynCode::LLM::Client.new(model: 'claude-sonnet-4-20250514') }

      it 'passes the block as on_text through to the adapter' do
        allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(
          { access_token: 'sk-ant-oat-stream-test', expires_at: Time.now + 3600, source: :keychain }
        )

        streamed = []
        stub_request(:post, anthropic_url)
          .to_return(status: 200, body: anthropic_stream_events('Streamed via Client#stream'))

        response = client.stream(messages: simple_messages) { |text| streamed << text }
        expect(streamed).to include('Streamed via Client#stream')
        expect(response).to be_a(RubynCode::LLM::Response)
      end
    end
  end

  # ===========================================================================
  # Cross-provider normalization verification
  # ===========================================================================

  describe 'cross-provider response normalization' do
    let(:anthropic_adapter) { RubynCode::LLM::Adapters::Anthropic.new }
    let(:openai_adapter) { RubynCode::LLM::Adapters::OpenAI.new(api_key: 'sk-test') }

    it 'produces structurally identical text responses from different providers' do
      stub_request(:post, anthropic_url)
        .to_return(status: 200, body: JSON.generate(anthropic_text_response('Same answer')))
      stub_request(:post, openai_url)
        .to_return(status: 200, body: JSON.generate(openai_text_response('Same answer')))

      ant_resp = anthropic_adapter.chat(messages: simple_messages, model: 'claude-sonnet-4-20250514',
                                        max_tokens: 1024)
      oai_resp = openai_adapter.chat(messages: simple_messages, model: 'gpt-4o', max_tokens: 1024)

      # Same structure
      expect(ant_resp.text).to eq(oai_resp.text)
      expect(ant_resp.stop_reason).to eq(oai_resp.stop_reason)
      expect(ant_resp.content.map(&:class)).to eq(oai_resp.content.map(&:class))
      expect(ant_resp.tool_use?).to eq(oai_resp.tool_use?)

      # Both have usage
      expect(ant_resp.usage).to be_a(RubynCode::LLM::Usage)
      expect(oai_resp.usage).to be_a(RubynCode::LLM::Usage)
    end

    it 'produces structurally identical tool_use responses from different providers' do
      stub_request(:post, anthropic_url)
        .to_return(status: 200, body: JSON.generate(
          anthropic_tool_use_response(tool_name: 'read_file', tool_input: { 'path' => 'test.rb' })
        ))
      stub_request(:post, openai_url)
        .to_return(status: 200, body: JSON.generate(
          openai_tool_call_response(tool_name: 'read_file', tool_input: { 'path' => 'test.rb' })
        ))

      ant_resp = anthropic_adapter.chat(messages: simple_messages, tools: tool_schema,
                                        model: 'claude-sonnet-4-20250514', max_tokens: 1024)
      oai_resp = openai_adapter.chat(messages: simple_messages, tools: tool_schema,
                                     model: 'gpt-4o', max_tokens: 1024)

      expect(ant_resp.stop_reason).to eq(oai_resp.stop_reason)
      expect(ant_resp.tool_use?).to eq(oai_resp.tool_use?)
      expect(ant_resp.tool_calls.size).to eq(oai_resp.tool_calls.size)
      expect(ant_resp.tool_calls.first.name).to eq(oai_resp.tool_calls.first.name)
      expect(ant_resp.tool_calls.first.input).to eq(oai_resp.tool_calls.first.input)
    end

    it 'normalizes all stop reason variants to the same set' do
      # Anthropic: 'end_turn' pass-through
      stub_request(:post, anthropic_url)
        .to_return(status: 200, body: JSON.generate(anthropic_text_response('ok')))
      ant_resp = anthropic_adapter.chat(messages: simple_messages, model: 'claude-sonnet-4-20250514',
                                        max_tokens: 1024)

      # OpenAI: 'stop' -> 'end_turn'
      stub_request(:post, openai_url)
        .to_return(status: 200, body: JSON.generate(openai_text_response('ok')))
      oai_resp = openai_adapter.chat(messages: simple_messages, model: 'gpt-4o', max_tokens: 1024)

      expect(ant_resp.stop_reason).to eq('end_turn')
      expect(oai_resp.stop_reason).to eq('end_turn')
    end
  end
end
