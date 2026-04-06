# frozen_string_literal: true

RSpec.describe RubynCode::Observability::SkillAnalytics do
  subject(:analytics) { described_class.new }

  describe '#record' do
    it 'adds an entry' do
      analytics.record(skill_name: 'deploy', loaded_at_turn: 1, tokens_cost: 500)
      expect(analytics.entries.size).to eq(1)
      expect(analytics.entries.first.skill_name).to eq('deploy')
    end

    it 'converts skill_name to string' do
      analytics.record(skill_name: :deploy, loaded_at_turn: 1)
      expect(analytics.entries.first.skill_name).to eq('deploy')
    end

    it 'defaults last_referenced_turn to loaded_at_turn' do
      analytics.record(skill_name: 'deploy', loaded_at_turn: 3)
      expect(analytics.entries.first.last_referenced_turn).to eq(3)
    end

    it 'accepts custom last_referenced_turn' do
      analytics.record(skill_name: 'deploy', loaded_at_turn: 1, last_referenced_turn: 5)
      expect(analytics.entries.first.last_referenced_turn).to eq(5)
    end
  end

  describe '#usage_stats' do
    it 'groups entries by skill name' do
      analytics.record(skill_name: 'deploy', loaded_at_turn: 1, tokens_cost: 500)
      analytics.record(skill_name: 'deploy', loaded_at_turn: 3, tokens_cost: 400)
      analytics.record(skill_name: 'review', loaded_at_turn: 2, tokens_cost: 300)

      stats = analytics.usage_stats
      expect(stats.keys).to contain_exactly('deploy', 'review')
      expect(stats['deploy'][:load_count]).to eq(2)
      expect(stats['deploy'][:total_tokens]).to eq(900)
      expect(stats['review'][:load_count]).to eq(1)
    end

    it 'calculates average tokens' do
      analytics.record(skill_name: 'deploy', loaded_at_turn: 1, tokens_cost: 500)
      analytics.record(skill_name: 'deploy', loaded_at_turn: 2, tokens_cost: 300)

      stats = analytics.usage_stats
      expect(stats['deploy'][:avg_tokens]).to eq(400)
    end

    it 'calculates acceptance rate' do
      analytics.record(skill_name: 'deploy', loaded_at_turn: 1, tokens_cost: 100, accepted: true)
      analytics.record(skill_name: 'deploy', loaded_at_turn: 2, tokens_cost: 100, accepted: false)

      stats = analytics.usage_stats
      expect(stats['deploy'][:acceptance_rate]).to eq(0.5)
    end

    it 'returns nil acceptance_rate when no entries are rated' do
      analytics.record(skill_name: 'deploy', loaded_at_turn: 1, tokens_cost: 100)

      stats = analytics.usage_stats
      expect(stats['deploy'][:acceptance_rate]).to be_nil
    end

    it 'returns empty hash when no entries recorded' do
      expect(analytics.usage_stats).to eq({})
    end
  end

  describe '#low_usage_skills' do
    it 'returns skills below the usage threshold' do
      20.times { analytics.record(skill_name: 'popular', loaded_at_turn: 1, tokens_cost: 100) }
      analytics.record(skill_name: 'rare', loaded_at_turn: 1, tokens_cost: 100)

      low = analytics.low_usage_skills(threshold: 0.1)
      expect(low).to include('rare')
      expect(low).not_to include('popular')
    end

    it 'returns empty array when no entries' do
      expect(analytics.low_usage_skills).to eq([])
    end
  end

  describe '#roi_ranking' do
    it 'returns skills sorted by ROI (acceptance rate per token)' do
      analytics.record(skill_name: 'efficient', loaded_at_turn: 1, tokens_cost: 100, accepted: true)
      analytics.record(skill_name: 'expensive', loaded_at_turn: 1, tokens_cost: 1000, accepted: true)

      ranking = analytics.roi_ranking
      expect(ranking.first).to eq('efficient')
    end

    it 'handles skills with no acceptance data' do
      analytics.record(skill_name: 'unrated', loaded_at_turn: 1, tokens_cost: 100)
      expect { analytics.roi_ranking }.not_to raise_error
    end
  end

  describe '#report' do
    it 'generates formatted string with skill data' do
      analytics.record(skill_name: 'deploy', loaded_at_turn: 1, tokens_cost: 500)
      analytics.record(skill_name: 'review', loaded_at_turn: 2, tokens_cost: 300)

      result = analytics.report
      expect(result).to include('Skill Usage:')
      expect(result).to include('deploy:')
      expect(result).to include('review:')
      expect(result).to include('500 tokens')
    end

    it 'returns a message when no data exists' do
      expect(analytics.report).to eq('No skill usage data.')
    end
  end
end
