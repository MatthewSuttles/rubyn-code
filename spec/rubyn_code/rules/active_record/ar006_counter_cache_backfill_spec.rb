# frozen_string_literal: true

require "spec_helper"
require "rubyn_code/rules/active_record/ar006_counter_cache_backfill"

RSpec.describe RubynCode::Rules::ActiveRecord::Ar006CounterCacheBackfill do
  after { RubynCode::Rules::Registry.reset! }

  describe "constants" do
    it "has the correct ID" do
      expect(described_class.id).to eq("AR006")
    end

    it "has category :active_record" do
      expect(described_class.category).to eq(:active_record)
    end

    it "has severity :high" do
      expect(described_class.severity).to eq(:high)
    end

    it "supports Rails >= 4.0" do
      expect(described_class.rails_versions).to eq([">= 4.0"])
    end

    it "has a confidence floor of 0.80" do
      expect(described_class.confidence_floor).to eq(0.80)
    end
  end

  describe ".applies_to?" do
    it "returns true when diff has a model file" do
      diff_data = { files: [{ path: "app/models/comment.rb", content: "class Comment; end" }] }
      expect(described_class.applies_to?(diff_data)).to be true
    end

    it "returns true when diff has a migration file" do
      diff_data = { files: [{ path: "db/migrate/20250101_add_comments_count.rb", content: "class AddCommentsCount" }] }
      expect(described_class.applies_to?(diff_data)).to be true
    end

    it "returns true when diff has both model and migration" do
      diff_data = {
        files: [
          { path: "app/models/comment.rb", content: "class Comment; end" },
          { path: "db/migrate/20250101_add_comments_count.rb", content: "class AddCommentsCount" }
        ]
      }
      expect(described_class.applies_to?(diff_data)).to be true
    end

    it "returns false when no model or migration files are changed" do
      diff_data = { files: [{ path: "app/controllers/posts_controller.rb", content: "class PostsController" }] }
      expect(described_class.applies_to?(diff_data)).to be false
    end

    it "returns false with empty files array" do
      diff_data = { files: [] }
      expect(described_class.applies_to?(diff_data)).to be false
    end

    it "returns false with nil input" do
      expect(described_class.applies_to?(nil)).to be false
    end

    it "returns false with non-hash input" do
      expect(described_class.applies_to?("not a hash")).to be false
    end
  end

  describe ".prompt_module" do
    it "returns a non-empty prompt string" do
      prompt = described_class.prompt_module
      expect(prompt).to be_a(String)
      expect(prompt).to include("AR006")
      expect(prompt).to include("counter_cache")
      expect(prompt).to include("backfill")
    end
  end

  describe ".validate" do
    # ---------------------------------------------------------------
    # POSITIVE fixtures — should return true (finding is valid)
    # ---------------------------------------------------------------

    context "positive: belongs_to with counter_cache: true, no backfill migration" do
      it "returns true" do
        diff_data = {
          files: [
            { path: "app/models/comment.rb", content: "class Comment < ApplicationRecord\n  belongs_to :post, counter_cache: true\nend\n" }
          ]
        }
        finding = { file: "app/models/comment.rb" }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: belongs_to with counter_cache: :custom_column, no backfill" do
      it "returns true" do
        diff_data = {
          files: [
            { path: "app/models/comment.rb", content: "class Comment < ApplicationRecord\n  belongs_to :post, counter_cache: :replies_count\nend\n" }
          ]
        }
        finding = { file: "app/models/comment.rb" }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: counter_cache with migration that only adds column (no backfill)" do
      it "returns true" do
        model_content = <<~RUBY
          class Comment < ApplicationRecord
            belongs_to :post, counter_cache: true
          end
        RUBY
        migration_content = <<~RUBY
          class AddCommentsCountToPosts < ActiveRecord::Migration[7.0]
            def change
              add_column :posts, :comments_count, :integer, default: 0, null: false
            end
          end
        RUBY
        diff_data = {
          files: [
            { path: "app/models/comment.rb", content: model_content },
            { path: "db/migrate/20250101_add_comments_count_to_posts.rb", content: migration_content }
          ]
        }
        finding = { file: "app/models/comment.rb" }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: counter_cache with unrelated migration content" do
      it "returns true" do
        model_content = "class Reply < ApplicationRecord\n  belongs_to :topic, counter_cache: true\nend\n"
        migration_content = <<~RUBY
          class AddIndexToTopics < ActiveRecord::Migration[7.0]
            def change
              add_index :topics, :user_id
            end
          end
        RUBY
        diff_data = {
          files: [
            { path: "app/models/reply.rb", content: model_content },
            { path: "db/migrate/20250201_add_index_to_topics.rb", content: migration_content }
          ]
        }
        finding = { file: "app/models/reply.rb" }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: counter_cache on model with additional options, no backfill" do
      it "returns true" do
        model_content = <<~RUBY
          class Vote < ApplicationRecord
            belongs_to :answer, counter_cache: true, inverse_of: :votes, optional: false
          end
        RUBY
        diff_data = {
          files: [{ path: "app/models/vote.rb", content: model_content }]
        }
        finding = { file: "app/models/vote.rb" }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: counter_cache with string keys in finding hash" do
      it "returns true" do
        diff_data = {
          files: [
            { path: "app/models/like.rb", content: "class Like < ApplicationRecord\n  belongs_to :photo, counter_cache: true\nend\n" }
          ]
        }
        finding = { "file" => "app/models/like.rb" }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    context "positive: counter_cache with string keys in diff_data" do
      it "returns true" do
        diff_data = {
          "files" => [
            { "path" => "app/models/reaction.rb", "content" => "class Reaction < ApplicationRecord\n  belongs_to :message, counter_cache: true\nend\n" }
          ]
        }
        finding = { file: "app/models/reaction.rb" }
        expect(described_class.validate(finding, diff_data)).to be true
      end
    end

    # ---------------------------------------------------------------
    # NEGATIVE fixtures — should return false (finding is not valid)
    # ---------------------------------------------------------------

    context "negative: counter_cache with reset_counters backfill in migration" do
      it "returns false" do
        model_content = "class Comment < ApplicationRecord\n  belongs_to :post, counter_cache: true\nend\n"
        migration_content = <<~RUBY
          class BackfillCommentsCount < ActiveRecord::Migration[7.0]
            def up
              Post.find_each do |post|
                Post.reset_counters(post.id, :comments)
              end
            end
          end
        RUBY
        diff_data = {
          files: [
            { path: "app/models/comment.rb", content: model_content },
            { path: "db/migrate/20250102_backfill_comments_count.rb", content: migration_content }
          ]
        }
        finding = { file: "app/models/comment.rb" }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: counter_cache with update_counters backfill" do
      it "returns false" do
        model_content = "class Comment < ApplicationRecord\n  belongs_to :post, counter_cache: true\nend\n"
        migration_content = <<~RUBY
          class BackfillPostCommentsCounts < ActiveRecord::Migration[7.0]
            def up
              Post.find_each do |post|
                Post.update_counters(post.id, comments_count: post.comments.count)
              end
            end
          end
        RUBY
        diff_data = {
          files: [
            { path: "app/models/comment.rb", content: model_content },
            { path: "db/migrate/20250102_backfill.rb", content: migration_content }
          ]
        }
        finding = { file: "app/models/comment.rb" }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: counter_cache with update_all backfill setting _count" do
      it "returns false" do
        model_content = "class Comment < ApplicationRecord\n  belongs_to :post, counter_cache: true\nend\n"
        migration_content = <<~RUBY
          class SetCommentsCounts < ActiveRecord::Migration[7.0]
            def up
              Post.update_all("comments_count = (SELECT COUNT(*) FROM comments WHERE comments.post_id = posts.id)")
            end
          end
        RUBY
        diff_data = {
          files: [
            { path: "app/models/comment.rb", content: model_content },
            { path: "db/migrate/20250102_set_comments_counts.rb", content: migration_content }
          ]
        }
        finding = { file: "app/models/comment.rb" }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: counter_cache with backfill keyword in migration" do
      it "returns false" do
        model_content = "class Bookmark < ApplicationRecord\n  belongs_to :article, counter_cache: true\nend\n"
        migration_content = <<~RUBY
          class BackfillBookmarksCounts < ActiveRecord::Migration[7.0]
            def up
              # backfill existing counts
              execute("UPDATE articles SET bookmarks_count = (SELECT COUNT(*) FROM bookmarks WHERE bookmarks.article_id = articles.id)")
            end
          end
        RUBY
        diff_data = {
          files: [
            { path: "app/models/bookmark.rb", content: model_content },
            { path: "db/migrate/20250102_backfill_bookmarks_counts.rb", content: migration_content }
          ]
        }
        finding = { file: "app/models/bookmark.rb" }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: finding references a non-model file" do
      it "returns false" do
        diff_data = {
          files: [{ path: "app/controllers/posts_controller.rb", content: "counter_cache: true" }]
        }
        finding = { file: "app/controllers/posts_controller.rb" }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: finding references a file not in the diff" do
      it "returns false" do
        diff_data = {
          files: [{ path: "app/models/post.rb", content: "class Post; end" }]
        }
        finding = { file: "app/models/comment.rb" }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: model file without counter_cache declaration" do
      it "returns false" do
        diff_data = {
          files: [{ path: "app/models/comment.rb", content: "class Comment < ApplicationRecord\n  belongs_to :post\nend\n" }]
        }
        finding = { file: "app/models/comment.rb" }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: finding has nil file" do
      it "returns false" do
        diff_data = { files: [] }
        finding = { file: nil }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: finding has empty file" do
      it "returns false" do
        diff_data = { files: [] }
        finding = { file: "" }
        expect(described_class.validate(finding, diff_data)).to be false
      end
    end

    context "negative: nil finding or diff_data" do
      it "returns false for nil finding" do
        expect(described_class.validate(nil, { files: [] })).to be false
      end

      it "returns false for nil diff_data" do
        expect(described_class.validate({ file: "app/models/x.rb" }, nil)).to be false
      end
    end
  end

  describe "registry integration" do
    it "is registered in the rules registry" do
      RubynCode::Rules::Registry.register(described_class)
      expect(RubynCode::Rules::Registry.get("AR006")).to eq(described_class)
    end
  end
end
