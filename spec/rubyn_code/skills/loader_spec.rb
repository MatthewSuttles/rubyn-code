# frozen_string_literal: true

require 'tempfile'

RSpec.describe RubynCode::Skills::Loader do
  let(:catalog) { instance_double(RubynCode::Skills::Catalog) }
  let(:tmpfile) { Tempfile.new(['skill', '.md']) }

  subject(:loader) { described_class.new(catalog) }

  before do
    tmpfile.write(<<~MD)
      ---
      name: commit
      description: Create a commit
      tags: [git]
      ---
      Commit instructions here.
    MD
    tmpfile.flush
  end

  after { tmpfile.close! }

  describe '#load' do
    it 'returns content wrapped in skill tags' do
      allow(catalog).to receive(:find).with('commit').and_return(tmpfile.path)

      content = loader.load('commit')
      expect(content).to include('<skill name="commit">')
      expect(content).to include('</skill>')
      expect(content).to include('Commit instructions here.')
    end

    it 'caches loaded skills' do
      allow(catalog).to receive(:find).with('commit').and_return(tmpfile.path)

      loader.load('commit')
      loader.load('commit')

      expect(catalog).to have_received(:find).once
    end

    it 'raises when skill is not found' do
      allow(catalog).to receive(:find).with('missing').and_return(nil)

      expect { loader.load('missing') }.to raise_error(RubynCode::Error, /not found/)
    end
  end

  describe '#loaded' do
    it 'tracks loaded skill names' do
      allow(catalog).to receive(:find).with('commit').and_return(tmpfile.path)

      loader.load('commit')
      expect(loader.loaded).to eq(['commit'])
    end
  end

  describe '#suggest_skills' do
    def build_index(nodes: [], edges: [])
      idx = instance_double(RubynCode::Index::CodebaseIndex)
      allow(idx).to receive(:nodes).and_return(nodes)
      allow(idx).to receive(:edges).and_return(edges)
      idx
    end

    it 'returns empty array when no index is provided' do
      expect(loader.suggest_skills).to eq([])
    end

    it 'returns empty array when index is nil' do
      expect(loader.suggest_skills(codebase_index: nil)).to eq([])
    end

    it 'suggests authentication when Devise classes are present' do
      index = build_index(nodes: [
                            { 'type' => 'class', 'name' => 'Devise::SessionsController', 'file' => 'app/controllers/devise/sessions_controller.rb' }
                          ])
      result = loader.suggest_skills(codebase_index: index)
      expect(result).to include('authentication')
    end

    it 'suggests authentication when devise config files are present' do
      index = build_index(nodes: [
                            { 'type' => 'class', 'name' => 'User', 'file' => 'config/initializers/devise.rb' }
                          ])
      result = loader.suggest_skills(codebase_index: index)
      expect(result).to include('authentication')
    end

    it 'suggests mailer when ActionMailer classes are present' do
      index = build_index(nodes: [
                            { 'type' => 'class', 'name' => 'UserMailer', 'file' => 'app/mailers/user_mailer.rb' }
                          ])
      result = loader.suggest_skills(codebase_index: index)
      expect(result).to include('mailer')
    end

    it 'suggests mailer when mailer directory files are present' do
      index = build_index(nodes: [
                            { 'type' => 'class', 'name' => 'ApplicationMailer',
                              'file' => 'app/mailers/application_mailer.rb' }
                          ])
      result = loader.suggest_skills(codebase_index: index)
      expect(result).to include('mailer')
    end

    it 'suggests background-job when ActiveJob classes are present' do
      index = build_index(nodes: [
                            { 'type' => 'class', 'name' => 'ProcessOrderJob',
                              'file' => 'app/jobs/process_order_job.rb' }
                          ])
      result = loader.suggest_skills(codebase_index: index)
      expect(result).to include('background-job')
    end

    it 'suggests background-job when jobs directory files are present' do
      index = build_index(nodes: [
                            { 'type' => 'class', 'name' => 'ApplicationJob', 'file' => 'app/jobs/application_job.rb' }
                          ])
      result = loader.suggest_skills(codebase_index: index)
      expect(result).to include('background-job')
    end

    it 'returns multiple suggestions when multiple patterns match' do
      index = build_index(nodes: [
                            { 'type' => 'class', 'name' => 'Devise::RegistrationsController',
                              'file' => 'app/controllers/registrations_controller.rb' },
                            { 'type' => 'class', 'name' => 'WelcomeMailer', 'file' => 'app/mailers/welcome_mailer.rb' },
                            { 'type' => 'class', 'name' => 'ImportJob', 'file' => 'app/jobs/import_job.rb' }
                          ])
      result = loader.suggest_skills(codebase_index: index)
      expect(result).to contain_exactly('authentication', 'mailer', 'background-job')
    end

    it 'returns empty array when no patterns match' do
      index = build_index(nodes: [
                            { 'type' => 'model', 'name' => 'User', 'file' => 'app/models/user.rb' }
                          ])
      result = loader.suggest_skills(codebase_index: index)
      expect(result).to be_empty
    end

    it 'returns empty array on error' do
      bad_index = instance_double(RubynCode::Index::CodebaseIndex)
      allow(bad_index).to receive(:nodes).and_raise(StandardError, 'boom')
      result = loader.suggest_skills(codebase_index: bad_index)
      expect(result).to eq([])
    end

    it 'accepts a project_profile parameter for future use' do
      index = build_index(nodes: [])
      result = loader.suggest_skills(codebase_index: index, project_profile: 'rails')
      expect(result).to be_an(Array)
    end
  end
end
