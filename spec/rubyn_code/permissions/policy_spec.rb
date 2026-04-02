# frozen_string_literal: true

RSpec.describe RubynCode::Permissions::Policy do
  let(:deny_list) { RubynCode::Permissions::DenyList.new }

  before do
    stub_tool = Class.new(RubynCode::Tools::Base) do
      const_set(:TOOL_NAME, "test_tool")
      const_set(:RISK_LEVEL, :read)
    end
    allow(RubynCode::Tools::Registry).to receive(:get).with("test_tool").and_return(stub_tool)

    write_tool = Class.new(RubynCode::Tools::Base) do
      const_set(:TOOL_NAME, "write_tool")
      const_set(:RISK_LEVEL, :write)
    end
    allow(RubynCode::Tools::Registry).to receive(:get).with("write_tool").and_return(write_tool)

    ext_tool = Class.new(RubynCode::Tools::Base) do
      const_set(:TOOL_NAME, "ext_tool")
      const_set(:RISK_LEVEL, :external)
    end
    allow(RubynCode::Tools::Registry).to receive(:get).with("ext_tool").and_return(ext_tool)

    danger_tool = Class.new(RubynCode::Tools::Base) do
      const_set(:TOOL_NAME, "danger_tool")
      const_set(:RISK_LEVEL, :destructive)
    end
    allow(RubynCode::Tools::Registry).to receive(:get).with("danger_tool").and_return(danger_tool)
  end

  def check(tool, tier)
    described_class.check(tool_name: tool, tool_input: {}, tier: tier, deny_list: deny_list)
  end

  it "returns :deny when the deny list blocks the tool" do
    deny_list.add_name("test_tool")
    expect(check("test_tool", :unrestricted)).to eq(:deny)
  end

  it "returns :ask for destructive tools regardless of tier" do
    expect(check("danger_tool", :unrestricted)).to eq(:ask)
  end

  it "returns :ask for everything in ask_always tier" do
    expect(check("test_tool", :ask_always)).to eq(:ask)
  end

  it "returns :allow for read tools in allow_read tier" do
    expect(check("test_tool", :allow_read)).to eq(:allow)
  end

  it "returns :ask for write tools in allow_read tier" do
    expect(check("write_tool", :allow_read)).to eq(:ask)
  end

  it "returns :allow for write tools in autonomous tier" do
    expect(check("write_tool", :autonomous)).to eq(:allow)
  end

  it "returns :ask for external tools in autonomous tier" do
    expect(check("ext_tool", :autonomous)).to eq(:ask)
  end

  it "returns :allow for everything in unrestricted tier" do
    expect(check("ext_tool", :unrestricted)).to eq(:allow)
  end
end
