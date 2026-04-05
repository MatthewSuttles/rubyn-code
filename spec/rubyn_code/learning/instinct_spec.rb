# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Learning::Instinct do
  let(:instinct) do
    described_class.new(
      id: 'inst-1',
      project_path: '/test',
      pattern: 'Always use guard clauses',
      confidence: 0.7,
      decay_rate: 0.05,
      times_applied: 3,
      times_helpful: 2,
      context_tags: %w[ruby style]
    )
  end

  it 'is a Data.define value object' do
    expect(instinct).to be_frozen
  end

  it 'clamps confidence between 0 and 1' do
    high = described_class.new(id: 'x', project_path: '/p', pattern: 'p', confidence: 5.0)
    low = described_class.new(id: 'y', project_path: '/p', pattern: 'p', confidence: -1.0)

    expect(high.confidence).to eq(1.0)
    expect(low.confidence).to eq(0.0)
  end

  it 'wraps context_tags in Array' do
    single = described_class.new(id: 'x', project_path: '/p', pattern: 'p', context_tags: 'ruby')
    expect(single.context_tags).to eq(['ruby'])
  end

  it 'coerces numeric fields' do
    inst = described_class.new(id: 'x', project_path: '/p', pattern: 'p',
                               times_applied: '5', times_helpful: '3', decay_rate: '0.1')
    expect(inst.times_applied).to eq(5)
    expect(inst.times_helpful).to eq(3)
    expect(inst.decay_rate).to eq(0.1)
  end
end

RSpec.describe RubynCode::Learning::InstinctMethods do
  let(:instinct) do
    RubynCode::Learning::Instinct.new(
      id: 'inst-1',
      project_path: '/test',
      pattern: 'Always use guard clauses',
      confidence: 0.7,
      decay_rate: 0.05,
      times_applied: 3,
      times_helpful: 2,
      updated_at: Time.now - (86_400 * 7) # 7 days ago
    )
  end

  describe '.apply_decay' do
    it 'reduces confidence based on elapsed time' do
      decayed = described_class.apply_decay(instinct, Time.now)
      expect(decayed.confidence).to be < instinct.confidence
    end

    it 'does not decay when no time has passed' do
      same_time = described_class.apply_decay(instinct, instinct.updated_at)
      expect(same_time.confidence).to eq(instinct.confidence)
    end

    it 'never drops below MIN_CONFIDENCE' do
      ancient = RubynCode::Learning::Instinct.new(
        id: 'old', project_path: '/p', pattern: 'p',
        confidence: 0.1, decay_rate: 1.0,
        updated_at: Time.now - (86_400 * 365)
      )
      decayed = described_class.apply_decay(ancient, Time.now)
      expect(decayed.confidence).to eq(described_class::MIN_CONFIDENCE)
    end
  end

  describe '.reinforce' do
    it 'increases confidence when helpful' do
      reinforced = described_class.reinforce(instinct, helpful: true)
      expect(reinforced.confidence).to be > instinct.confidence
      expect(reinforced.times_applied).to eq(4)
      expect(reinforced.times_helpful).to eq(3)
    end

    it 'decreases confidence when not helpful' do
      reinforced = described_class.reinforce(instinct, helpful: false)
      expect(reinforced.confidence).to be < instinct.confidence
      expect(reinforced.times_applied).to eq(4)
      expect(reinforced.times_helpful).to eq(2)
    end

    it 'applies diminishing returns on positive reinforcement' do
      high_conf = instinct.with(confidence: 0.95)
      reinforced = described_class.reinforce(high_conf, helpful: true)
      boost = reinforced.confidence - high_conf.confidence
      expect(boost).to be < 0.01 # small boost at high confidence
    end

    it 'never drops below MIN_CONFIDENCE' do
      low = instinct.with(confidence: described_class::MIN_CONFIDENCE)
      reinforced = described_class.reinforce(low, helpful: false)
      expect(reinforced.confidence).to eq(described_class::MIN_CONFIDENCE)
    end
  end

  describe '.confidence_label' do
    it 'returns near-certain for >= 0.9' do
      expect(described_class.confidence_label(0.95)).to eq('near-certain')
    end

    it 'returns confident for >= 0.7' do
      expect(described_class.confidence_label(0.75)).to eq('confident')
    end

    it 'returns moderate for >= 0.5' do
      expect(described_class.confidence_label(0.55)).to eq('moderate')
    end

    it 'returns tentative for >= 0.3' do
      expect(described_class.confidence_label(0.35)).to eq('tentative')
    end

    it 'returns unreliable below 0.3' do
      expect(described_class.confidence_label(0.1)).to eq('unreliable')
    end
  end

  describe '.reinforce_in_db' do
    it 'updates confidence and counters for helpful reinforcement' do
      db = setup_test_db_with_tables
      now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      sql = <<~SQL.tr("\n", ' ').strip
        INSERT INTO instincts
          (id, project_path, pattern, confidence, times_applied,
           times_helpful, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      db.execute(
        sql,
        ['inst-1', '/test', 'test pattern', 0.5, 2, 1, now, now]
      )

      described_class.reinforce_in_db('inst-1', db, helpful: true)

      row = db.query('SELECT * FROM instincts WHERE id = ?', ['inst-1']).first
      expect(row['confidence']).to be > 0.5
      expect(row['times_applied']).to eq(3)
      expect(row['times_helpful']).to eq(2)
    end

    it 'decreases confidence for unhelpful reinforcement' do
      db = setup_test_db_with_tables
      now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      sql = <<~SQL.tr("\n", ' ').strip
        INSERT INTO instincts
          (id, project_path, pattern, confidence, times_applied,
           times_helpful, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      db.execute(
        sql,
        ['inst-2', '/test', 'test pattern', 0.8, 5, 3, now, now]
      )

      described_class.reinforce_in_db('inst-2', db, helpful: false)

      row = db.query('SELECT * FROM instincts WHERE id = ?', ['inst-2']).first
      expect(row['confidence']).to be < 0.8
      expect(row['times_applied']).to eq(6)
      expect(row['times_helpful']).to eq(3)
    end
  end

  describe '.decay_all' do
    it 'removes instincts below MIN_CONFIDENCE after decay' do
      db = setup_test_db_with_tables
      old = (Time.now.utc - (86_400 * 365)).strftime('%Y-%m-%dT%H:%M:%SZ')

      sql = <<~SQL.tr("\n", ' ').strip
        INSERT INTO instincts
          (id, project_path, pattern, confidence, decay_rate,
           created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      db.execute(
        sql,
        ['stale', '/test', 'stale pattern', 0.06, 1.0, old, old]
      )

      described_class.decay_all(db, project_path: '/test')

      rows = db.query('SELECT * FROM instincts WHERE id = ?', ['stale'])
      expect(rows).to be_empty
    end

    it 'preserves instincts with high confidence' do
      db = setup_test_db_with_tables
      now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')

      sql = <<~SQL.tr("\n", ' ').strip
        INSERT INTO instincts
          (id, project_path, pattern, confidence, decay_rate,
           created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      SQL
      db.execute(
        sql,
        ['strong', '/test', 'strong pattern', 0.9, 0.01, now, now]
      )

      described_class.decay_all(db, project_path: '/test')

      rows = db.query('SELECT * FROM instincts WHERE id = ?', ['strong'])
      expect(rows).not_to be_empty
    end
  end
end
