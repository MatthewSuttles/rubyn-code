# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/rules/security/sec003_authorize_missing"

RSpec.describe RubynCode::Rules::Security::Sec003AuthorizeMissing do
  after { RubynCode::Rules::Registry.reset! }

  describe "constants" do
    it "has the correct ID" do
      expect(described_class.id).to eq("SEC003")
    end

    it "has category :security" do
      expect(described_class.category).to eq(:security)
    end

    it "has severity :high" do
      expect(described_class.severity).to eq(:high)
    end

    it "supports Rails >= 5.0" do
      expect(described_class.rails_versions).to eq([">= 5.0"])
    end

    it "has a confidence floor of 0.85" do
      expect(described_class.confidence_floor).to eq(0.85)
    end
  end

  describe ".applies_to?" do
    it "returns true when diff has a controller file and Pundit in Gemfile" do
      diff_data = {
        files: [{ path: "app/controllers/posts_controller.rb", patch: "def show\nend" }],
        gemfile_content: "gem 'pundit'"
      }
      expect(described_class.applies_to?(diff_data)).to be true
    end

    it "returns true when controller includes Pundit module" do
      diff_data = {
        files: [{
          path: "app/controllers/posts_controller.rb",
          content: "class PostsController < ApplicationController\n  include Pundit\nend"
        }]
      }
      expect(described_class.applies_to?(diff_data)).to be true
    end

    it "returns false when no controller files are changed" do
      diff_data = {
        files: [{ path: "app/models/post.rb", patch: "class Post; end" }],
        gemfile_content: "gem 'pundit'"
      }
      expect(described_class.applies_to?(diff_data)).to be false
    end

    it "returns false when Pundit is not detected" do
      diff_data = {
        files: [{ path: "app/controllers/posts_controller.rb", patch: "def show\nend" }],
        gemfile_content: "gem 'rails'"
      }
      expect(described_class.applies_to?(diff_data)).to be false
    end

    it "returns false with empty files array" do
      diff_data = { files: [], gemfile_content: "gem 'pundit'" }
      expect(described_class.applies_to?(diff_data)).to be false
    end
  end

  describe ".prompt_module" do
    it "returns a non-empty prompt string" do
      prompt = described_class.prompt_module
      expect(prompt).to be_a(String)
      expect(prompt).to include("SEC003")
      expect(prompt).to include("authorize")
    end
  end

  describe ".validate" do
    # ---------------------------------------------------------------
    # POSITIVE fixtures — should return true (finding is valid)
    # ---------------------------------------------------------------

    context "positive: show action with find but no authorize" do
      let(:controller_content) do
        <<~RUBY
          class PostsController < ApplicationController
            def show
              @post = Post.find(params[:id])
              render :show
            end
          end
        RUBY
      end

      it "returns true" do
        diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/posts_controller.rb", action: "show", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: update action with find_by! but no authorize" do
      let(:controller_content) do
        <<~RUBY
          class OrdersController < ApplicationController
            def update
              @order = Order.find_by!(id: params[:id])
              @order.update!(order_params)
              redirect_to @order
            end
          end
        RUBY
      end

      it "returns true" do
        diff_data = { files: [{ path: "app/controllers/orders_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/orders_controller.rb", action: "update", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: destroy action with find but no authorize" do
      let(:controller_content) do
        <<~RUBY
          class CommentsController < ApplicationController
            def destroy
              @comment = Comment.find(params[:id])
              @comment.destroy
              redirect_to posts_path
            end
          end
        RUBY
      end

      it "returns true" do
        diff_data = { files: [{ path: "app/controllers/comments_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/comments_controller.rb", action: "destroy", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: edit action with find but no authorize" do
      let(:controller_content) do
        <<~RUBY
          class ArticlesController < ApplicationController
            def edit
              @article = Article.find(params[:id])
            end
          end
        RUBY
      end

      it "returns true" do
        diff_data = { files: [{ path: "app/controllers/articles_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/articles_controller.rb", action: "edit", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: show action with where(...).first but no authorize" do
      let(:controller_content) do
        <<~RUBY
          class InvoicesController < ApplicationController
            def show
              @invoice = Invoice.where(token: params[:token]).first
              render :show
            end
          end
        RUBY
      end

      it "returns true" do
        diff_data = { files: [{ path: "app/controllers/invoices_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/invoices_controller.rb", action: "show", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: update action with find_sole_by but no authorize" do
      let(:controller_content) do
        <<~RUBY
          class ProfilesController < ApplicationController
            def update
              @profile = Profile.find_sole_by(user_id: current_user.id)
              @profile.update!(profile_params)
              redirect_to @profile
            end
          end
        RUBY
      end

      it "returns true" do
        diff_data = { files: [{ path: "app/controllers/profiles_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/profiles_controller.rb", action: "update", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: show action with find_by but no authorize" do
      let(:controller_content) do
        <<~RUBY
          class UsersController < ApplicationController
            def show
              @user = User.find_by(slug: params[:slug])
              render :show
            end
          end
        RUBY
      end

      it "returns true" do
        diff_data = { files: [{ path: "app/controllers/users_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/users_controller.rb", action: "show", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    # ---------------------------------------------------------------
    # NEGATIVE fixtures — should return false (finding is not valid)
    # ---------------------------------------------------------------

    context "negative: show action with find AND authorize present" do
      let(:controller_content) do
        <<~RUBY
          class PostsController < ApplicationController
            def show
              @post = Post.find(params[:id])
              authorize(@post)
              render :show
            end
          end
        RUBY
      end

      it "returns false" do
        diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/posts_controller.rb", action: "show", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: action without a finder call (no record loaded)" do
      let(:controller_content) do
        <<~RUBY
          class DashboardsController < ApplicationController
            def show
              @stats = DashboardService.new(current_user).stats
              render :show
            end
          end
        RUBY
      end

      it "returns false" do
        diff_data = { files: [{ path: "app/controllers/dashboards_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/dashboards_controller.rb", action: "show", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: finding references a file not in the diff" do
      it "returns false" do
        diff_data = { files: [{ path: "app/controllers/other_controller.rb", content: "def show; end" }] }
        finding = { file: "app/controllers/missing_controller.rb", action: "show", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: finding has nil file or action" do
      it "returns false when file is nil" do
        diff_data = { files: [] }
        finding = { file: nil, action: "show", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be false
      end

      it "returns false when action is nil" do
        diff_data = { files: [] }
        finding = { file: "app/controllers/posts_controller.rb", action: nil, line: 2 }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: destroy action with authorize called" do
      let(:controller_content) do
        <<~RUBY
          class ProjectsController < ApplicationController
            def destroy
              @project = Project.find(params[:id])
              authorize(@project)
              @project.destroy
              redirect_to projects_path
            end
          end
        RUBY
      end

      it "returns false" do
        diff_data = { files: [{ path: "app/controllers/projects_controller.rb", content: controller_content }] }
        finding = { file: "app/controllers/projects_controller.rb", action: "destroy", line: 2 }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: update action with authorize using string keys in finding" do
      let(:controller_content) do
        <<~RUBY
          class TasksController < ApplicationController
            def update
              @task = Task.find(params[:id])
              authorize(@task)
              @task.update!(task_params)
              redirect_to @task
            end
          end
        RUBY
      end

      it "returns false" do
        diff_data = { files: [{ path: "app/controllers/tasks_controller.rb", content: controller_content }] }
        finding = { "file" => "app/controllers/tasks_controller.rb", "action" => "update", "line" => 2 }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end
  end

  describe "registry integration" do
    it "is registered in the rules registry" do
      # Re-register since reset! was called in after hook
      RubynCode::Rules::Registry.register(described_class)
      expect(RubynCode::Rules::Registry.get("SEC003")).to eq(described_class)
    end
  end
end
