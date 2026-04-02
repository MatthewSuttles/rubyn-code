# frozen_string_literal: true

require "tempfile"

RSpec.describe RubynCode::Skills::Loader do
  let(:catalog) { instance_double(RubynCode::Skills::Catalog) }
  let(:tmpfile) { Tempfile.new(["skill", ".md"]) }

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

  describe "#load" do
    it "returns content wrapped in skill tags" do
      allow(catalog).to receive(:find).with("commit").and_return(tmpfile.path)

      content = loader.load("commit")
      expect(content).to include('<skill name="commit">')
      expect(content).to include("</skill>")
      expect(content).to include("Commit instructions here.")
    end

    it "caches loaded skills" do
      allow(catalog).to receive(:find).with("commit").and_return(tmpfile.path)

      loader.load("commit")
      loader.load("commit")

      expect(catalog).to have_received(:find).once
    end

    it "raises when skill is not found" do
      allow(catalog).to receive(:find).with("missing").and_return(nil)

      expect { loader.load("missing") }.to raise_error(RubynCode::Error, /not found/)
    end
  end

  describe "#loaded" do
    it "tracks loaded skill names" do
      allow(catalog).to receive(:find).with("commit").and_return(tmpfile.path)

      loader.load("commit")
      expect(loader.loaded).to eq(["commit"])
    end
  end
end
