# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Task budget plumbing' do
  describe RubynCode::LLM::Adapters::Anthropic do
    let(:adapter) { described_class.new }

    describe '#apply_task_budget' do
      it 'sends `remaining` as output_config.task_budget.total for a supported model' do
        body = {}
        adapter.send(:apply_task_budget, body, { total: 100_000, remaining: 42_000 }, 'claude-opus-4-8')
        expect(body[:output_config]).to eq(task_budget: { type: 'tokens', total: 42_000 })
      end

      it 'supports claude-fable-5, claude-mythos-*, claude-sonnet-5, and claude-opus-4-7/8' do
        %w[claude-fable-5 claude-mythos-5 claude-sonnet-5 claude-opus-4-7 claude-opus-4-8].each do |model|
          body = {}
          adapter.send(:apply_task_budget, body, { total: 100_000, remaining: 50_000 }, model)
          expect(body[:output_config]).to eq(task_budget: { type: 'tokens', total: 50_000 })
        end
      end

      it 'merges into an existing output_config hash (e.g. alongside effort)' do
        body = { output_config: { effort: 'high' } }
        adapter.send(:apply_task_budget, body, { total: 100_000, remaining: 42_000 }, 'claude-opus-4-8')
        expect(body[:output_config]).to eq(effort: 'high', task_budget: { type: 'tokens', total: 42_000 })
      end

      it 'leaves body untouched for an unsupported model (e.g. claude-haiku-4-5)' do
        body = { model: 'm' }
        adapter.send(:apply_task_budget, body, { total: 100_000, remaining: 42_000 }, 'claude-haiku-4-5')
        expect(body).to eq(model: 'm')
      end

      it 'leaves body untouched when remaining is below the 20k API minimum' do
        body = { model: 'm' }
        adapter.send(:apply_task_budget, body, { total: 100_000, remaining: 19_999 }, 'claude-opus-4-8')
        expect(body).to eq(model: 'm')
      end

      it 'leaves body untouched when task_budget is nil' do
        body = { model: 'm' }
        adapter.send(:apply_task_budget, body, nil, 'claude-opus-4-8')
        expect(body).to eq(model: 'm')
      end
    end

    describe '#task_budget_on_wire?' do
      it 'is true when output_config.task_budget is present' do
        body = { output_config: { task_budget: { type: 'tokens', total: 42_000 } } }
        expect(adapter.send(:task_budget_on_wire?, body)).to be true
      end

      it 'is false when output_config is absent' do
        expect(adapter.send(:task_budget_on_wire?, { model: 'm' })).to be false
      end
    end
  end

  describe 'Gap: task budget wire format', :webmock do
    include ProviderStubs

    let(:adapter) { RubynCode::LLM::Adapters::Anthropic.new }
    let(:api_url) { RubynCode::LLM::Adapters::Anthropic::API_URL }

    let(:oauth_token) do
      { access_token: 'sk-ant-oat-test-token', expires_at: Time.now + 3600, source: :keychain }
    end

    let(:api_key_token) do
      { access_token: 'sk-ant-api01-test-key', expires_at: Time.now + 3600, source: :env }
    end

    it 'sends output_config.task_budget and appends the beta to the OAuth header, comma-separated' do
      stub_request(:post, api_url)
        .with(headers: { 'anthropic-beta' => 'oauth-2025-04-20,task-budgets-2026-03-13' })
        .to_return do |req|
          @captured = JSON.parse(req.body)
          { status: 200, body: anthropic_text_response('hi').to_json }
        end
      allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(oauth_token)

      adapter.chat(
        messages: [{ role: 'user', content: 'hi' }],
        model: 'claude-opus-4-8',
        max_tokens: 4096,
        task_budget: { total: 100_000, remaining: 42_000 }
      )

      expect(@captured['output_config']).to eq('task_budget' => { 'type' => 'tokens', 'total' => 42_000 })
    end

    it 'sends just the task-budget beta on the API-key path (no oauth-2025-04-20 to preserve)' do
      stub_request(:post, api_url)
        .with(headers: { 'anthropic-beta' => 'task-budgets-2026-03-13' })
        .to_return(status: 200, body: anthropic_text_response('hi').to_json)
      allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(api_key_token)

      adapter.chat(
        messages: [{ role: 'user', content: 'hi' }],
        model: 'claude-opus-4-8',
        max_tokens: 4096,
        task_budget: { total: 100_000, remaining: 42_000 }
      )
    end

    it 'sends nothing on an unsupported model (claude-haiku-4-5)' do
      captured = nil
      stub_request(:post, api_url).to_return do |req|
        captured = JSON.parse(req.body)
        { status: 200, body: anthropic_text_response('hi').to_json }
      end
      allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(oauth_token)

      adapter.chat(
        messages: [{ role: 'user', content: 'hi' }],
        model: 'claude-haiku-4-5',
        max_tokens: 4096,
        task_budget: { total: 100_000, remaining: 42_000 }
      )

      expect(captured).not_to have_key('output_config')
      expect(a_request(:post, api_url).with(headers: { 'anthropic-beta' => 'oauth-2025-04-20' })).to have_been_made
    end

    it 'sends nothing when the configured total is below the 20k API minimum' do
      captured = nil
      stub_request(:post, api_url).to_return do |req|
        captured = JSON.parse(req.body)
        { status: 200, body: anthropic_text_response('hi').to_json }
      end
      allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(oauth_token)

      adapter.chat(
        messages: [{ role: 'user', content: 'hi' }],
        model: 'claude-opus-4-8',
        max_tokens: 4096,
        task_budget: { total: 100_000, remaining: 19_999 }
      )

      expect(captured).not_to have_key('output_config')
      expect(a_request(:post, api_url).with(headers: { 'anthropic-beta' => 'oauth-2025-04-20' })).to have_been_made
    end
  end
end
