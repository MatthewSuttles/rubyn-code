# frozen_string_literal: true

RSpec.describe RubynCode::Skills::TtlManager do
  subject(:manager) { described_class.new }

  describe '#register' do
    it 'stores an entry with token count' do
      manager.register('deploy', 'Deploy steps here')
      expect(manager.entries).to have_key('deploy')
      expect(manager.entries['deploy'].token_count).to be > 0
    end

    it 'returns the content unchanged when within size cap' do
      content = 'Short content'
      result = manager.register('small_skill', content)
      expect(result).to eq(content)
    end

    it 'truncates content exceeding MAX_SKILL_TOKENS' do
      long_content = 'a' * (described_class::MAX_SKILL_TOKENS * described_class::CHARS_PER_TOKEN + 100)
      result = manager.register('large_skill', long_content)
      expect(result).to include('[skill truncated to 800 tokens]')
      expect(result.length).to be < long_content.length
    end

    it 'records the current turn as loaded_at_turn' do
      manager.tick!
      manager.tick!
      manager.register('skill', 'content')
      expect(manager.entries['skill'].loaded_at_turn).to eq(2)
    end

    it 'allows custom TTL override' do
      manager.register('custom', 'content', ttl: 10)
      expect(manager.entries['custom'].ttl).to eq(10)
    end
  end

  describe '#tick!' do
    it 'advances the turn counter' do
      manager.register('skill', 'content')
      5.times { manager.tick! }
      expect(manager.stats[:current_turn]).to eq(5)
    end
  end

  describe '#touch' do
    it 'resets last_referenced_turn to current turn' do
      manager.register('skill', 'content')
      3.times { manager.tick! }
      manager.touch('skill')
      expect(manager.entries['skill'].last_referenced_turn).to eq(3)
    end

    it 'does nothing for nonexistent skills' do
      expect { manager.touch('nonexistent') }.not_to raise_error
    end
  end

  describe '#expired_skills' do
    it 'returns skills past their TTL' do
      manager.register('old_skill', 'content', ttl: 2)
      3.times { manager.tick! }
      expect(manager.expired_skills).to include('old_skill')
    end

    it 'does not return skills within TTL' do
      manager.register('fresh_skill', 'content', ttl: 10)
      2.times { manager.tick! }
      expect(manager.expired_skills).not_to include('fresh_skill')
    end

    it 'does not return recently touched skills' do
      manager.register('touched_skill', 'content', ttl: 2)
      2.times { manager.tick! }
      manager.touch('touched_skill')
      manager.tick!
      expect(manager.expired_skills).not_to include('touched_skill')
    end
  end

  describe '#eject_expired!' do
    it 'removes expired skills and returns their names' do
      manager.register('expired', 'content', ttl: 1)
      manager.register('fresh', 'content', ttl: 10)
      2.times { manager.tick! }

      ejected = manager.eject_expired!
      expect(ejected).to include('expired')
      expect(ejected).not_to include('fresh')
      expect(manager.entries).not_to have_key('expired')
      expect(manager.entries).to have_key('fresh')
    end

    it 'returns empty array when nothing expired' do
      manager.register('fresh', 'content', ttl: 10)
      expect(manager.eject_expired!).to be_empty
    end
  end

  describe '#total_tokens' do
    it 'sums token counts of all entries' do
      manager.register('a', 'content one')
      manager.register('b', 'content two')
      expect(manager.total_tokens).to eq(
        manager.entries['a'].token_count + manager.entries['b'].token_count
      )
    end

    it 'returns zero when no entries' do
      expect(manager.total_tokens).to eq(0)
    end
  end

  describe '#stats' do
    it 'returns correct values' do
      manager.register('a', 'content', ttl: 1)
      manager.register('b', 'more content', ttl: 10)
      2.times { manager.tick! }

      stats = manager.stats
      expect(stats[:loaded_skills]).to eq(2)
      expect(stats[:total_tokens]).to eq(manager.total_tokens)
      expect(stats[:expired]).to eq(1)
      expect(stats[:current_turn]).to eq(2)
    end
  end
end
