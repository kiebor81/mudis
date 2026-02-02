# frozen_string_literal: true

require "socket"
require "json"

require_relative "spec_helper"

RSpec.describe MudisServer do # rubocop:disable Metrics/BlockLength
  unless ENV["MUDIS_RUN_IPC"] == "true"
    it "skips IPC socket tests unless MUDIS_RUN_IPC=true" do
      skip "Set MUDIS_RUN_IPC=true to run IPC socket tests"
    end
    next
  end

  before(:all) do
    # Start the server once for all tests
    Thread.new { MudisServer.start! }
    sleep 0.2 # Allow the server to start
  end

  before(:each) do
    allow(Mudis).to receive(:read).and_return("mock_value")
    allow(Mudis).to receive(:write)
    allow(Mudis).to receive(:delete)
    allow(Mudis).to receive(:exists?).and_return(true)
    allow(Mudis).to receive(:fetch).and_return("mock_fetched_value")
    allow(Mudis).to receive(:inspect).and_return({ key: "test_key", size_bytes: 10 })
    allow(Mudis).to receive(:keys).and_return(["a", "b"])
    allow(Mudis).to receive(:clear_namespace)
    allow(Mudis).to receive(:least_touched).and_return([["a", 0]])
    allow(Mudis).to receive(:all_keys).and_return(["k1"])
    allow(Mudis).to receive(:current_memory_bytes).and_return(123)
    allow(Mudis).to receive(:max_memory_bytes).and_return(456)
    allow(Mudis).to receive(:metrics).and_return({ reads: 1, writes: 1 })
  end

  after(:all) do
    socket_path = MudisIPCConfig::SOCKET_PATH
    File.unlink(socket_path) if File.exist?(socket_path) && !MudisIPCConfig.use_tcp?
  end

  def send_request(request)
    if MudisIPCConfig.use_tcp?
      TCPSocket.open(MudisIPCConfig::TCP_HOST, MudisIPCConfig::TCP_PORT) do |sock|
        sock.puts(JSON.dump(request))
        JSON.parse(sock.gets, symbolize_names: true)
      end
    else
      UNIXSocket.open(MudisIPCConfig::SOCKET_PATH) do |sock|
        sock.puts(JSON.dump(request))
        JSON.parse(sock.gets, symbolize_names: true)
      end
    end
  end

  it "handles the 'read' command" do
    response = send_request({ cmd: "read", key: "test_key", namespace: "test_ns" })
    expect(response).to eq({ ok: true, value: "mock_value" })
    expect(Mudis).to have_received(:read).with("test_key", namespace: "test_ns")
  end

  it "handles the 'write' command" do
    response = send_request({ cmd: "write", key: "test_key", value: "test_value", ttl: 60, namespace: "test_ns" })
    expect(response).to eq({ ok: true, value: nil })
    expect(Mudis).to have_received(:write).with("test_key", "test_value", expires_in: 60, namespace: "test_ns")
  end

  it "handles the 'delete' command" do
    response = send_request({ cmd: "delete", key: "test_key", namespace: "test_ns" })
    expect(response).to eq({ ok: true, value: nil })
    expect(Mudis).to have_received(:delete).with("test_key", namespace: "test_ns")
  end

  it "handles the 'exists' command" do
    response = send_request({ cmd: "exists", key: "test_key", namespace: "test_ns" })
    expect(response).to eq({ ok: true, value: true })
    expect(Mudis).to have_received(:exists?).with("test_key", namespace: "test_ns")
  end

  it "handles the 'fetch' command" do
    response = send_request({ cmd: "fetch", key: "test_key", ttl: 60, namespace: "test_ns",
                              fallback: "fallback_value" })
    expect(response).to eq({ ok: true, value: "mock_fetched_value" })
    expect(Mudis).to have_received(:fetch).with("test_key", expires_in: 60, namespace: "test_ns")
  end

  it "handles the 'inspect' command" do
    response = send_request({ cmd: "inspect", key: "test_key", namespace: "test_ns" })
    expect(response).to eq({ ok: true, value: { key: "test_key", size_bytes: 10 } })
    expect(Mudis).to have_received(:inspect).with("test_key", namespace: "test_ns")
  end

  it "handles the 'keys' command" do
    response = send_request({ cmd: "keys", namespace: "test_ns" })
    expect(response).to eq({ ok: true, value: ["a", "b"] })
    expect(Mudis).to have_received(:keys).with(namespace: "test_ns")
  end

  it "handles the 'clear_namespace' command" do
    response = send_request({ cmd: "clear_namespace", namespace: "test_ns" })
    expect(response).to eq({ ok: true, value: nil })
    expect(Mudis).to have_received(:clear_namespace).with(namespace: "test_ns")
  end

  it "handles the 'least_touched' command" do
    response = send_request({ cmd: "least_touched", limit: 5 })
    expect(response).to eq({ ok: true, value: [["a", 0]] })
    expect(Mudis).to have_received(:least_touched).with(5)
  end

  it "handles the 'all_keys' command" do
    response = send_request({ cmd: "all_keys" })
    expect(response).to eq({ ok: true, value: ["k1"] })
    expect(Mudis).to have_received(:all_keys)
  end

  it "handles the 'current_memory_bytes' command" do
    response = send_request({ cmd: "current_memory_bytes" })
    expect(response).to eq({ ok: true, value: 123 })
    expect(Mudis).to have_received(:current_memory_bytes)
  end

  it "handles the 'max_memory_bytes' command" do
    response = send_request({ cmd: "max_memory_bytes" })
    expect(response).to eq({ ok: true, value: 456 })
    expect(Mudis).to have_received(:max_memory_bytes)
  end

  it "handles the 'metrics' command" do
    response = send_request({ cmd: "metrics" })
    expect(response).to eq({ ok: true, value: { reads: 1, writes: 1 } })
    expect(Mudis).to have_received(:metrics)
  end

  it "handles unknown commands" do
    response = send_request({ cmd: "unknown_command" })
    expect(response[:ok]).to be false
    expect(response[:error]).to match(/unknown command/i)
  end
end
