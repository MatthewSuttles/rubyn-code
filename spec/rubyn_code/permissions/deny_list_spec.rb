# frozen_string_literal: true

RSpec.describe RubynCode::Permissions::DenyList do
  subject(:deny_list) { described_class.new(names: ["rm_rf"], prefixes: ["mcp_"]) }

  describe "#blocks?" do
    it "blocks an exact name match" do
      expect(deny_list.blocks?("rm_rf")).to be true
    end

    it "blocks a tool matching a prefix" do
      expect(deny_list.blocks?("mcp_deploy")).to be true
    end

    it "does not block an unrelated tool" do
      expect(deny_list.blocks?("read_file")).to be false
    end
  end

  describe "#add_name" do
    it "adds a name and blocks it" do
      deny_list.add_name("dangerous")
      expect(deny_list.blocks?("dangerous")).to be true
    end

    it "returns self for chaining" do
      expect(deny_list.add_name("x")).to be deny_list
    end
  end

  describe "#add_prefix" do
    it "adds a prefix and blocks matching tools" do
      deny_list.add_prefix("evil_")
      expect(deny_list.blocks?("evil_tool")).to be true
    end
  end

  describe "#remove_name" do
    it "removes a name so it is no longer blocked" do
      deny_list.remove_name("rm_rf")
      expect(deny_list.blocks?("rm_rf")).to be false
    end

    it "returns self for chaining" do
      expect(deny_list.remove_name("rm_rf")).to be deny_list
    end
  end
end
