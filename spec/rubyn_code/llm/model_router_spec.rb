# frozen_string_literal: true

RSpec.describe RubynCode::LLM::ModelRouter do
  describe '.tier_for' do
    it 'returns :cheap for file_search' do
      expect(described_class.tier_for(:file_search)).to eq(:cheap)
    end

    it 'returns :cheap for other cheap tasks' do
      %i[spec_summary schema_lookup format_code git_operations memory_retrieval context_summary].each do |task|
        expect(described_class.tier_for(task)).to eq(:cheap)
      end
    end

    it 'returns :mid for generate_specs' do
      expect(described_class.tier_for(:generate_specs)).to eq(:mid)
    end

    it 'returns :mid for other mid tasks' do
      %i[simple_refactor code_review documentation bug_fix explore].each do |task|
        expect(described_class.tier_for(task)).to eq(:mid)
      end
    end

    it 'returns :top for architecture' do
      expect(described_class.tier_for(:architecture)).to eq(:top)
    end

    it 'returns :top for other top tasks' do
      %i[complex_refactor security_review performance planning].each do |task|
        expect(described_class.tier_for(task)).to eq(:top)
      end
    end

    it 'returns :mid for unknown tasks' do
      expect(described_class.tier_for(:something_unknown)).to eq(:mid)
    end
  end

  describe '.model_for' do
    it 'returns the first preferred model for a task tier' do
      expect(described_class.model_for(:file_search)).to eq('claude-haiku-4-5')
    end

    it 'returns a top-tier model for architecture tasks' do
      expect(described_class.model_for(:architecture)).to eq('claude-opus-4-6')
    end

    it 'filters by available_models when provided' do
      result = described_class.model_for(:file_search, available_models: ['gpt-4o-mini-2024'])
      expect(result).to eq('gpt-4o-mini')
    end

    it 'falls back to first preferred when no available models match' do
      result = described_class.model_for(:file_search, available_models: ['nonexistent-model'])
      expect(result).to eq('claude-haiku-4-5')
    end

    it 'returns first preferred when available_models is empty' do
      result = described_class.model_for(:generate_specs, available_models: [])
      expect(result).to eq('claude-sonnet-4-6')
    end
  end

  describe '.resolve' do
    it 'returns provider and model hash for a task type' do
      result = described_class.resolve(:file_search)
      expect(result).to eq({ provider: 'anthropic', model: 'claude-haiku-4-5' })
    end

    it 'returns top-tier provider and model for architecture' do
      result = described_class.resolve(:architecture)
      expect(result).to eq({ provider: 'anthropic', model: 'claude-opus-4-6' })
    end

    it 'returns mid-tier for unknown tasks' do
      result = described_class.resolve(:something_random)
      expect(result).to eq({ provider: 'anthropic', model: 'claude-sonnet-4-6' })
    end
  end

  describe '.detect_task' do
    context 'from messages' do
      it 'detects architecture tasks' do
        expect(described_class.detect_task('restructure the entire app')).to eq(:architecture)
      end

      it 'detects security_review tasks' do
        expect(described_class.detect_task('check for security vulnerabilities')).to eq(:security_review)
      end

      it 'detects performance tasks' do
        expect(described_class.detect_task('fix N+1 queries')).to eq(:performance)
      end

      it 'detects generate_specs tasks' do
        expect(described_class.detect_task('write rspec tests')).to eq(:generate_specs)
      end

      it 'detects bug_fix tasks' do
        expect(described_class.detect_task('fix this bug')).to eq(:bug_fix)
      end

      it 'detects file_search tasks' do
        expect(described_class.detect_task('find the user model')).to eq(:file_search)
      end

      it 'detects simple_refactor tasks' do
        expect(described_class.detect_task('refactor this method')).to eq(:simple_refactor)
      end

      it 'detects documentation tasks' do
        expect(described_class.detect_task('explain this code in a doc')).to eq(:documentation)
      end

      it 'returns :explore for generic messages' do
        expect(described_class.detect_task('hello world')).to eq(:explore)
      end
    end

    context 'from tools' do
      it 'detects file_search from grep tool' do
        expect(described_class.detect_task('hello', recent_tools: ['grep'])).to eq(:file_search)
      end

      it 'detects generate_specs from run_specs tool' do
        expect(described_class.detect_task('hello', recent_tools: ['run_specs'])).to eq(:generate_specs)
      end

      it 'detects code_review from review_pr tool' do
        expect(described_class.detect_task('hello', recent_tools: ['review_pr'])).to eq(:code_review)
      end

      it 'detects git_operations from git tools' do
        expect(described_class.detect_task('hello', recent_tools: ['git_status'])).to eq(:git_operations)
      end
    end
  end

  describe '.cost_multiplier' do
    it 'returns 0.07 for :cheap' do
      expect(described_class.cost_multiplier(:cheap)).to eq(0.07)
    end

    it 'returns 0.20 for :mid' do
      expect(described_class.cost_multiplier(:mid)).to eq(0.20)
    end

    it 'returns 1.0 for :top' do
      expect(described_class.cost_multiplier(:top)).to eq(1.0)
    end

    it 'returns 0.20 for unknown tiers' do
      expect(described_class.cost_multiplier(:unknown)).to eq(0.20)
    end
  end
end
