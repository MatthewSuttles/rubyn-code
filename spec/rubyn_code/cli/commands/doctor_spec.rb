# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Doctor do
  subject(:command) { described_class.new }

  let(:project_root) { Dir.mktmpdir('rubyn_doctor_') }
  let(:renderer) { instance_double(RubynCode::CLI::Renderer, info: nil, success: nil, warning: nil) }
  let(:db) { instance_double('DB::Connection') }
  let(:catalog) do
    instance_double('Skills::Catalog', list: %w[ruby rails rspec], available: available_skills,
                                       skills_dirs: [])
  end
  let(:available_skills) do
    [{ name: 'ruby', description: 'Ruby basics', tags: [], path: '/skills/ruby.md' },
     { name: 'rails', description: 'Rails basics', tags: [], path: '/skills/rails.md' },
     { name: 'rspec', description: 'RSpec basics', tags: [], path: '/skills/rspec.md' }]
  end
  let(:skill_loader) { instance_double('Skills::Loader', catalog: catalog) }

  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      db: db,
      project_root: project_root,
      skill_loader: skill_loader
    )
  end

  after { FileUtils.rm_rf(project_root) }

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/doctor') }
  end

  describe '.description' do
    it { expect(described_class.description).to eq('Environment health check') }
  end

  describe '#execute' do
    before do
      allow(db).to receive(:query).and_return([{ 'c' => 10 }])
      allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(true)
      allow(RubynCode::Auth::TokenStore).to receive(:load).and_return({ source: :api_key })
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

    context 'MCP connectivity check' do
      it 'reports mcp.json not found when file missing' do
        expect { command.execute([], ctx) }.to output(/MCP connectivity.*mcp\.json not found/).to_stdout
      end

      it 'reports servers reachable when mcp.json present' do
        mcp_dir = File.join(project_root, '.rubyn-code')
        FileUtils.mkdir_p(mcp_dir)
        mcp_config = {
          'mcpServers' => {
            'test-server' => { 'command' => 'echo', 'args' => [] }
          }
        }
        File.write(File.join(mcp_dir, 'mcp.json'), JSON.generate(mcp_config))

        expect { command.execute([], ctx) }.to output(%r{MCP connectivity.*1/1 servers reachable}).to_stdout
      end
    end

    context 'Codebase index check' do
      it 'reports index not found when file missing' do
        expect { command.execute([], ctx) }.to output(/Codebase index.*index not found/).to_stdout
      end

      it 'reports index age when file exists' do
        index_dir = File.join(project_root, '.rubyn-code')
        FileUtils.mkdir_p(index_dir)
        File.write(File.join(index_dir, 'codebase_index.json'), '{}')

        expect { command.execute([], ctx) }.to output(/Codebase index.*0\.0h old/).to_stdout
      end
    end

    context 'Skill catalog health check' do
      it 'reports skill catalog status' do
        expect { command.execute([], ctx) }.to output(/Skill catalog.*3 skills loaded/).to_stdout
      end

      it 'reports no skills found when catalog is empty' do
        allow(catalog).to receive(:available).and_return([])
        expect { command.execute([], ctx) }.to output(/Skill catalog.*no skills found/).to_stdout
      end
    end
  end
end
