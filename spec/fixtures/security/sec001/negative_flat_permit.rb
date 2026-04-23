# frozen_string_literal: true

# Negative fixture: flat permit with only scalar attributes (safe)
class PostsController < ApplicationController
  def create
    @post = Post.new(post_params)
    @post.save
  end

  private

  def post_params
    params.require(:post).permit(:title, :body, :published)
  end
end
