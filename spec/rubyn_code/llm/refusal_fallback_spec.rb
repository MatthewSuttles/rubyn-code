# frozen_string_literal: true

require 'spec_helper'
require 'rubyn_code/llm/message_builder'
require 'rubyn_code/llm/adapters/anthropic_streaming'

RSpec.describe 'Refusal handling and server-side fallbacks' do
  describe RubynCode::LLM::Response do
    it 'defaults stop_details to nil when omitted' do
      response = described_class.new(
        id: 'r', content: [], stop_reason: 'end_turn',
        usage: RubynCode::LLM::Usage.new(input_tokens: 0, output_tokens: 0)
      )
      expect(response.stop_details).to be_nil
      expect(response.refusal?).to be false
    end

    it 'reports refusal? true when stop_reason is "refusal"' do
      response = described_class.new(
        id: 'r', content: [], stop_reason: 'refusal', stop_details: { 'category' => 'cyber' },
        usage: RubynCode::LLM::Usage.new(input_tokens: 0, output_tokens: 0)
      )
      expect(response.refusal?).to be true
      expect(response.stop_details).to eq('category' => 'cyber')
    end
  end

  describe RubynCode::LLM::Adapters::Anthropic do
    let(:adapter) { described_class.new }

    describe '#apply_fallbacks' do
      it 'adds the fallbacks param for claude-fable-5' do
        body = {}
        adapter.send(:apply_fallbacks, body, 'claude-fable-5')
        expect(body[:fallbacks]).to eq([{ model: 'claude-opus-4-8' }])
      end

      it 'adds the fallbacks param for claude-mythos-5' do
        body = {}
        adapter.send(:apply_fallbacks, body, 'claude-mythos-5')
        expect(body[:fallbacks]).to eq([{ model: 'claude-opus-4-8' }])
      end

      it 'adds the fallbacks param for claude-opus-5' do
        body = {}
        adapter.send(:apply_fallbacks, body, 'claude-opus-5')
        expect(body[:fallbacks]).to eq([{ model: 'claude-opus-4-8' }])
      end

      it 'leaves body untouched for claude-opus-4-8' do
        body = { model: 'claude-opus-4-8' }
        adapter.send(:apply_fallbacks, body, 'claude-opus-4-8')
        expect(body).to eq(model: 'claude-opus-4-8')
      end
    end

    describe '#build_api_response' do
      it 'parses stop_details from the response body' do
        body = {
          'id' => 'msg_refused', 'content' => [], 'stop_reason' => 'refusal',
          'stop_details' => { 'type' => 'refusal', 'category' => 'cyber' },
          'usage' => { 'input_tokens' => 12, 'output_tokens' => 0 }
        }
        response = adapter.send(:build_api_response, body)
        expect(response.stop_reason).to eq('refusal')
        expect(response.stop_details).to eq('type' => 'refusal', 'category' => 'cyber')
        expect(response.content).to eq([])
      end
    end
  end

  describe RubynCode::LLM::Adapters::AnthropicStreaming do
    let(:events) { [] }
    let(:streamer) { RubynCode::LLM::Adapters::AnthropicStreaming.new { |e| events << e } }

    it 'carries stop_details from message_delta into the finalized Response' do
      streamer.feed <<~SSE
        event: message_start
        data: {"message":{"id":"msg_1"}}

      SSE
      streamer.feed <<~SSE
        event: message_delta
        data: {"delta":{"stop_reason":"refusal","stop_details":{"type":"refusal","category":"bio"}}}

      SSE
      response = streamer.finalize
      expect(response.stop_reason).to eq('refusal')
      expect(response.stop_details).to eq('type' => 'refusal', 'category' => 'bio')
    end
  end

  describe 'wire format', :webmock do
    include ProviderStubs

    let(:adapter) { RubynCode::LLM::Adapters::Anthropic.new }
    let(:api_url) { RubynCode::LLM::Adapters::Anthropic::API_URL }

    before do
      allow(RubynCode::Auth::TokenStore).to receive_messages(
        load: { access_token: 'sk-ant-oat-test-token', source: :keychain },
        valid?: true
      )
    end

    it 'sends fallbacks + the combined beta header for claude-fable-5' do
      captured = nil
      stub_request(:post, api_url)
        .with(headers: { 'anthropic-beta' => 'oauth-2025-04-20,server-side-fallback-2026-06-01' })
        .to_return do |req|
          captured = JSON.parse(req.body)
          { status: 200, body: anthropic_text_response('hi').to_json }
        end

      adapter.chat(messages: [{ role: 'user', content: 'hi' }], model: 'claude-fable-5', max_tokens: 4096)

      expect(captured['fallbacks']).to eq([{ 'model' => 'claude-opus-4-8' }])
    end

    it 'sends no fallbacks param and no fallback beta for claude-opus-4-8' do
      captured = nil
      stub_request(:post, api_url)
        .with(headers: { 'anthropic-beta' => 'oauth-2025-04-20' })
        .to_return do |req|
          captured = JSON.parse(req.body)
          { status: 200, body: anthropic_text_response('hi').to_json }
        end

      adapter.chat(messages: [{ role: 'user', content: 'hi' }], model: 'claude-opus-4-8', max_tokens: 4096)

      expect(captured).not_to have_key('fallbacks')
    end

    it 'sends only the fallback beta (no oauth beta) on the API-key path' do
      allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(access_token: 'sk-ant-api01-test', source: :env)

      stub_request(:post, api_url)
        .with(headers: { 'anthropic-beta' => 'server-side-fallback-2026-06-01' })
        .to_return(status: 200, body: anthropic_text_response('hi').to_json)

      adapter.chat(messages: [{ role: 'user', content: 'hi' }], model: 'claude-fable-5', max_tokens: 4096)
    end

    it 'combines the oauth, task-budget, and fallback betas when all apply' do
      stub_request(:post, api_url)
        .with(headers: {
                'anthropic-beta' => 'oauth-2025-04-20,task-budgets-2026-03-13,server-side-fallback-2026-06-01'
              })
        .to_return(status: 200, body: anthropic_text_response('hi').to_json)

      adapter.chat(
        messages: [{ role: 'user', content: 'hi' }],
        model: 'claude-fable-5', max_tokens: 4096,
        task_budget: { total: 100_000, remaining: 42_000 }
      )
    end
  end
end
