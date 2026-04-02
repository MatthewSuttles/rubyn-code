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
  end
end
