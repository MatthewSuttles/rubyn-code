# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe RubynCode::Config::ProjectProfile do
  let(:tmpdir) { Dir.mktmpdir }
  let(:profile) { described_class.new(project_root: tmpdir) }

  after { FileUtils.remove_entry(tmpdir) }

  describe '#load' do
    it 'returns nil when no profile exists' do
      expect(profile.load).to be_nil
    end

    it 'returns self when profile exists' do
      profile.save!
      expect(profile.load).to be_a(described_class)
    end

    it 'loads saved data correctly' do
      profile.detect_and_save!
      loaded = described_class.new(project_root: tmpdir)
      loaded.load
      expect(loaded.data).to eq(profile.data)
    end
  end

  describe '#detect_and_save!' do
    it 'detects framework from Gemfile' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'rails'\n")
      profile.detect_and_save!
      expect(profile.data['framework']).to eq('rails')
    end

    it 'detects sinatra from Gemfile' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'sinatra'\n")
      profile.detect_and_save!
      expect(profile.data['framework']).to eq('sinatra')
    end

    it 'detects ruby version from .ruby-version' do
      File.write(File.join(tmpdir, '.ruby-version'), "3.3.0\n")
      profile.detect_and_save!
      expect(profile.data['ruby_version']).to eq('3.3.0')
    end

    it 'detects postgresql database' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'pg'\n")
      profile.detect_and_save!
      expect(profile.data['database']).to eq('postgresql')
    end

    it 'detects mysql database' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'mysql2'\n")
      profile.detect_and_save!
      expect(profile.data['database']).to eq('mysql')
    end

    it 'detects test framework rspec' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'rspec'\n")
      profile.detect_and_save!
      expect(profile.data['test_framework']).to eq('rspec')
    end

    it 'detects factory_bot' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'factory_bot'\n")
      profile.detect_and_save!
      expect(profile.data['factories']).to eq('factory_bot')
    end

    it 'detects devise auth' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'devise'\ngem 'rails'\n")
      profile.detect_and_save!
      expect(profile.data['auth']).to eq('devise')
    end

    it 'detects sidekiq background jobs' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'sidekiq'\n")
      profile.detect_and_save!
      expect(profile.data['background_jobs']).to eq('sidekiq')
    end

    it 'detects key models from app/models' do
      models_dir = File.join(tmpdir, 'app', 'models')
      FileUtils.mkdir_p(models_dir)
      File.write(File.join(models_dir, 'user.rb'), "class User < ApplicationRecord\nend\n")
      File.write(File.join(models_dir, 'post.rb'), "class Post < ApplicationRecord\nend\n")

      profile.detect_and_save!
      expect(profile.data['key_models']).to include('User', 'Post')
    end

    it 'detects service pattern from app/services' do
      services_dir = File.join(tmpdir, 'app', 'services')
      FileUtils.mkdir_p(services_dir)
      File.write(File.join(services_dir, 'create_user_service.rb'), '')

      profile.detect_and_save!
      expect(profile.data['service_pattern']).to eq('app/services/**/*_service.rb')
    end
  end

  describe '#load_or_detect!' do
    it 'loads existing profile when one exists' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'rails'\n")
      profile.detect_and_save!

      fresh = described_class.new(project_root: tmpdir)
      fresh.load_or_detect!
      expect(fresh.data['framework']).to eq('rails')
    end

    it 'detects when no profile exists' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'sinatra'\n")

      fresh = described_class.new(project_root: tmpdir)
      fresh.load_or_detect!
      expect(fresh.data['framework']).to eq('sinatra')
    end
  end

  describe '#to_prompt' do
    it 'returns empty string when data is empty' do
      expect(profile.to_prompt).to eq('')
    end

    it 'returns formatted string with profile data' do
      File.write(File.join(tmpdir, 'Gemfile'), "gem 'rails'\ngem 'pg'\n")
      profile.detect_and_save!

      result = profile.to_prompt
      expect(result).to include('Project Profile:')
      expect(result).to include('framework: rails')
      expect(result).to include('database: postgresql')
    end

    it 'joins array values with commas' do
      File.write(File.join(tmpdir, 'Gemfile'), '')
      models_dir = File.join(tmpdir, 'app', 'models')
      FileUtils.mkdir_p(models_dir)
      File.write(File.join(models_dir, 'user.rb'), "class User\nend\n")
      File.write(File.join(models_dir, 'post.rb'), "class Post\nend\n")

      profile.detect_and_save!
      result = profile.to_prompt
      expect(result).to match(/key_models:.*User/)
    end
  end

  describe '#stale?' do
    it 'returns true when no profile exists' do
      expect(profile.stale?).to be true
    end

    it 'returns false for a freshly saved profile' do
      profile.save!
      expect(profile.stale?).to be false
    end
  end

  describe '#save!' do
    it 'creates .rubyn-code directory' do
      profile.save!
      expect(File.directory?(File.join(tmpdir, '.rubyn-code'))).to be true
    end

    it 'creates the profile YAML file' do
      profile.save!
      expect(File.exist?(profile.profile_path)).to be true
    end
  end
end
