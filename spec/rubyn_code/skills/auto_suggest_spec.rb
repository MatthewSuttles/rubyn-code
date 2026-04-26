# frozen_string_literal: true

require_relative 'skill_packs_spec_helper'
require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe RubynCode::Skills::AutoSuggest do
  let(:tmpdir) { Dir.mktmpdir('rubyn_suggest_test_') }
  let(:registry_client) { instance_double(RubynCode::Skills::RegistryClient) }
  subject(:suggest) do
    described_class.new(project_root: tmpdir, registry_client: registry_client)
  end

  after { FileUtils.remove_entry(tmpdir) }

  def write_gemfile(content)
    File.write(File.join(tmpdir, 'Gemfile'), content)
  end

  def state_path
    File.join(tmpdir, '.rubyn-code', 'suggested.json')
  end

  def write_state(state)
    dir = File.dirname(state_path)
    FileUtils.mkdir_p(dir)
    File.write(state_path, JSON.pretty_generate(state))
  end

  def read_state
    JSON.parse(File.read(state_path))
  end

  describe '#check' do
    context 'with a Gemfile containing known gems' do
      before do
        write_gemfile(<<~GEMFILE)
          source 'https://rubygems.org'

          gem 'rails', '~> 7.1'
          gem 'stripe'
          gem 'sidekiq', '~> 7.0'
          gem 'puma'
        GEMFILE

        allow(registry_client).to receive(:fetch_suggestions)
          .with(array_including('stripe', 'sidekiq'))
          .and_return([
                        { 'name' => 'stripe', 'reason' => 'stripe gem detected in Gemfile' },
                        { 'name' => 'sidekiq', 'reason' => 'sidekiq gem detected in Gemfile' }
                      ])
      end

      it 'returns a suggestion message' do
        message = suggest.check

        expect(message).to include('stripe')
        expect(message).to include('sidekiq')
        expect(message).to include('/install-skills')
      end

      it 'records shown suggestions in state file' do
        suggest.check

        state = read_state
        expect(state['shown']).to include('stripe', 'sidekiq')
      end

      it 'does not repeat suggestions already shown' do
        write_state({ 'shown' => %w[stripe sidekiq] })

        message = suggest.check

        expect(message).to be_nil
      end
    end

    context 'Gemfile parsing' do
      it 'parses single-quoted gem names' do
        write_gemfile("gem 'devise'\n")

        allow(registry_client).to receive(:fetch_suggestions)
          .with(['devise'])
          .and_return([{ 'name' => 'devise', 'reason' => 'devise gem detected' }])

        message = suggest.check
        expect(message).to include('devise')
      end

      it 'parses double-quoted gem names' do
        write_gemfile("gem \"devise\"\n")

        allow(registry_client).to receive(:fetch_suggestions)
          .with(['devise'])
          .and_return([{ 'name' => 'devise', 'reason' => 'devise gem detected' }])

        message = suggest.check
        expect(message).to include('devise')
      end

      it 'parses gems with version constraints' do
        write_gemfile("gem 'stripe', '~> 5.0'\n")

        allow(registry_client).to receive(:fetch_suggestions)
          .with(['stripe'])
          .and_return([{ 'name' => 'stripe', 'reason' => 'stripe gem detected' }])

        message = suggest.check
        expect(message).to include('stripe')
      end

      it 'deduplicates gem names' do
        write_gemfile("gem 'stripe'\ngem 'stripe'\n")

        allow(registry_client).to receive(:fetch_suggestions)
          .with(['stripe'])
          .and_return([{ 'name' => 'stripe', 'reason' => 'stripe gem detected' }])

        message = suggest.check
        expect(message).to include('stripe')
      end

      it 'ignores commented-out gems' do
        write_gemfile("# gem 'stripe'\ngem 'sidekiq'\n")

        allow(registry_client).to receive(:fetch_suggestions)
          .with(['sidekiq'])
          .and_return([{ 'name' => 'sidekiq', 'reason' => 'sidekiq gem detected' }])

        message = suggest.check
        expect(message).to include('sidekiq')
        expect(message).not_to include('stripe')
      end
    end

    context 'when no Gemfile exists' do
      it 'returns nil' do
        expect(suggest.check).to be_nil
      end
    end

    context 'when Gemfile has no matching packs' do
      before do
        write_gemfile("gem 'rails'\ngem 'puma'\n")

        allow(registry_client).to receive(:fetch_suggestions)
          .and_return([])
      end

      it 'returns nil' do
        expect(suggest.check).to be_nil
      end
    end

    context 'when all suggestions have been dismissed' do
      before do
        write_gemfile("gem 'stripe'\n")
        write_state({ 'dismissed' => ['stripe'] })

        allow(registry_client).to receive(:fetch_suggestions)
          .and_return([{ 'name' => 'stripe', 'reason' => 'stripe gem detected' }])
      end

      it 'returns nil' do
        expect(suggest.check).to be_nil
      end
    end

    context 'when all suggestions have been installed' do
      before do
        write_gemfile("gem 'stripe'\n")
        write_state({ 'installed' => ['stripe'] })

        allow(registry_client).to receive(:fetch_suggestions)
          .and_return([{ 'name' => 'stripe', 'reason' => 'stripe gem detected' }])
      end

      it 'returns nil' do
        expect(suggest.check).to be_nil
      end
    end

    context 'when registry is unreachable' do
      before do
        write_gemfile("gem 'stripe'\n")

        allow(registry_client).to receive(:fetch_suggestions)
          .and_raise(RubynCode::Skills::RegistryError, 'Connection refused')
      end

      it 'returns nil without raising' do
        expect(suggest.check).to be_nil
      end
    end

    context 'when an unexpected error occurs' do
      before do
        write_gemfile("gem 'stripe'\n")

        allow(registry_client).to receive(:fetch_suggestions)
          .and_raise(StandardError, 'something broke')
      end

      it 'returns nil without raising' do
        expect(suggest.check).to be_nil
      end
    end
  end

  describe '#mark_installed' do
    it 'records the pack as installed in state' do
      suggest.mark_installed('stripe')

      state = read_state
      expect(state['installed']).to include('stripe')
    end

    it 'does not duplicate entries' do
      suggest.mark_installed('stripe')
      suggest.mark_installed('stripe')

      state = read_state
      expect(state['installed'].count('stripe')).to eq(1)
    end

    it 'creates the state directory if needed' do
      expect(Dir.exist?(File.dirname(state_path))).to be false

      suggest.mark_installed('stripe')

      expect(File.exist?(state_path)).to be true
    end
  end

  describe '#mark_dismissed' do
    it 'records the pack as dismissed in state' do
      suggest.mark_dismissed('stripe')

      state = read_state
      expect(state['dismissed']).to include('stripe')
    end

    it 'does not duplicate entries' do
      suggest.mark_dismissed('stripe')
      suggest.mark_dismissed('stripe')

      state = read_state
      expect(state['dismissed'].count('stripe')).to eq(1)
    end
  end

  describe 'interaction between shown, installed, and dismissed' do
    before do
      write_gemfile("gem 'stripe'\ngem 'sidekiq'\ngem 'devise'\n")
    end

    it 'filters out shown, installed, and dismissed packs' do
      write_state({
                    'shown' => ['stripe'],
                    'installed' => ['sidekiq'],
                    'dismissed' => []
                  })

      allow(registry_client).to receive(:fetch_suggestions)
        .and_return([
                      { 'name' => 'stripe', 'reason' => 'stripe gem detected' },
                      { 'name' => 'sidekiq', 'reason' => 'sidekiq gem detected' },
                      { 'name' => 'devise', 'reason' => 'devise gem detected' }
                    ])

      message = suggest.check

      expect(message).to include('devise')
      expect(message).not_to include('stripe')
      expect(message).not_to include('sidekiq')
    end
  end

  describe 'corrupted state file' do
    before do
      write_gemfile("gem 'stripe'\n")
      FileUtils.mkdir_p(File.dirname(state_path))
      File.write(state_path, 'not json')

      allow(registry_client).to receive(:fetch_suggestions)
        .and_return([{ 'name' => 'stripe', 'reason' => 'stripe gem detected' }])
    end

    it 'treats corrupted state as empty and still suggests' do
      message = suggest.check
      expect(message).to include('stripe')
    end
  end
end
