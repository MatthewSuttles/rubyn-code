# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::CLI::Commands::Agents do
  subject(:command) { described_class.new }

  let(:renderer) { instance_double('Renderer', info: nil, error: nil) }

  around do |example|
    Dir.mktmpdir do |dir|
      @project = dir
      example.run
    end
  end

  let(:ctx) do
    instance_double(RubynCode::CLI::Commands::Context, renderer: renderer, project_root: @project)
  end

  it 'lists the built-in agent types' do
    expect { command.execute([], ctx) }.to output(/explore.*built-in.*read-only/m).to_stdout
  end

  it 'includes custom agents from .rubyn-code/agents' do
    dir = File.join(@project, '.rubyn-code', 'agents')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'reviewer.md'), "---\ndescription: Reviews code\n---\nReview it.")

    expect { command.execute([], ctx) }.to output(/reviewer.*custom.*Reviews code/m).to_stdout
  end
end
