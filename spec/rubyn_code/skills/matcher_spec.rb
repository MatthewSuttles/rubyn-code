# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe RubynCode::Skills::Matcher do
  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) }

  let(:catalog) { RubynCode::Skills::Catalog.new(tmpdir) }
  let(:project_root) { tmpdir }

  subject(:matcher) { described_class.new(catalog: catalog, project_root: project_root) }

  def write_skill(name, triggers: [], gems: [], rails_constraint: nil)
    fm = +"---\nname: #{name}\ndescription: #{name} skill\n"
    fm << "triggers:\n#{triggers.map { |t| "  - \"#{t}\"" }.join("\n")}\n" if triggers.any?
    fm << "gems:\n#{gems.map { |g| "  - #{g}" }.join("\n")}\n" if gems.any?
    fm << "rails: \"#{rails_constraint}\"\n" if rails_constraint
    fm << "---\nBody.\n"
    File.write(File.join(tmpdir, "#{name}.md"), fm)
  end

  def write_gemfile(gems)
    File.write(File.join(tmpdir, 'Gemfile'),
               gems.map { |g| "gem '#{g}'" }.join("\n"))
  end

  describe '#match' do
    it 'returns no matches for an empty message' do
      write_skill('a', triggers: ['turbo'])
      expect(matcher.match('')).to be_empty
    end

    it 'returns no matches when no trigger fires' do
      write_skill('a', triggers: ['turbo'])
      expect(matcher.match('how do I write a service object')).to be_empty
    end

    it 'matches a single skill by substring on a trigger' do
      write_skill('turbo-drive', triggers: ['turbo drive', 'page navigation'])
      result = matcher.match('I want to set up turbo drive')
      expect(result.map { |e| e[:name] }).to eq(['turbo-drive'])
    end

    it 'is case-insensitive on both sides' do
      write_skill('turbo-drive', triggers: ['Turbo Drive'])
      result = matcher.match('TURBO drive please')
      expect(result.map { |e| e[:name] }).to eq(['turbo-drive'])
    end

    it 'returns multiple matches when several skills fire' do
      write_skill('turbo-drive', triggers: ['turbo drive'])
      write_skill('stimulus', triggers: ['stimulus controller'])
      result = matcher.match('combine turbo drive with stimulus controller')
      expect(result.map { |e| e[:name] }).to contain_exactly('turbo-drive', 'stimulus')
    end

    it 'skips skills with no triggers' do
      write_skill('a', triggers: [])
      expect(matcher.match('anything')).to be_empty
    end
  end

  describe 'per-session dedup' do
    it 'returns a skill only once across calls' do
      write_skill('turbo-drive', triggers: ['turbo drive'])
      first = matcher.match('turbo drive')
      second = matcher.match('turbo drive again')
      expect(first.map { |e| e[:name] }).to eq(['turbo-drive'])
      expect(second).to be_empty
    end

    it 'exposes loaded names' do
      write_skill('turbo-drive', triggers: ['turbo drive'])
      matcher.match('turbo drive')
      expect(matcher.loaded).to eq(['turbo-drive'])
    end
  end

  describe 'gem gating' do
    it 'gates skills whose gems are not in the Gemfile' do
      write_skill('devise-skill', triggers: ['devise'], gems: ['devise'])
      write_gemfile(['rails'])
      expect(matcher.match('devise question')).to be_empty
    end

    it 'allows skills whose gems are present in the Gemfile' do
      write_skill('devise-skill', triggers: ['devise'], gems: ['devise'])
      write_gemfile(['devise', 'rails'])
      result = matcher.match('devise question')
      expect(result.map { |e| e[:name] }).to eq(['devise-skill'])
    end

    it 'allows skills with no gem dependencies even without a Gemfile' do
      write_skill('plain', triggers: ['foo'])
      result = matcher.match('please foo this')
      expect(result.map { |e| e[:name] }).to eq(['plain'])
    end

    it 'skips gem gating entirely when there is no Gemfile' do
      write_skill('devise-skill', triggers: ['devise'], gems: ['devise'])
      result = matcher.match('devise question')
      expect(result.map { |e| e[:name] }).to eq(['devise-skill'])
    end

    it 'requires every gem in the skill to be present' do
      write_skill('multi', triggers: ['multi'], gems: %w[devise jwt])
      write_gemfile(['devise'])
      expect(matcher.match('multi please')).to be_empty
    end
  end
end
