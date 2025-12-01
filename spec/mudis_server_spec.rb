# frozen_string_literal: true

require "socket"
require "json"

require_relative "spec_helper"

RSpec.describe MudisServer do # rubocop:disable Metrics/BlockLength
  let(:socket_path) { MudisIPCConfig::SOCKET_PATH }

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
    allow(Mudis).to receive(:metrics).and_return({ reads: 1, writes: 1 })
    allow(Mudis).to receive(:reset_metrics!)
    allow(Mudis).to receive(:reset!)
  end

  after do
    File.unlink(socket_path) if File.exist?(socket_path) && !MudisIPCConfig.use_tcp?
  end

  def send_request(request)
    if MudisIPCConfig.use_tcp?
      TCPSocket.open(MudisIPCConfig::TCP_HOST, MudisIPCConfig::TCP_PORT) do |sock|
        sock.puts(JSON.dump(request))
        JSON.parse(sock.gets, symbolize_names: true)
      end
    else
      UNIXSocket.open(socket_path) do |sock|
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

  it "handles the 'metrics' command" do
    response = send_request({ cmd: "metrics" })
    expect(response).to eq({ ok: true, value: { reads: 1, writes: 1 } })
    expect(Mudis).to have_received(:metrics)
  end

  it "handles the 'reset_metrics' command" do
    response = send_request({ cmd: "reset_metrics" })
    expect(response).to eq({ ok: true, value: nil })
    expect(Mudis).to have_received(:reset_metrics!)
  end

  it "handles the 'reset' command" do
    response = send_request({ cmd: "reset" })
    expect(response).to eq({ ok: true, value: nil })
    expect(Mudis).to have_received(:reset!)
  end

  it "handles unknown commands" do
    response = send_request({ cmd: "unknown_command" })
    expect(response[:ok]).to be false
    expect(response[:error]).to match(/unknown command/i)
  end
end
