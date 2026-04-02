# frozen_string_literal: true

require "tmpdir"

RSpec.describe RubynCode::Context::AutoCompact do
  let(:llm_client) { double("llm_client") }
  let(:messages) { [{ role: "user", content: "Hello" }, { role: "assistant", content: "Hi" }] }

  describe ".call" do
    before do
      allow(llm_client).to receive(:respond_to?).with(:chat).and_return(true)
      allow(llm_client).to receive(:chat).and_return("Summary of conversation")
    end

    it "returns a single-element array with the summary" do
      result = described_class.call(messages, llm_client: llm_client)

      expect(result.length).to eq(1)
      expect(result.first[:role]).to eq("user")
      expect(result.first[:content]).to include("Summary of conversation")
      expect(result.first[:content]).to include("[Context compacted]")
    end

    it "calls the LLM client for summarization" do
      described_class.call(messages, llm_client: llm_client)

      expect(llm_client).to have_received(:chat).once
    end

    it "saves transcript to disk when transcript_dir is given" do
      Dir.mktmpdir do |dir|
        described_class.call(messages, llm_client: llm_client, transcript_dir: dir)

        files = Dir.glob(File.join(dir, "transcript_*.json"))
        expect(files.length).to eq(1)

        saved = JSON.parse(File.read(files.first))
        expect(saved.length).to eq(2)
      end
    end
  end
end
