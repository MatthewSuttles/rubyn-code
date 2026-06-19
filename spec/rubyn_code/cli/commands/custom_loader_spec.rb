# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::CLI::Commands::CustomLoader do
  around do |example|
    Dir.mktmpdir do |project|
      Dir.mktmpdir do |home|
        @project = project
        @home = home
        example.run
      end
    end
  end

  def write_command(dir, name, content)
    path = File.join(dir, '.rubyn-code', 'commands')
    path = File.join(@home, 'commands') if dir == @home
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "#{name}.md"), content)
  end

  def load
    described_class.load_all(project_root: @project, home_dir: @home)
  end

  it 'loads a project command file as a slash command' do
    write_command(@project, 'deploy', "---\ndescription: Ship it\n---\nDeploy now: $ARGUMENTS")

    commands = load
    expect(commands.size).to eq(1)
    expect(commands.first.command_name).to eq('/deploy')
    expect(commands.first.description).to eq('Ship it')
  end

  it 'falls back to the first line for the description when no frontmatter' do
    write_command(@project, 'triage', "# Triage the inbox\nDo the thing")
    expect(load.first.description).to eq('Triage the inbox')
  end

  it 'loads user-global commands too' do
    write_command(@home, 'note', 'Take a note')
    expect(load.map(&:command_name)).to include('/note')
  end

  it 'lets a project command override a user command of the same name' do
    write_command(@home, 'dup', 'USER version')
    write_command(@project, 'dup', 'PROJECT version')

    dups = load.select { |c| c.command_name == '/dup' }
    expect(dups.size).to eq(1)
    expect(dups.first.source).to start_with(@project)
  end

  it 'ignores files with unsafe names' do
    dir = File.join(@project, '.rubyn-code', 'commands')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, '../evil.md'), 'nope') if false # guarded
    File.write(File.join(dir, ' .md'), 'blank name')
    expect(load).to be_empty
  end

  it 'returns nothing when no command dirs exist' do
    expect(load).to be_empty
  end
end
