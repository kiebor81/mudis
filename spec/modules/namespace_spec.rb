# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Mudis::Namespace do
  let(:test_class) do
    Class.new do
      extend Mudis::Namespace
      
      @buckets = 2
      @mutexes = Array.new(2) { Mutex.new }
      @stores = [
        { "ns1:key1" => {}, "ns1:key2" => {}, "key3" => {} },
        { "ns2:key1" => {}, "other" => {} }
      ]
      @lru_nodes = Array.new(2) { {} }
      @current_bytes = Array.new(2, 0)
      
      class << self
        attr_accessor :buckets, :mutexes, :stores, :lru_nodes, :current_bytes
        
        def all_keys
          @stores.flat_map(&:keys)
        end
        
        def evict_key(idx, key)
          @stores[idx].delete(key)
        end
      end
    end
  end

  describe "#keys" do
    it "returns all keys for a given namespace" do
      keys = test_class.keys(namespace: "ns1")
      
      expect(keys).to contain_exactly("key1", "key2")
    end

    it "returns empty array if no keys exist for namespace" do
      keys = test_class.keys(namespace: "nonexistent")
      
      expect(keys).to eq([])
    end

    it "raises error if namespace is nil" do
      expect { test_class.keys(namespace: nil) }.to raise_error(ArgumentError, "namespace is required")
    end

    it "strips namespace prefix from returned keys" do
      keys = test_class.keys(namespace: "ns2")
      
      expect(keys).to eq(["key1"])
      expect(keys).not_to include("ns2:key1")
    end
  end

  describe "#clear_namespace" do
    it "deletes all keys in a given namespace" do
      test_class.clear_namespace(namespace: "ns1")
      
      expect(test_class.stores[0]).not_to have_key("ns1:key1")
      expect(test_class.stores[0]).not_to have_key("ns1:key2")
      expect(test_class.stores[0]).to have_key("key3") # non-namespaced key remains
    end

    it "does nothing if namespace has no keys" do
      expect { test_class.clear_namespace(namespace: "nonexistent") }.not_to raise_error
    end

    it "raises error if namespace is nil" do
      expect { test_class.clear_namespace(namespace: nil) }.to raise_error(ArgumentError, "namespace is required")
    end

    it "only deletes keys with exact namespace prefix" do
      test_class.stores[0]["ns1_similar"] = {}
      
      test_class.clear_namespace(namespace: "ns1")
      
      expect(test_class.stores[0]).to have_key("ns1_similar")
    end
  end

  describe "#with_namespace" do
    it "sets thread-local namespace for the block" do
      test_class.with_namespace("test_ns") do
        expect(Thread.current[:mudis_namespace]).to eq("test_ns")
      end
    end

    it "restores previous namespace after block" do
      Thread.current[:mudis_namespace] = "original"
      
      test_class.with_namespace("temporary") do
        # inside block
      end
      
      expect(Thread.current[:mudis_namespace]).to eq("original")
    end

    it "restores namespace even if block raises error" do
      Thread.current[:mudis_namespace] = "original"
      
      expect do
        test_class.with_namespace("temporary") do
          raise "test error"
        end
      end.to raise_error("test error")
      
      expect(Thread.current[:mudis_namespace]).to eq("original")
    end

    it "returns the block's return value" do
      result = test_class.with_namespace("test") do
        "block_result"
      end
      
      expect(result).to eq("block_result")
    end
  end

  describe "#namespaced_key (private)" do
    it "prefixes key with namespace" do
      result = test_class.send(:namespaced_key, "mykey", "mynamespace")
      
      expect(result).to eq("mynamespace:mykey")
    end

    it "returns unprefixed key when namespace is nil" do
      Thread.current[:mudis_namespace] = nil
      
      result = test_class.send(:namespaced_key, "mykey", nil)
      
      expect(result).to eq("mykey")
    end

    it "uses thread-local namespace when explicit namespace is nil" do
      Thread.current[:mudis_namespace] = "thread_ns"
      
      result = test_class.send(:namespaced_key, "mykey", nil)
      
      expect(result).to eq("thread_ns:mykey")
    ensure
      Thread.current[:mudis_namespace] = nil
    end

    it "prefers explicit namespace over thread-local" do
      Thread.current[:mudis_namespace] = "thread_ns"
      
      result = test_class.send(:namespaced_key, "mykey", "explicit_ns")
      
      expect(result).to eq("explicit_ns:mykey")
    ensure
      Thread.current[:mudis_namespace] = nil
    end
  end
end
