# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Mudis Memory Guardrails" do
  before do
    Mudis.reset!
    Mudis.stop_expiry_thread
    Mudis.instance_variable_set(:@buckets, 1)
    Mudis.instance_variable_set(:@stores, [{}])
    Mudis.instance_variable_set(:@mutexes, [Mutex.new])
    Mudis.instance_variable_set(:@lru_heads, [nil])
    Mudis.instance_variable_set(:@lru_tails, [nil])
    Mudis.instance_variable_set(:@lru_nodes, [{}])
    Mudis.instance_variable_set(:@current_bytes, [0])

    Mudis.max_value_bytes = nil
    Mudis.instance_variable_set(:@threshold_bytes, 1_000_000)
    Mudis.hard_memory_limit = true
    Mudis.instance_variable_set(:@max_bytes, 100)
  end

  it "rejects writes that exceed max memory" do
    big_value = "a" * 90
    Mudis.write("a", big_value)
    expect(Mudis.read("a")).to eq(big_value)

    big_value2 = "b" * 90
    Mudis.write("b", big_value2)
    expect(Mudis.read("b")).to be_nil
    expect(Mudis.metrics[:rejected]).to be > 0
  end

  it "rejects updates that exceed max memory" do
    Mudis.write("a", "a" * 10)
    expect(Mudis.read("a")).to eq("a" * 10)

    Mudis.update("a") { "b" * 200 }
    expect(Mudis.read("a")).to eq("a" * 10)
    expect(Mudis.metrics[:rejected]).to be > 0
  end
end
