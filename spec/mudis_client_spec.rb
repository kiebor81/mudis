# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe MudisClient do # rubocop:disable Metrics/BlockLength
  let(:socket_path) { MudisIPCConfig::SOCKET_PATH }
  let(:socket_class) { MudisIPCConfig.use_tcp? ? TCPSocket : UNIXSocket }
  let(:mock_socket) { instance_double(socket_class) }
  let(:client) { MudisClient.new }

  around do |example|
    ClimateControl.modify("SOCKET_PATH" => socket_path) do
      example.run
    end
  end

  before do
    if MudisIPCConfig.use_tcp?
      allow(TCPSocket).to receive(:new).and_return(mock_socket)
    else
      allow(UNIXSocket).to receive(:open).and_return(mock_socket)
    end
    allow(mock_socket).to receive(:close)
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

  describe "#inspect" do
    it "sends an inspect command and returns metadata" do
      payload = { cmd: "inspect", key: "test_key", namespace: nil }
      response = { ok: true, value: { key: "test_key", size_bytes: 10 } }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.inspect("test_key")).to eq({ key: "test_key", size_bytes: 10 })
    end
  end

  describe "#keys" do
    it "sends a keys command and returns keys" do
      payload = { cmd: "keys", namespace: "ns" }
      response = { ok: true, value: ["a", "b"] }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.keys(namespace: "ns")).to eq(["a", "b"])
    end
  end

  describe "#clear_namespace" do
    it "sends a clear_namespace command" do
      payload = { cmd: "clear_namespace", namespace: "ns" }
      response = { ok: true, value: nil }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.clear_namespace(namespace: "ns")).to be_nil
    end
  end

  describe "#least_touched" do
    it "sends a least_touched command" do
      payload = { cmd: "least_touched", limit: 5 }
      response = { ok: true, value: [["a", 0], ["b", 1]] }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.least_touched(5)).to eq([["a", 0], ["b", 1]])
    end
  end

  describe "#all_keys" do
    it "sends an all_keys command" do
      payload = { cmd: "all_keys" }
      response = { ok: true, value: ["k1"] }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.all_keys).to eq(["k1"])
    end
  end

  describe "#current_memory_bytes" do
    it "sends a current_memory_bytes command" do
      payload = { cmd: "current_memory_bytes" }
      response = { ok: true, value: 123 }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.current_memory_bytes).to eq(123)
    end
  end

  describe "#max_memory_bytes" do
    it "sends a max_memory_bytes command" do
      payload = { cmd: "max_memory_bytes" }
      response = { ok: true, value: 456 }.to_json

      expect(mock_socket).to receive(:puts).with(payload.to_json)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect(client.max_memory_bytes).to eq(456)
    end
  end

  describe "error handling" do
    it "warns when the socket is missing" do
      allow(MudisIPCConfig).to receive(:retries).and_return(1)
      if MudisIPCConfig.use_tcp?
        allow(TCPSocket).to receive(:new).and_raise(Errno::ECONNREFUSED)
      else
        allow(UNIXSocket).to receive(:open).and_raise(Errno::ENOENT)
      end

      expect { client.read("test_key") }.to output(/Cannot connect/).to_stderr
      expect(client.read("test_key")).to be_nil
    end

    it "raises an error when the server returns an error" do
      response = { ok: false, error: "Something went wrong" }.to_json

      expect(mock_socket).to receive(:puts)
      expect(mock_socket).to receive(:gets).and_return(response)

      expect { client.read("test_key") }.to raise_error("Something went wrong")
    end

    it "retries on timeout and then warns" do
      allow(MudisIPCConfig).to receive(:retries).and_return(1)
      allow(MudisIPCConfig).to receive(:timeout).and_return(0.01)

      if MudisIPCConfig.use_tcp?
        allow(TCPSocket).to receive(:new).and_raise(Timeout::Error)
      else
        allow(UNIXSocket).to receive(:open).and_raise(Timeout::Error)
      end

      expect { client.read("test_key") }.to output(/Cannot connect/).to_stderr
    end
  end
end
