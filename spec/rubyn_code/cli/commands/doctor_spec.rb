# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Doctor do
  subject(:command) { described_class.new }

  let(:renderer) { instance_double(RubynCode::CLI::Renderer, info: nil, success: nil, warning: nil) }
  let(:db) { instance_double('DB::Connection') }
  let(:catalog) { instance_double('Skills::Catalog', list: %w[ruby rails rspec]) }
  let(:skill_loader) { instance_double('Skills::Loader', catalog: catalog) }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      db: db,
      project_root: Dir.pwd,
      skill_loader: skill_loader
    )
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/doctor') }
  end

  describe '.description' do
    it { expect(described_class.description).to eq('Environment health check') }
  end

  describe '#execute' do
    before do
      allow(db).to receive(:query).and_return([{ 'c' => 10 }])
      allow(RubynCode::Auth::TokenStore).to receive(:valid_for?).with('anthropic').and_return(true)
      allow(RubynCode::Auth::TokenStore).to receive(:load_for_provider).with('anthropic').and_return({ source: :api_key })
    end

    it 'runs all health checks without raising' do
      expect { command.execute([], ctx) }.to output(/✓/).to_stdout
    end

    it 'checks Ruby version' do
      expect { command.execute([], ctx) }.to output(/Ruby version/).to_stdout
    end

    it 'checks database connectivity' do
      expect { command.execute([], ctx) }.to output(/Database/).to_stdout
    end

    it 'checks authentication' do
      expect { command.execute([], ctx) }.to output(/Authentication/).to_stdout
    end

    it 'checks skills availability' do
      expect { command.execute([], ctx) }.to output(/Skills/).to_stdout
    end

    it 'reports failure for bad database' do
      allow(db).to receive(:query).and_raise(StandardError.new('connection failed'))
      expect { command.execute([], ctx) }.to output(/✗.*Database/).to_stdout
    end
  end
end
