# frozen_string_literal: true

# End-to-end WebMock integration tests that hit the actual Anthropic
# adapter wire path and verify the request body / response parsing for
# each parity gap. These are the strongest single-test-proves-it proof
# that a feature is properly wired to Anthropic.
require 'spec_helper'

RSpec.describe 'Parity wire-format verification', :webmock do
  include ProviderStubs

  let(:adapter) { RubynCode::LLM::Adapters::Anthropic.new }
  let(:api_url) { RubynCode::LLM::Adapters::Anthropic::API_URL }

  before do
    allow(RubynCode::Auth::TokenStore).to receive_messages(
      load: { 'provider' => 'anthropic', 'oauth_token' => 'sk-test' },
      valid?: true
    )
  end

  describe 'Gap 1: extended thinking wire format' do
    it 'sends `thinking: {type: adaptive}` on the request body for 4.6+ models' do
      captured = nil
      stub_request(:post, api_url).to_return do |req|
        captured = JSON.parse(req.body)
        { status: 200, body: anthropic_text_response('hi').to_json }
      end

      body = adapter.send(:build_request_body,
                          messages: [{ role: 'user', content: 'hi' }],
                          tools: nil, system: nil,
                          model: 'claude-opus-4-8', max_tokens: 4096,
                          stream: false, thinking: { budget_tokens: 1024 })
      adapter.send(:execute_with_retries, body, nil)

      expect(captured).to include('thinking' => { 'type' => 'adaptive' })
    end

    it 'parses a `thinking` content block from the response' do
      stub_request(:post, api_url).to_return(
        status: 200,
        body: {
          'id' => 'msg_001', 'type' => 'message', 'role' => 'assistant',
          'content' => [
            { 'type' => 'thinking', 'thinking' => 'step 1: parse input' },
            { 'type' => 'text', 'text' => 'final answer' }
          ],
          'stop_reason' => 'end_turn',
          'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
        }.to_json
      )

      response = adapter.send(:execute_with_retries, {
                                model: 'claude-opus-4-8',
                                messages: [{ role: 'user', content: 'hi' }],
                                max_tokens: 4096,
                                thinking: { type: 'enabled', budget_tokens: 1024 }
                              }, nil)

      types = response.content.map(&:type)
      expect(types).to include('thinking')
      expect(response.content.find { |b| b.type == 'thinking' }.text).to eq('step 1: parse input')
    end
  end

  describe 'Gap 2: image wire format' do
    it 'sends `image` content blocks as Anthropic source blocks' do
      captured = nil
      stub_request(:post, api_url).to_return do |req|
        captured = JSON.parse(req.body)
        { status: 200, body: anthropic_text_response('I see an image').to_json }
      end

      image_source = { 'type' => 'base64', 'media_type' => 'image/png', 'data' => 'BASE64DATA' }
      adapter.send(:execute_with_retries, {
                     model: 'claude-opus-4-8',
                     messages: [
                       { role: 'user', content: [
                         { 'type' => 'text', 'text' => 'what is this?' },
                         { 'type' => 'image', 'source' => image_source }
                       ] }
                     ],
                     max_tokens: 4096
                   }, nil)

      content = captured['messages'].first['content']
      expect(content).to include(
        'type' => 'image',
        'source' => { 'type' => 'base64', 'media_type' => 'image/png', 'data' => 'BASE64DATA' }
      )
    end
  end

  describe 'Gap 3: effort wire format' do
    before do
      allow(RubynCode::Auth::TokenStore).to receive_messages(
        load: { 'provider' => 'anthropic', 'access_token' => 'sk-test', 'source' => 'keychain' },
        valid?: true
      )
    end

    it 'sends `output_config: {effort}` on the request body when effort is set' do
      captured = nil
      stub_request(:post, api_url).to_return do |req|
        captured = JSON.parse(req.body)
        { status: 200, body: anthropic_text_response('hi').to_json }
      end

      adapter.chat(
        messages: [{ role: 'user', content: 'hi' }],
        model: 'claude-opus-4-8',
        max_tokens: 4096,
        effort: 'high'
      )

      expect(captured).to include('output_config' => { 'effort' => 'high' })
    end

    it 'omits output_config when effort is not set' do
      captured = nil
      stub_request(:post, api_url).to_return do |req|
        captured = JSON.parse(req.body)
        { status: 200, body: anthropic_text_response('hi').to_json }
      end

      adapter.chat(
        messages: [{ role: 'user', content: 'hi' }],
        model: 'claude-opus-4-8',
        max_tokens: 4096
      )

      expect(captured).not_to have_key('output_config')
    end
  end
end
