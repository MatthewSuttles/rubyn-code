# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe RubynCode::Skills::Catalog do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmpdir) }

  before do
    File.write(File.join(tmpdir, "deploy.md"), <<~MD)
      ---
      name: deploy
      description: Deploy the app
      tags: []
      ---
      Steps to deploy.
    MD

    File.write(File.join(tmpdir, "review.md"), <<~MD)
      ---
      name: review
      description: Code review checklist
      tags: []
      ---
      Review steps.
    MD
  end

  subject(:catalog) { described_class.new(tmpdir) }

  describe "#descriptions" do
    it "returns a formatted string with all skills" do
      desc = catalog.descriptions
      expect(desc).to include("deploy")
      expect(desc).to include("review")
    end
  end

  describe "#available" do
    it "returns entries for each skill file" do
      expect(catalog.available.length).to eq(2)
    end
  end

  describe "#find" do
    it "returns the path for a known skill" do
      path = catalog.find("deploy")
      expect(path).to end_with("deploy.md")
    end

    it "returns nil for an unknown skill" do
      expect(catalog.find("nonexistent")).to be_nil
    end
  end
end
