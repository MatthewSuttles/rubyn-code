# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::LoadSkill do
  let(:project_root) { Dir.mktmpdir('load-skill-spec') }
  let(:skill_loader) { instance_double(RubynCode::Skills::Loader) }

  subject(:tool) { described_class.new(project_root: project_root, skill_loader: skill_loader) }

  after { FileUtils.rm_rf(project_root) }

  describe '.tool_name' do
    it 'returns load_skill' do
      expect(described_class.tool_name).to eq('load_skill')
    end
  end

  describe '.risk_level' do
    it 'is read-only' do
      expect(described_class.risk_level).to eq(:read)
    end
  end

  describe '.requires_confirmation?' do
    it 'does not require confirmation' do
      expect(described_class.requires_confirmation?).to be false
    end
  end

  describe '#execute' do
    context 'with a valid skill name' do
      it 'loads the skill through the loader' do
        allow(skill_loader).to receive(:load).with('adapter').and_return('Adapter skill content')

        result = tool.execute(name: 'adapter')
        expect(result).to eq('Adapter skill content')
      end
    end

    context 'when name has a leading slash' do
      it 'strips the leading slash before loading' do
        allow(skill_loader).to receive(:load).with('request-specs').and_return('Request specs skill')

        result = tool.execute(name: '/request-specs')
        expect(result).to eq('Request specs skill')
        expect(skill_loader).to have_received(:load).with('request-specs')
      end
    end

    context 'when name has multiple leading slashes' do
      it 'strips all leading slashes' do
        allow(skill_loader).to receive(:load).with('my-skill').and_return('content')

        result = tool.execute(name: '///my-skill')
        expect(result).to eq('content')
        expect(skill_loader).to have_received(:load).with('my-skill')
      end
    end

    context 'when name is empty' do
      it 'returns an error message' do
        result = tool.execute(name: '')
        expect(result).to eq('Error: skill name required')
      end
    end

    context 'when name is only slashes' do
      it 'returns an error message' do
        result = tool.execute(name: '///')
        expect(result).to eq('Error: skill name required')
      end
    end

    context 'when name is only whitespace' do
      it 'returns an error message' do
        result = tool.execute(name: '   ')
        expect(result).to eq('Error: skill name required')
      end
    end

    context 'when name is nil' do
      it 'returns an error message' do
        result = tool.execute(name: nil)
        expect(result).to eq('Error: skill name required')
      end
    end

    context 'when name has surrounding whitespace' do
      it 'strips whitespace before loading' do
        allow(skill_loader).to receive(:load).with('clean-name').and_return('loaded')

        result = tool.execute(name: '  clean-name  ')
        expect(result).to eq('loaded')
      end
    end

    context 'without an injected skill_loader' do
      subject(:tool_no_loader) { described_class.new(project_root: project_root) }

      it 'uses the default loader and raises for unknown skill' do
        expect { tool_no_loader.execute(name: 'nonexistent-skill-xyz') }
          .to raise_error(RubynCode::Error, /not found/i)
      end
    end
  end

  describe '.to_schema' do
    it 'returns a valid schema hash' do
      schema = described_class.to_schema
      expect(schema[:name]).to eq('load_skill')
      expect(schema[:description]).to include('skill')
      expect(schema[:input_schema]).to be_a(Hash)
    end
  end
end
