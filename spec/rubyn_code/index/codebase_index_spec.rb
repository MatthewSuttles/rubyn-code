# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'

RSpec.describe RubynCode::Index::CodebaseIndex do
  let(:tmpdir) { Dir.mktmpdir }
  let(:index) { described_class.new(project_root: tmpdir) }

  after { FileUtils.remove_entry(tmpdir) }

  before do
    # Stub Debug.warn to avoid undefined method errors
    debug_mod = Module.new do
      def self.warn(msg); end
    end
    stub_const('RubynCode::Debug', debug_mod)
  end

  def create_model_file(name, content)
    dir = File.join(tmpdir, 'app', 'models')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{name}.rb"), content)
  end

  def create_controller_file(name, content)
    dir = File.join(tmpdir, 'app', 'controllers')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{name}.rb"), content)
  end

  def create_service_file(name, content)
    dir = File.join(tmpdir, 'app', 'services')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{name}.rb"), content)
  end

  def create_ruby_file(relative_path, content)
    path = File.join(tmpdir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  describe '#build!' do
    it 'indexes classes' do
      create_model_file('user', <<~RUBY)
        class User < ApplicationRecord
        end
      RUBY

      index.build!
      class_nodes = index.nodes.select { |n| n['name'] == 'User' }
      expect(class_nodes).not_to be_empty
      expect(class_nodes.first['type']).to eq('model')
    end

    it 'indexes methods' do
      create_model_file('user', <<~RUBY)
        class User < ApplicationRecord
          def full_name
            "\#{first_name} \#{last_name}"
          end
        end
      RUBY

      index.build!
      method_nodes = index.nodes.select { |n| n['type'] == 'method' }
      expect(method_nodes.map { |n| n['name'] }).to include('full_name')
    end

    it 'indexes associations' do
      create_model_file('user', <<~RUBY)
        class User < ApplicationRecord
          has_many :posts
          belongs_to :organization
        end
      RUBY

      index.build!
      assoc_edges = index.edges.select { |e| e['relationship'] == 'association' }
      assoc_names = assoc_edges.map { |e| e['to'] }
      expect(assoc_names).to include('posts', 'organization')
    end

    it 'indexes callbacks and scopes' do
      create_model_file('post', <<~RUBY)
        class Post < ApplicationRecord
          scope :published, -> { where(published: true) }
        end
      RUBY

      create_controller_file('posts_controller', <<~RUBY)
        class PostsController < ApplicationController
          before_action :authenticate_user!
        end
      RUBY

      index.build!
      scope_nodes = index.nodes.select { |n| n['type'] == 'scope' }
      callback_nodes = index.nodes.select { |n| n['type'] == 'callback' }
      expect(scope_nodes.map { |n| n['name'] }).to include('published')
      expect(callback_nodes.map { |n| n['name'] }).to include('authenticate_user')
    end

    it 'classifies nodes by directory' do
      create_model_file('user', "class User\nend\n")
      create_controller_file('users_controller', "class UsersController\nend\n")
      create_service_file('create_user', "class CreateUser\nend\n")

      index.build!
      expect(index.nodes.find { |n| n['name'] == 'User' }['type']).to eq('model')
      expect(index.nodes.find { |n| n['name'] == 'UsersController' }['type']).to eq('controller')
      expect(index.nodes.find { |n| n['name'] == 'CreateUser' }['type']).to eq('service')
    end
  end

  describe '#load' do
    it 'returns nil when no index exists' do
      expect(index.load).to be_nil
    end

    it 'returns self when index exists' do
      create_model_file('user', "class User\nend\n")
      index.build!

      fresh = described_class.new(project_root: tmpdir)
      expect(fresh.load).to be_a(described_class)
    end

    it 'deduplicates edges from older bloated index files' do
      create_model_file('user', "class User\nend\n")
      create_ruby_file('spec/models/user_spec.rb', "RSpec.describe User do\nend\n")
      index.build!

      data = JSON.parse(File.read(index.index_path))
      data['edges'] += data['edges'] # simulate duplicates written by older versions
      File.write(index.index_path, JSON.generate(data))

      fresh = described_class.new(project_root: tmpdir)
      fresh.load
      expect(fresh.edges).to eq(fresh.edges.uniq)
      expect(fresh.edges.count { |e| e['relationship'] == 'tests' }).to eq(1)
    end

    it 'restores nodes and edges from disk' do
      create_model_file('user', <<~RUBY)
        class User < ApplicationRecord
          has_many :posts
        end
      RUBY
      index.build!

      fresh = described_class.new(project_root: tmpdir)
      fresh.load
      expect(fresh.nodes).not_to be_empty
      expect(fresh.edges).not_to be_empty
    end
  end

  describe '#load_or_build!' do
    it 'builds when no index exists' do
      create_model_file('user', "class User\nend\n")
      result = index.load_or_build!
      expect(result).to be_a(described_class)
      expect(index.nodes).not_to be_empty
    end

    it 'loads when index exists' do
      create_model_file('user', "class User\nend\n")
      index.build!

      fresh = described_class.new(project_root: tmpdir)
      fresh.load_or_build!
      expect(fresh.nodes).not_to be_empty
    end
  end

  describe '#query' do
    before do
      create_model_file('user', "class User\n  def full_name\n  end\nend\n")
      create_model_file('post', "class Post\nend\n")
      index.build!
    end

    it 'finds matching nodes by name' do
      results = index.query('User')
      expect(results.map { |n| n['name'] }).to include('User')
    end

    it 'finds matching nodes by file path' do
      results = index.query('user.rb')
      expect(results).not_to be_empty
    end

    it 'is case-insensitive' do
      results = index.query('user')
      expect(results).not_to be_empty
    end

    it 'returns empty for no matches' do
      results = index.query('nonexistent_xyz')
      expect(results).to be_empty
    end
  end

  describe '#impact_analysis' do
    before do
      create_model_file('user', <<~RUBY)
        class User < ApplicationRecord
          has_many :posts
        end
      RUBY
      index.build!
    end

    it 'returns definitions for the file' do
      file_path = File.join(tmpdir, 'app', 'models', 'user.rb')
      result = index.impact_analysis(file_path)
      expect(result[:definitions]).not_to be_empty
    end

    it 'returns relationships for the file' do
      file_path = File.join(tmpdir, 'app', 'models', 'user.rb')
      result = index.impact_analysis(file_path)
      expect(result).to have_key(:relationships)
    end

    it 'returns affected_files' do
      file_path = File.join(tmpdir, 'app', 'models', 'user.rb')
      result = index.impact_analysis(file_path)
      expect(result).to have_key(:affected_files)
    end
  end

  describe '#to_prompt_summary' do
    it 'returns a compact string' do
      create_model_file('user', "class User\n  def name\n  end\nend\n")
      create_controller_file('users_controller', "class UsersController\nend\n")
      index.build!

      result = index.to_prompt_summary
      expect(result).to include('Codebase Index:')
      expect(result).to include('Classes:')
      expect(result).to include('Models:')
      expect(result).to include('Controllers:')
    end

    it 'counts nodes correctly' do
      create_model_file('user', "class User\nend\n")
      create_model_file('post', "class Post\nend\n")
      index.build!

      result = index.to_prompt_summary
      expect(result).to include('Models: 2')
    end
  end

  describe '#to_structural_summary' do
    it 'includes models with their associations' do
      create_model_file('user', <<~RUBY)
        class User < ApplicationRecord
          has_many :posts
          belongs_to :organization
        end
      RUBY
      index.build!

      result = index.to_structural_summary
      expect(result).to include('Codebase Structure:')
      expect(result).to include('Models:')
      expect(result).to include('User')
      expect(result).to include('has_many :posts')
      expect(result).to include('belongs_to :organization')
    end

    it 'includes controllers' do
      create_controller_file('users_controller', <<~RUBY)
        class UsersController < ApplicationController
        end
      RUBY
      index.build!

      result = index.to_structural_summary
      expect(result).to include('Controllers:')
      expect(result).to include('UsersController')
    end

    it 'includes service objects' do
      create_service_file('create_user', <<~RUBY)
        class CreateUser
          def call; end
        end
      RUBY
      index.build!

      result = index.to_structural_summary
      expect(result).to include('Services:')
      expect(result).to include('CreateUser')
    end

    it 'includes stats line' do
      create_model_file('user', "class User\nend\n")
      index.build!

      result = index.to_structural_summary
      expect(result).to include('Stats:')
      expect(result).to match(/\d+ classes/)
      expect(result).to match(/\d+ methods/)
      expect(result).to match(/\d+ edges/)
    end

    it 'truncates output to respect max_tokens' do
      10.times do |i|
        create_model_file("model_#{i}", "class Model#{i} < ApplicationRecord\nend\n")
      end
      index.build!

      short = index.to_structural_summary(max_tokens: 10) # ~40 chars budget
      full  = index.to_structural_summary(max_tokens: 5000)
      expect(short.length).to be < full.length
    end

    it 'returns structure header even with empty index' do
      index.build!
      result = index.to_structural_summary
      expect(result).to include('Codebase Structure:')
      expect(result).to include('Stats:')
    end
  end

  describe '#save!' do
    it 'creates the index file' do
      index.build!
      expect(File.exist?(index.index_path)).to be true
    end

    it 'writes valid JSON' do
      create_model_file('user', "class User\nend\n")
      index.build!

      data = JSON.parse(File.read(index.index_path))
      expect(data).to have_key('nodes')
      expect(data).to have_key('edges')
      expect(data).to have_key('file_mtimes')
    end
  end

  describe '#update!' do
    it 're-indexes changed files' do
      create_model_file('user', "class User\nend\n")
      index.build!

      # Force a different mtime by touching the file in the future
      user_file = File.join(tmpdir, 'app', 'models', 'user.rb')
      new_content = "class User\n  def greet\n  end\nend\n"
      File.write(user_file, new_content)
      future_time = Time.now + 10
      File.utime(future_time, future_time, user_file)

      index.update!
      method_nodes = index.nodes.select { |n| n['type'] == 'method' && n['name'] == 'greet' }
      expect(method_nodes).not_to be_empty
    end

    it 'returns self when no files changed' do
      create_model_file('user', "class User\nend\n")
      index.build!
      expect(index.update!).to be_a(described_class)
    end

    it 'does not duplicate tests edges across repeated updates' do
      create_model_file('user', "class User\nend\n")
      create_ruby_file('spec/models/user_spec.rb', "RSpec.describe User do\nend\n")
      index.build!

      user_file = File.join(tmpdir, 'app', 'models', 'user.rb')
      3.times do |i|
        File.write(user_file, "class User\n  def version_#{i}\n  end\nend\n")
        future_time = Time.now + (10 * (i + 1))
        File.utime(future_time, future_time, user_file)
        index.update!
      end

      tests_edges = index.edges.select { |e| e['relationship'] == 'tests' }
      expect(tests_edges.size).to eq(1)
    end
  end

  describe '#update_file!' do
    it 're-indexes only the given file' do
      create_model_file('user', "class User\nend\n")
      create_model_file('post', "class Post\nend\n")
      index.build!

      user_file = File.join(tmpdir, 'app', 'models', 'user.rb')
      post_file = File.join(tmpdir, 'app', 'models', 'post.rb')
      File.write(user_file, "class User\n  def greet\n  end\nend\n")
      File.write(post_file, "class Post\n  def stale\n  end\nend\n")

      index.update_file!(user_file)

      names = index.nodes.map { |n| n['name'] }
      expect(names).to include('greet')
      expect(names).not_to include('stale')
    end

    it 'preserves other files nodes and edges' do
      create_model_file('user', "class User\nend\n")
      create_model_file('post', "class Post\n  has_many :comments\nend\n")
      index.build!

      index.update_file!(File.join(tmpdir, 'app', 'models', 'user.rb'))

      expect(index.nodes.map { |n| n['name'] }).to include('Post')
      assoc = index.edges.select { |e| e['relationship'] == 'association' }
      expect(assoc.map { |e| e['to'] }).to include('comments')
    end

    it 'removes nodes when the file was deleted' do
      create_model_file('user', "class User\nend\n")
      index.build!

      user_file = File.join(tmpdir, 'app', 'models', 'user.rb')
      File.delete(user_file)
      index.update_file!(user_file)

      expect(index.nodes.map { |n| n['name'] }).not_to include('User')
    end

    it 'does not duplicate tests edges across repeated calls' do
      create_model_file('user', "class User\nend\n")
      create_ruby_file('spec/models/user_spec.rb', "RSpec.describe User do\nend\n")
      index.build!

      user_file = File.join(tmpdir, 'app', 'models', 'user.rb')
      3.times { index.update_file!(user_file) }

      tests_edges = index.edges.select { |e| e['relationship'] == 'tests' }
      expect(tests_edges.size).to eq(1)
    end

    it 'persists the update to disk' do
      create_model_file('user', "class User\nend\n")
      index.build!

      user_file = File.join(tmpdir, 'app', 'models', 'user.rb')
      File.write(user_file, "class User\n  def greet\n  end\nend\n")
      index.update_file!(user_file)

      fresh = described_class.new(project_root: tmpdir)
      fresh.load
      expect(fresh.nodes.map { |n| n['name'] }).to include('greet')
    end

    it 'ignores paths outside the project root' do
      create_model_file('user', "class User\nend\n")
      index.build!

      expect { index.update_file!('/etc/hosts') }.not_to(change { index.nodes.size })
    end
  end

  describe 'git-aware file discovery' do
    it 'skips gitignored files when the project is a git repository' do
      skip 'git not available' unless system('git --version', out: File::NULL, err: File::NULL)

      create_model_file('user', "class User\nend\n")
      create_ruby_file('tmp/junk.rb', "class Junk\nend\n")
      File.write(File.join(tmpdir, '.gitignore'), "tmp/\n")
      system('git', '-C', tmpdir, 'init', '-q', out: File::NULL, err: File::NULL)

      index.build!

      names = index.nodes.map { |n| n['name'] }
      expect(names).to include('User')
      expect(names).not_to include('Junk')
    end
  end
end
