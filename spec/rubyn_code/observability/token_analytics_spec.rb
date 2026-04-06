# frozen_string_literal: true

RSpec.describe RubynCode::Observability::TokenAnalytics do
  subject(:analytics) { described_class.new }

  describe '#record_input' do
    it 'accumulates tokens by category' do
      analytics.record_input(:system_prompt, 100)
      analytics.record_input(:system_prompt, 50)
      analytics.record_input(:conversation, 200)

      expect(analytics.input_breakdown[:system_prompt]).to eq(150)
      expect(analytics.input_breakdown[:conversation]).to eq(200)
    end

    it 'handles string categories by converting to symbols' do
      analytics.record_input('system_prompt', 100)
      expect(analytics.input_breakdown[:system_prompt]).to eq(100)
    end
  end

  describe '#record_output' do
    it 'accumulates tokens by category' do
      analytics.record_output(:code_written, 300)
      analytics.record_output(:code_written, 100)
      analytics.record_output(:explanations, 50)

      expect(analytics.output_breakdown[:code_written]).to eq(400)
      expect(analytics.output_breakdown[:explanations]).to eq(50)
    end
  end

  describe '#record_savings' do
    it 'accumulates tokens by feature' do
      analytics.record_savings(:prompt_caching, 500)
      analytics.record_savings(:prompt_caching, 200)
      analytics.record_savings(:tool_filtering, 100)

      expect(analytics.savings[:prompt_caching]).to eq(700)
      expect(analytics.savings[:tool_filtering]).to eq(100)
    end
  end

  describe '#total_input_tokens' do
    it 'sums all input categories' do
      analytics.record_input(:system_prompt, 100)
      analytics.record_input(:conversation, 200)
      analytics.record_input(:tool_output, 300)

      expect(analytics.total_input_tokens).to eq(600)
    end

    it 'returns zero when nothing recorded' do
      expect(analytics.total_input_tokens).to eq(0)
    end
  end

  describe '#total_output_tokens' do
    it 'sums all output categories' do
      analytics.record_output(:code_written, 400)
      analytics.record_output(:explanations, 100)

      expect(analytics.total_output_tokens).to eq(500)
    end

    it 'returns zero when nothing recorded' do
      expect(analytics.total_output_tokens).to eq(0)
    end
  end

  describe '#total_tokens_saved' do
    it 'sums all savings features' do
      analytics.record_savings(:prompt_caching, 500)
      analytics.record_savings(:tool_filtering, 300)

      expect(analytics.total_tokens_saved).to eq(800)
    end

    it 'returns zero when nothing recorded' do
      expect(analytics.total_tokens_saved).to eq(0)
    end
  end

  describe '#report' do
    it 'generates a formatted string' do
      analytics.record_input(:system_prompt, 1000)
      analytics.record_output(:code_written, 500)
      analytics.record_turn!

      result = analytics.report
      expect(result).to include('Session:')
      expect(result).to include('1 turns')
      expect(result).to include('Input tokens:')
      expect(result).to include('Output tokens:')
      expect(result).to include('System prompt')
      expect(result).to include('Code written')
    end

    it 'includes savings section when savings are recorded' do
      analytics.record_savings(:prompt_caching, 500)
      result = analytics.report
      expect(result).to include('Savings applied:')
      expect(result).to include('Prompt caching')
    end

    it 'excludes savings section when no savings recorded' do
      result = analytics.report
      expect(result).not_to include('Savings applied:')
    end
  end

  describe '#session_minutes' do
    it 'returns elapsed time in minutes' do
      result = analytics.session_minutes
      expect(result).to be_a(Float)
      expect(result).to be >= 0.0
    end
  end

  describe '#record_turn!' do
    it 'increments the turn counter' do
      3.times { analytics.record_turn! }
      result = analytics.report
      expect(result).to include('3 turns')
    end
  end
end
