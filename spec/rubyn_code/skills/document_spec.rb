# frozen_string_literal: true

RSpec.describe RubynCode::Skills::Document do
  let(:content) do
    <<~MD
      ---
      name: deploy
      description: Deploy the application
      tags:
        - ops
        - ci
      ---
      Run the deploy script with the right flags.
    MD
  end

  describe ".parse" do
    subject(:doc) { described_class.parse(content) }

    it "extracts the name from frontmatter" do
      expect(doc.name).to eq("deploy")
    end

    it "extracts the description" do
      expect(doc.description).to eq("Deploy the application")
    end

    it "extracts tags as an array" do
      expect(doc.tags).to eq(%w[ops ci])
    end

    it "extracts the body after frontmatter" do
      expect(doc.body).to include("Run the deploy script")
    end
  end

  describe ".parse with no frontmatter" do
    subject(:doc) { described_class.parse("Just plain text") }

    it "derives a name from the content" do
      expect(doc.name).to eq("just-plain-text")
    end

    it "uses the full content as body" do
      expect(doc.body).to eq("Just plain text")
    end

    it "returns empty tags" do
      expect(doc.tags).to eq([])
    end

    it "returns empty triggers" do
      expect(doc.triggers).to eq([])
    end

    it "returns empty gems" do
      expect(doc.gems).to eq([])
    end

    it "returns nil rails constraint" do
      expect(doc.rails).to be_nil
    end
  end

  describe ".parse with autoload metadata" do
    let(:content) do
      <<~MD
        ---
        name: turbo-drive
        description: Turbo Drive navigation
        triggers:
          - turbo drive
          - page navigation
          - data-turbo
        gems:
          - turbo-rails
        rails: ">=7.0"
        ---
        Body content.
      MD
    end

    subject(:doc) { described_class.parse(content) }

    it "parses triggers as strings" do
      expect(doc.triggers).to eq(["turbo drive", "page navigation", "data-turbo"])
    end

    it "parses gems as strings" do
      expect(doc.gems).to eq(["turbo-rails"])
    end

    it "parses the rails constraint as a string" do
      expect(doc.rails).to eq(">=7.0")
    end
  end

  describe ".parse with frontmatter missing autoload fields" do
    let(:content) do
      <<~MD
        ---
        name: deploy
        description: Deploy
        ---
        Body.
      MD
    end

    subject(:doc) { described_class.parse(content) }

    it "defaults triggers to []" do
      expect(doc.triggers).to eq([])
    end

    it "defaults gems to []" do
      expect(doc.gems).to eq([])
    end

    it "defaults rails to nil" do
      expect(doc.rails).to be_nil
    end
  end
end
