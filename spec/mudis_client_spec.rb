# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe MudisClient do # rubocop:disable Metrics/BlockLength
  let(:socket_path) { "/tmp/mudis.sock" }
  let(:mock_socket) { instance_double(UNIXSocket) }
  let(:client) { MudisClient.new }

  around do |example|
    ClimateControl.modify("SOCKET_PATH" => socket_path) do
      example.run
    end
  end

  before do
    allow(UNIXSocket).to receive(:open).and_yield(mock_socket)
  end

  describe "#read" do
    it "sends a read command and returns the value" do
      payload = { cmd: "read", key: "test_key", namespace: nil }
      response = { ok: true, value: "test_value" }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.read("test_key")).to eq("test_value")
    end
  end

  describe "#write" do
    it "sends a write command and returns the value" do
      payload = { cmd: "write", key: "test_key", value: "test_value", ttl: nil, namespace: nil }
      response = { ok: true, value: nil }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.write("test_key", "test_value")).to be_nil
    end
  end

  describe "#delete" do
    it "sends a delete command and returns the value" do
      payload = { cmd: "delete", key: "test_key", namespace: nil }
      response = { ok: true, value: nil }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.delete("test_key")).to be_nil
    end
  end

  describe "#exists?" do
    it "sends an exists command and returns true" do
      payload = { cmd: "exists", key: "test_key", namespace: nil }
      response = { ok: true, value: true }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.exists?("test_key")).to eq(true)
    end
  end

  describe "#fetch" do
    it "fetches an existing value or writes a new one" do
      read_response = { ok: true, value: nil }.to_json
      write_payload = { cmd: "write", key: "test_key", value: "new_value", ttl: nil, namespace: nil }
      write_response = { ok: true, value: nil }.to_json

      expect(mock_socket).to receive(:puts).with({ cmd: "read", key: "test_key", namespace: nil }.to_json)
      expect(mock_socket).to receive(:gets).and_return(read_response)
      expect(mock_socket).to receive(:puts).with(write_payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(write_response)

      result = client.fetch("test_key") { "new_value" } # rubocop:disable Style/RedundantFetchBlock
      expect(result).to eq("new_value")
    end
  end

  describe "#metrics" do
    it "sends a metrics command and returns the metrics" do
      payload = { cmd: "metrics" }
      response = { ok: true, value: { reads: 10, writes: 5 } }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.metrics).to eq({ reads: 10, writes: 5 })
    end
  end

  describe "#reset_metrics!" do
    it "sends a reset_metrics command" do
      payload = { cmd: "reset_metrics" }
      response = { ok: true, value: nil }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.reset_metrics!).to be_nil
    end
  end

  describe "#reset!" do
    it "sends a reset command" do
      payload = { cmd: "reset" }
      response = { ok: true, value: nil }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.reset!).to be_nil
    end
  end

  describe "error handling" do
    it "warns when the socket is missing" do
      allow(UNIXSocket).to receive(:open).and_raise(Errno::ENOENT)

      expect { client.read("test_key") }.to output(/Socket missing/).to_stderr
      expect(client.read("test_key")).to be_nil
    end

    it "raises an error when the server returns an error" do
      response = { ok: false, error: "Something went wrong" }.to_json

      expect(mock_socket).to receive(:puts)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect { client.read("test_key") }.to raise_error("Something went wrong")
    end
  end
end
