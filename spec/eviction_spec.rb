# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Mudis LRU Eviction" do
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
    Mudis.hard_memory_limit = false
    Mudis.instance_variable_set(:@threshold_bytes, 60)
    Mudis.max_value_bytes = 100
  end

  it "evicts old entries when size limit is reached" do
    Mudis.write("a", "a" * 50)
    Mudis.write("b", "b" * 50)

    expect(Mudis.read("a")).to be_nil
    expect(Mudis.read("b")).not_to be_nil
  end
end
