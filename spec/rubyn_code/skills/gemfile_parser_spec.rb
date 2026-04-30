# frozen_string_literal: true

RSpec.describe RubynCode::Skills::GemfileParser do
  describe '.gems' do
    it 'extracts simple gem names' do
      content = <<~GEMFILE
        gem 'rails'
        gem 'puma'
      GEMFILE
      expect(described_class.gems(content)).to contain_exactly('rails', 'puma')
    end

    it 'handles gem names with version constraints' do
      content = <<~GEMFILE
        gem 'stripe', '~> 8.0'
        gem 'sidekiq', '>= 6.0'
      GEMFILE
      expect(described_class.gems(content)).to contain_exactly('stripe', 'sidekiq')
    end

    it 'handles double-quoted gem names' do
      content = 'gem "devise"'
      expect(described_class.gems(content)).to contain_exactly('devise')
    end

    it 'returns an empty array for empty content' do
      expect(described_class.gems('')).to eq([])
      expect(described_class.gems(nil)).to eq([])
      expect(described_class.gems("   \n")).to eq([])
    end

    it 'skips commented lines' do
      content = <<~GEMFILE
        # gem 'forbidden'
        gem 'stripe' # inline comment still captures
        # gem 'also_forbidden'
      GEMFILE
      expect(described_class.gems(content)).to contain_exactly('stripe')
    end

    it 'deduplicates gem names' do
      content = <<~GEMFILE
        gem 'stripe'
        gem 'stripe'
        gem 'puma'
      GEMFILE
      expect(described_class.gems(content)).to contain_exactly('stripe', 'puma')
    end

    it 'normalizes to lowercase' do
      content = "gem 'ActiveRecord'"
      expect(described_class.gems(content)).to contain_exactly('activerecord')
    end

    it 'handles gems with additional options' do
      content = <<~GEMFILE
        gem 'pundit', require: false
        gem 'sidekiq', group: :workers
        gem 'factory_bot_rails', platforms: [:ruby]
      GEMFILE
      expect(described_class.gems(content)).to contain_exactly('pundit', 'sidekiq', 'factory_bot_rails')
    end

    it 'ignores source declarations' do
      content = <<~GEMFILE
        source 'https://rubygems.org'
        gem 'rails'
      GEMFILE
      expect(described_class.gems(content)).to contain_exactly('rails')
    end
  end
end
