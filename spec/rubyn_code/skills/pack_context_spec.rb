# frozen_string_literal: true

require_relative 'skill_packs_spec_helper'

RSpec.describe RubynCode::Skills::PackContext do
  let(:registry_client) { instance_double('RubynCode::Skills::RegistryClient') }
  let(:context) { described_class.new(gems: gems, registry_client: registry_client) }

  describe '#matched_packs' do
    context 'with stripe gem' do
      let(:gems) { ['stripe'] }

      it 'maps stripe to stripe/webhooks' do
        expect(context.matched_packs).to contain_exactly('stripe/webhooks')
      end
    end

    context 'with sidekiq gem' do
      let(:gems) { ['sidekiq'] }

      it 'returns sidekiq directly' do
        expect(context.matched_packs).to contain_exactly('sidekiq')
      end
    end

    context 'with mixed gems' do
      let(:gems) { %w[stripe sidekiq devise] }

      it 'returns all pack names' do
        expect(context.matched_packs).to contain_exactly('stripe/webhooks', 'sidekiq', 'devise')
      end
    end

    context 'with no gems' do
      let(:gems) { [] }

      it 'returns empty array' do
        expect(context.matched_packs).to eq([])
      end
    end
  end

  describe '#build_context_block' do
    let(:gems) { ['stripe'] }

    it 'returns empty string when no gems matched' do
      empty_context = described_class.new(gems: [], registry_client: registry_client)
      expect(empty_context.build_context_block).to eq('')
    end

    it 'includes a "pack not found" fallback notice when registry fetch fails' do
      allow(registry_client).to receive(:fetch_pack).with('stripe/webhooks').and_raise(
        RubynCode::Skills::RegistryError.new('not found')
      )
      block = context.build_context_block
      expect(block).to include('stripe/webhooks')
      expect(block).to include('pack not found in registry')
      expect(block).not_to include('<skill')
    end

    it 'formats a valid pack into a context block' do
      pack_data = {
        name: 'stripe/webhooks',
        description: 'Stripe webhook patterns',
        files: {
          'webhooks.md' => {
            content: "# Stripe Webhooks\n\nAlways verify signatures."
          }
        }
      }

      allow(registry_client).to receive(:fetch_pack).with('stripe/webhooks').and_return(pack_data)

      block = context.build_context_block
      expect(block).to include('stripe/webhooks')
      expect(block).to include('<skill name=')
      expect(block).to include('</skill>')
    end

    it 'includes pack description when present' do
      pack_data = {
        name: 'stripe/webhooks',
        description: 'Stripe webhook patterns',
        files: { 'webhooks.md' => { content: '# Webhooks' } }
      }

      allow(registry_client).to receive(:fetch_pack).with('stripe/webhooks').and_return(pack_data)

      block = context.build_context_block
      expect(block).to include('Stripe webhook patterns')
    end
  end

  describe '.for_repo' do
    it 'reads Gemfile from project_root' do
      Dir.mktmpdir do |tmpdir|
        File.write(File.join(tmpdir, 'Gemfile'), "gem 'stripe'\ngem 'sidekiq'")

        context = described_class.for_repo(project_root: tmpdir)
        expect(context.gems).to contain_exactly('stripe', 'sidekiq')
      end
    end

    it 'returns empty gems when no Gemfile exists' do
      Dir.mktmpdir do |tmpdir|
        context = described_class.for_repo(project_root: tmpdir)
        expect(context.gems).to eq([])
      end
    end
  end
end
