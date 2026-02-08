# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Mudis do # rubocop:disable Metrics/BlockLength
  before(:each) do
    Mudis.stop_expiry_thread
    Mudis.instance_variable_set(:@buckets, nil)
    Mudis.instance_variable_set(:@stores, Array.new(Mudis.buckets) { {} })
    Mudis.instance_variable_set(:@mutexes, Array.new(Mudis.buckets) { Mutex.new })
    Mudis.instance_variable_set(:@lru_heads, Array.new(Mudis.buckets) { nil })
    Mudis.instance_variable_set(:@lru_tails, Array.new(Mudis.buckets) { nil })
    Mudis.instance_variable_set(:@lru_nodes, Array.new(Mudis.buckets) { {} })
    Mudis.instance_variable_set(:@current_bytes, Array.new(Mudis.buckets, 0))
    Mudis.instance_variable_set(:@metrics, { hits: 0, misses: 0, evictions: 0, rejected: 0 })
    Mudis.serializer = JSON
    Mudis.compress = false
    Mudis.max_value_bytes = nil
  end

  describe ".write and .read" do
    it "writes and reads a value" do
      Mudis.write("foo", { bar: "baz" })
      result = Mudis.read("foo")
      expect(result).to eq({ "bar" => "baz" })
    end

    it "returns nil for non-existent keys" do
      expect(Mudis.read("nope")).to be_nil
    end
  end

  describe ".exists?" do
    it "returns true if key exists" do
      Mudis.write("check", [1, 2, 3])
      expect(Mudis.exists?("check")).to be true
    end

    it "returns false if key does not exist" do
      expect(Mudis.exists?("missing")).to be false
    end
  end

  describe ".delete" do
    it "deletes a key" do
      Mudis.write("temp", 42)
      Mudis.delete("temp")
      expect(Mudis.read("temp")).to be_nil
    end
  end

  describe ".update" do
    it "updates a cached value" do
      Mudis.write("counter", 5)
      Mudis.update("counter") { |v| v + 1 }
      expect(Mudis.read("counter")).to eq(6)
    end

    it "refreshes TTL based on original duration" do
      Mudis.write("ttl_key", "v", expires_in: 2)
      meta_before = Mudis.inspect("ttl_key")
      original_ttl = meta_before[:expires_at] - meta_before[:created_at]

      sleep 1
      Mudis.update("ttl_key") { |v| v }
      meta_after = Mudis.inspect("ttl_key")

      expect(meta_after[:created_at]).to be > meta_before[:created_at]
      expect(meta_after[:expires_at]).to be_within(0.5).of(Time.now + original_ttl)
    end
  end

  describe ".fetch" do
    it "returns cached value if exists" do
      Mudis.write("k", 123)
      result = Mudis.fetch("k", expires_in: 60) { 999 } # fix: use keyword arg
      expect(result).to eq(123)
    end

    it "writes and returns block result if missing" do
      Mudis.delete("k")
      result = Mudis.fetch("k", expires_in: 60) { 999 } # fix
      expect(result).to eq(999)
      expect(Mudis.read("k")).to eq(999)
    end

    it "forces overwrite if force: true" do
      Mudis.write("k", 100)
      result = Mudis.fetch("k", force: true) { 200 } # fix
      expect(result).to eq(200)
    end

    it "executes the block once with singleflight: true" do
      Mudis.delete("sf")
      count = 0
      count_mutex = Mutex.new
      results = []
      results_mutex = Mutex.new

      threads = 5.times.map do
        Thread.new do
          value = Mudis.fetch("sf", singleflight: true) do
            count_mutex.synchronize { count += 1 }
            sleep 0.05
            "v"
          end
          results_mutex.synchronize { results << value }
        end
      end

      threads.each(&:join)
      expect(count).to eq(1)
      expect(results).to all(eq("v"))
      expect(Mudis.read("sf")).to eq("v")
    end
  end

  describe ".clear" do
    it "removes a key from the cache" do
      Mudis.write("to_clear", 123)
      expect(Mudis.read("to_clear")).to eq(123)
      Mudis.clear("to_clear")
      expect(Mudis.read("to_clear")).to be_nil
    end
  end

  describe ".replace" do
    it "replaces value only if key exists" do
      Mudis.write("to_replace", 100)
      Mudis.replace("to_replace", 200)
      expect(Mudis.read("to_replace")).to eq(200)

      Mudis.delete("to_replace")
      Mudis.replace("to_replace", 300)
      expect(Mudis.read("to_replace")).to be_nil
    end
  end

  describe ".inspect" do
    it "returns metadata for a cached key" do
      Mudis.write("key1", "abc", expires_in: 60)
      meta = Mudis.inspect("key1")

      expect(meta).to include(:key, :bucket, :expires_at, :created_at, :size_bytes, :compressed)
      expect(meta[:key]).to eq("key1")
      expect(meta[:compressed]).to eq(false)
    end

    it "returns nil for missing key" do
      expect(Mudis.inspect("unknown")).to be_nil
    end
  end

  describe "expiry handling" do
    it "expires values after specified time" do
      Mudis.write("short_lived", "gone soon", expires_in: 1)
      sleep 2
      expect(Mudis.read("short_lived")).to be_nil
    end
  end

  describe ".all_keys" do
    it "lists all stored keys" do
      Mudis.write("k1", 1)
      Mudis.write("k2", 2)
      expect(Mudis.all_keys).to include("k1", "k2")
    end
  end

  it "respects max_bytes when updated externally" do
    Mudis.max_bytes = 100
    expect(Mudis.send(:max_bytes)).to eq(100)
  end

  describe ".current_memory_bytes" do
    it "returns a non-zero byte count after writes" do
      Mudis.configure do |c|
        c.max_value_bytes = nil
        c.hard_memory_limit = false
      end

      Mudis.write("size_test", "a" * 100)
      expect(Mudis.current_memory_bytes).to be > 0
    end
  end

  describe ".least_touched" do
    it "returns keys with lowest read access counts" do
      Mudis.reset!
      Mudis.write("a", 1)
      Mudis.write("b", 2)
      Mudis.write("c", 3)

      Mudis.read("a")
      Mudis.read("a")
      Mudis.read("b")

      least = Mudis.least_touched(2)
      expect(least.map(&:first)).to include("c") # Never read
      expect(least.first.last).to eq(0)
    end
  end

  describe ".configure" do
    it "applies configuration settings correctly" do
      Mudis.configure do |c|
        c.serializer = JSON
        c.compress = true
        c.max_value_bytes = 12_345
        c.hard_memory_limit = true
        c.max_bytes = 987_654
      end

      expect(Mudis.compress).to eq(true)
      expect(Mudis.max_value_bytes).to eq(12_345)
      expect(Mudis.hard_memory_limit).to eq(true)
      expect(Mudis.max_bytes).to eq(987_654)
    end
  end
end
