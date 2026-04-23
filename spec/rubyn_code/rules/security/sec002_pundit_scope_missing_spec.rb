# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/rules/security/sec002_pundit_scope_missing"

RSpec.describe RubynCode::Rules::Security::Sec002PunditScopeMissing do
  let(:rule) { described_class }

  describe "constants" do
    it "has the correct ID" do
      expect(rule.id).to eq("SEC002")
    end

    it "has :security category" do
      expect(rule.category).to eq(:security)
    end

    it "has :high severity" do
      expect(rule.severity).to eq(:high)
    end

    it "supports Rails >= 5.0" do
      expect(rule.rails_versions).to eq([">= 5.0"])
    end

    it "has a confidence floor of 0.85" do
      expect(rule.confidence_floor).to eq(0.85)
    end
  end

  describe ".applies_to?" do
    let(:gemfile_with_pundit) { "gem 'pundit'\ngem 'rails'" }

    it "returns true when a controller file is changed in a Pundit project" do
      diff_data = {
        files: [{ path: "app/controllers/posts_controller.rb", content: "class PostsController" }],
        gemfile_content: gemfile_with_pundit
      }
      expect(rule.applies_to?(diff_data)).to be true
    end

    it "returns false when no controller files are changed" do
      diff_data = {
        files: [{ path: "app/models/post.rb", content: "class Post" }],
        gemfile_content: gemfile_with_pundit
      }
      expect(rule.applies_to?(diff_data)).to be false
    end

    it "returns false when Pundit is not present" do
      diff_data = {
        files: [{ path: "app/controllers/posts_controller.rb", content: "class PostsController" }],
        gemfile_content: "gem 'rails'"
      }
      expect(rule.applies_to?(diff_data)).to be false
    end

    it "detects Pundit via Gemfile.lock content" do
      diff_data = {
        files: [{ path: "app/controllers/posts_controller.rb", content: "class PostsController" }],
        gemfile_content: "",
        gemfile_lock_content: "    pundit (2.3.0)\n"
      }
      expect(rule.applies_to?(diff_data)).to be true
    end

    it "detects Pundit via include Pundit in changed files" do
      diff_data = {
        files: [{
          path: "app/controllers/application_controller.rb",
          content: "class ApplicationController < ActionController::Base\n  include Pundit\nend\n"
        }],
        gemfile_content: ""
      }
      expect(rule.applies_to?(diff_data)).to be true
    end
  end

  describe ".prompt_module" do
    it "returns a non-empty prompt string" do
      expect(rule.prompt_module).to be_a(String)
      expect(rule.prompt_module).to include("SEC002")
      expect(rule.prompt_module).to include("policy_scope")
    end
  end

  describe ".validate" do
    # --- Positive cases (violations) ---

    it "flags index action using Model.all without policy_scope" do
      content = <<~RUBY
        class PostsController < ApplicationController
          def index
            @posts = Post.all
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: content }] }
      finding = { file: "app/controllers/posts_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be true
    end

    it "flags index action using Model.where without policy_scope" do
      content = <<~RUBY
        class PostsController < ApplicationController
          def index
            @posts = Post.where(published: true)
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: content }] }
      finding = { file: "app/controllers/posts_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be true
    end

    it "flags index action using Model.order without policy_scope" do
      content = <<~RUBY
        class ArticlesController < ApplicationController
          def index
            @articles = Article.order(created_at: :desc)
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/articles_controller.rb", content: content }] }
      finding = { file: "app/controllers/articles_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be true
    end

    it "flags index action using chained scopes without policy_scope" do
      content = <<~RUBY
        class UsersController < ApplicationController
          def index
            @users = User.where(active: true).includes(:profile).order(:name)
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/users_controller.rb", content: content }] }
      finding = { file: "app/controllers/users_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be true
    end

    it "flags index action using Model.joins without policy_scope" do
      content = <<~RUBY
        class CommentsController < ApplicationController
          def index
            @comments = Comment.joins(:post).where(posts: { published: true })
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/comments_controller.rb", content: content }] }
      finding = { file: "app/controllers/comments_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be true
    end

    it "flags index action using Model.select without policy_scope" do
      content = <<~RUBY
        class ReportsController < ApplicationController
          def index
            @reports = Report.select(:id, :title, :created_at)
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/reports_controller.rb", content: content }] }
      finding = { file: "app/controllers/reports_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be true
    end

    # --- Negative cases (compliant) ---

    it "passes when index uses policy_scope" do
      content = <<~RUBY
        class PostsController < ApplicationController
          def index
            @posts = policy_scope(Post)
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: content }] }
      finding = { file: "app/controllers/posts_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be false
    end

    it "passes when index uses policy_scope with chained queries" do
      content = <<~RUBY
        class PostsController < ApplicationController
          def index
            @posts = policy_scope(Post).where(published: true).order(:title)
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: content }] }
      finding = { file: "app/controllers/posts_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be false
    end

    it "passes when index uses policy_scope wrapping a query" do
      content = <<~RUBY
        class PostsController < ApplicationController
          def index
            @posts = policy_scope(Post.where(draft: false))
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: content }] }
      finding = { file: "app/controllers/posts_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be false
    end

    it "passes for non-index actions even without policy_scope" do
      content = <<~RUBY
        class PostsController < ApplicationController
          def show
            @post = Post.find(params[:id])
          end

          def recent
            @posts = Post.where(published: true).limit(5)
          end
        end
      RUBY

      diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: content }] }
      finding = { file: "app/controllers/posts_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be false
    end

    it "returns false when finding references a non-controller file" do
      diff_data = { files: [{ path: "app/models/post.rb", content: "class Post; end" }] }
      finding = { file: "app/models/post.rb" }

      expect(rule.validate(finding, diff_data)).to be false
    end

    it "returns false when finding file is not in diff_data" do
      diff_data = { files: [{ path: "app/controllers/other_controller.rb", content: "" }] }
      finding = { file: "app/controllers/posts_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be false
    end

    it "returns false when file content is empty" do
      diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: "" }] }
      finding = { file: "app/controllers/posts_controller.rb" }

      expect(rule.validate(finding, diff_data)).to be false
    end
  end

  describe "registry integration" do
    it "is registered in the rules registry" do
      expect(RubynCode::Rules::Registry.get("SEC002")).to eq(described_class)
    end
  end
end
