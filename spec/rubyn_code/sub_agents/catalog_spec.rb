# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::SubAgents::Catalog do
  around do |example|
    Dir.mktmpdir do |project|
      Dir.mktmpdir do |home|
        @project = project
        @home = home
        example.run
      end
    end
  end

  def catalog
    described_class.new(project_root: @project, home_dir: @home)
  end

  def write_agent(name, content)
    dir = File.join(@project, '.rubyn-code', 'agents')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{name}.md"), content)
  end

  describe 'built-ins' do
    it 'always provides explore and worker' do
      expect(catalog.get('explore').read_only?).to be(true)
      expect(catalog.get('worker').read_only?).to be(false)
    end

    it 'falls back to nil for an unknown type' do
      expect(catalog.get('nope')).to be_nil
    end
  end

  describe 'custom agents' do
    it 'loads a custom agent with prompt, tools, and access from frontmatter' do
      write_agent('reviewer', <<~MD)
        ---
        description: Reviews a diff
        tools: read_file, grep
        access: read
        ---
        You are a meticulous code reviewer.
      MD

      agent = catalog.get('reviewer')
      expect(agent.description).to eq('Reviews a diff')
      expect(agent.tool_names).to eq(%w[read_file grep])
      expect(agent.read_only?).to be(true)
      expect(agent.system_prompt).to include('meticulous code reviewer')
      expect(agent).to be_custom
    end

    it 'defaults to write access and a generated description when omitted' do
      write_agent('builder', 'Build things.')
      agent = catalog.get('builder')
      expect(agent.read_only?).to be(false)
      expect(agent.description).to include('builder')
    end

    it 'derives the name from the filename when frontmatter omits it' do
      write_agent('tidy', "---\ndescription: x\n---\nbody")
      expect(catalog.get('tidy')).not_to be_nil
    end

    it 'cannot override the built-in explore/worker names' do
      write_agent('explore', "---\naccess: write\n---\nhijack")
      expect(catalog.get('explore').read_only?).to be(true)
    end

    it 'lists custom names' do
      write_agent('reviewer', 'Review')
      expect(catalog.custom_names).to include('reviewer')
    end
  end
end
