# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Mudis Public API" do
  describe "ensures no breaking changes" do
    it "exposes all core cache operations" do
      expect(Mudis).to respond_to(:read)
      expect(Mudis).to respond_to(:write)
      expect(Mudis).to respond_to(:delete)
      expect(Mudis).to respond_to(:exists?)
      expect(Mudis).to respond_to(:update)
      expect(Mudis).to respond_to(:fetch)
      expect(Mudis).to respond_to(:clear)
      expect(Mudis).to respond_to(:replace)
      expect(Mudis).to respond_to(:inspect)
    end

    it "exposes all configuration methods" do
      expect(Mudis).to respond_to(:configure)
      expect(Mudis).to respond_to(:config)
      expect(Mudis).to respond_to(:serializer)
      expect(Mudis).to respond_to(:serializer=)
      expect(Mudis).to respond_to(:compress)
      expect(Mudis).to respond_to(:compress=)
      expect(Mudis).to respond_to(:max_bytes)
      expect(Mudis).to respond_to(:max_bytes=)
      expect(Mudis).to respond_to(:max_value_bytes)
      expect(Mudis).to respond_to(:max_value_bytes=)
      expect(Mudis).to respond_to(:hard_memory_limit)
      expect(Mudis).to respond_to(:hard_memory_limit=)
      expect(Mudis).to respond_to(:max_ttl)
      expect(Mudis).to respond_to(:max_ttl=)
      expect(Mudis).to respond_to(:default_ttl)
      expect(Mudis).to respond_to(:default_ttl=)
    end

    it "exposes all metrics methods" do
      expect(Mudis).to respond_to(:metrics)
      expect(Mudis).to respond_to(:reset_metrics!)
    end

    it "exposes all expiry methods" do
      expect(Mudis).to respond_to(:start_expiry_thread)
      expect(Mudis).to respond_to(:stop_expiry_thread)
      expect(Mudis).to respond_to(:cleanup_expired!)
    end

    it "exposes all namespace methods" do
      expect(Mudis).to respond_to(:keys)
      expect(Mudis).to respond_to(:clear_namespace)
      expect(Mudis).to respond_to(:with_namespace)
    end

    it "exposes all persistence methods" do
      expect(Mudis).to respond_to(:save_snapshot!)
      expect(Mudis).to respond_to(:load_snapshot!)
    end

    it "exposes all utility methods" do
      expect(Mudis).to respond_to(:reset!)
      expect(Mudis).to respond_to(:all_keys)
      expect(Mudis).to respond_to(:current_memory_bytes)
      expect(Mudis).to respond_to(:max_memory_bytes)
      expect(Mudis).to respond_to(:least_touched)
      expect(Mudis).to respond_to(:buckets)
    end

    it "maintains backward compatibility with method signatures" do
      # Core operations accept namespace parameter
      expect(Mudis.method(:read).parameters).to include([:key, :namespace])
      expect(Mudis.method(:write).parameters).to include([:key, :namespace])
      expect(Mudis.method(:delete).parameters).to include([:key, :namespace])
      expect(Mudis.method(:exists?).parameters).to include([:key, :namespace])
      
      # Fetch accepts expires_in, force, and namespace
      expect(Mudis.method(:fetch).parameters).to include([:key, :expires_in])
      expect(Mudis.method(:fetch).parameters).to include([:key, :force])
      expect(Mudis.method(:fetch).parameters).to include([:key, :namespace])
    end

    it "verifies LRUNode class is still accessible" do
      expect(defined?(Mudis::LRUNode)).to be_truthy
      node = Mudis::LRUNode.new("test_key")
      expect(node).to respond_to(:key)
      expect(node).to respond_to(:prev)
      expect(node).to respond_to(:next)
    end

    it "verifies all public methods work correctly" do
      Mudis.reset!
      
      # Write and read
      Mudis.write("test", "value")
      expect(Mudis.read("test")).to eq("value")
      
      # Exists
      expect(Mudis.exists?("test")).to be true
      
      # Update
      Mudis.update("test") { |v| v.upcase }
      expect(Mudis.read("test")).to eq("VALUE")
      
      # Fetch
      result = Mudis.fetch("new_key") { "new_value" }
      expect(result).to eq("new_value")
      
      # Replace
      Mudis.replace("test", "replaced")
      expect(Mudis.read("test")).to eq("replaced")
      
      # Inspect
      meta = Mudis.inspect("test")
      expect(meta).to include(:key, :bucket, :created_at, :size_bytes)
      
      # Namespace operations
      Mudis.write("k1", "v1", namespace: "ns1")
      expect(Mudis.keys(namespace: "ns1")).to include("k1")
      
      Mudis.with_namespace("ns2") do
        Mudis.write("k2", "v2")
      end
      expect(Mudis.keys(namespace: "ns2")).to include("k2")
      
      # Clear namespace
      Mudis.clear_namespace(namespace: "ns1")
      expect(Mudis.keys(namespace: "ns1")).to be_empty
      
      # Metrics
      metrics = Mudis.metrics
      expect(metrics).to include(:hits, :misses, :evictions, :total_memory, :buckets)
      
      # Least touched
      touched = Mudis.least_touched(5)
      expect(touched).to be_an(Array)
      
      # All keys
      keys = Mudis.all_keys
      expect(keys).to be_an(Array)
      
      # Memory tracking
      expect(Mudis.current_memory_bytes).to be > 0
      expect(Mudis.max_memory_bytes).to be > 0
      
      # Delete
      Mudis.delete("test")
      expect(Mudis.exists?("test")).to be false
      
      # Clear (alias for delete)
      Mudis.write("to_clear", "value")
      Mudis.clear("to_clear")
      expect(Mudis.exists?("to_clear")).to be false
    end
  end
end
