# frozen_string_literal: true

require "spec_helper"
require "json"
require "json_schemer"

RSpec.describe "IDE Protocol Contract", :contract do
  let(:schema_path) { File.join(__dir__, "../../../protocol/schema.json") }
  let(:schema_json) { JSON.parse(File.read(schema_path)) }
  let(:fixtures_dir) { File.join(__dir__, "../../../protocol/fixtures") }

  describe "schema validity" do
    it "loads without errors" do
      expect(schema_json).to be_a(Hash)
      expect(schema_json["$defs"]).to be_a(Hash)
    end

    it "contains all expected method definitions" do
      defs = schema_json["$defs"]

      # Client → Server requests
      %w[
        initialize_params initialize_result
        prompt_params prompt_result
        cancel_params cancel_result
        review_params review_result
        approve_tool_use_params approve_tool_use_result
        accept_edit_params accept_edit_result
        shutdown_result
        config_get_params config_get_result
        config_set_params config_set_result
        models_list_result
        session_reset_params session_reset_result
      ].each do |def_name|
        expect(defs).to have_key(def_name), "Missing $def: #{def_name}"
      end

      # Server → Client notifications
      %w[
        stream_text_params agent_status_params
        tool_use_params tool_result_params
        file_edit_params file_create_params
        review_finding_params session_cost_params
        config_changed_params
      ].each do |def_name|
        expect(defs).to have_key(def_name), "Missing $def: #{def_name}"
      end

      # IDE RPC (server → client requests)
      %w[
        ide_open_diff_params ide_open_diff_result
        ide_read_selection_result
        ide_read_active_file_result
        ide_save_file_params ide_save_file_result
        ide_navigate_to_params
        ide_get_open_tabs_result
        ide_get_diagnostics_params ide_get_diagnostics_result
        ide_get_workspace_symbols_params ide_get_workspace_symbols_result
      ].each do |def_name|
        expect(defs).to have_key(def_name), "Missing $def: #{def_name}"
      end

      # Session management
      %w[
        session_list_params session_list_result
        session_resume_params session_resume_result
        session_fork_params session_fork_result
      ].each do |def_name|
        expect(defs).to have_key(def_name), "Missing $def: #{def_name}"
      end
    end
  end

  describe "fixture validation" do
    fixture_files = Dir[File.join(File.expand_path("../../../protocol/fixtures", __dir__), "*.json")]

    fixture_files.each do |fixture_path|
      fixture_name = File.basename(fixture_path, ".json")

      context "fixture: #{fixture_name}" do
        let(:fixture) { JSON.parse(File.read(fixture_path)) }

        it "has valid structure" do
          expect(fixture).to have_key("description")
          expect(fixture).to have_key("steps")
          expect(fixture["steps"]).to be_an(Array)
          expect(fixture["steps"]).not_to be_empty
        end

        it "all steps have valid direction and type" do
          fixture["steps"].each_with_index do |step, idx|
            expect(%w[client_to_server server_to_client]).to include(step["direction"]),
              "Step #{idx}: invalid direction '#{step['direction']}'"
            expect(%w[request response notification]).to include(step["type"]),
              "Step #{idx}: invalid type '#{step['type']}'"
          end
        end

        it "all messages are valid JSON-RPC 2.0" do
          fixture["steps"].each_with_index do |step, idx|
            msg = step["message"]
            expect(msg["jsonrpc"]).to eq("2.0"),
              "Step #{idx}: missing jsonrpc version"

            case step["type"]
            when "request"
              expect(msg).to have_key("id"), "Step #{idx}: request missing id"
              expect(msg).to have_key("method"), "Step #{idx}: request missing method"
            when "response"
              expect(msg).to have_key("id"), "Step #{idx}: response missing id"
              expect(msg.key?("result") || msg.key?("error")).to be(true),
                "Step #{idx}: response missing result or error"
            when "notification"
              expect(msg).to have_key("method"), "Step #{idx}: notification missing method"
              expect(msg).not_to have_key("id"), "Step #{idx}: notification should not have id"
            end
          end
        end

        it "params and results validate against schema $defs" do
          fixture["steps"].each_with_index do |step, idx|
            # Validate params against schema
            if step["validate_params"]
              def_name = step["validate_params"]
              sub_schema = schema_json["$defs"][def_name]
              expect(sub_schema).not_to be_nil, "Step #{idx}: unknown $def '#{def_name}'"

              # Build a schema document that references the $def
              full_schema = {
                "$schema" => "https://json-schema.org/draft/2020-12/schema",
                "$defs" => schema_json["$defs"],
                "$ref" => "#/$defs/#{def_name}"
              }
              schemer = JSONSchemer.schema(full_schema)
              params = step["message"]["params"] || {}

              errors = schemer.validate(params).to_a
              expect(errors).to be_empty,
                "Step #{idx}: params failed #{def_name} validation:\n#{errors.map { |e| e["error"] }.join("\n")}"
            end

            # Validate result against schema
            if step["validate_result"]
              def_name = step["validate_result"]
              sub_schema = schema_json["$defs"][def_name]
              expect(sub_schema).not_to be_nil, "Step #{idx}: unknown $def '#{def_name}'"

              full_schema = {
                "$schema" => "https://json-schema.org/draft/2020-12/schema",
                "$defs" => schema_json["$defs"],
                "$ref" => "#/$defs/#{def_name}"
              }
              schemer = JSONSchemer.schema(full_schema)
              result = step["message"]["result"]

              errors = schemer.validate(result).to_a
              expect(errors).to be_empty,
                "Step #{idx}: result failed #{def_name} validation:\n#{errors.map { |e| e["error"] }.join("\n")}"
            end
          end
        end
      end
    end
  end
end
