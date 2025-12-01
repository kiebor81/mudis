# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Mudis::LRU do
  let(:test_class) do
    Class.new do
      extend Mudis::LRU
      
      @stores = Array.new(2) { {} }
      @lru_heads = Array.new(2) { nil }
      @lru_tails = Array.new(2) { nil }
      @lru_nodes = Array.new(2) { {} }
      @current_bytes = Array.new(2, 0)
      
      class << self
        attr_accessor :stores, :lru_heads, :lru_tails, :lru_nodes, :current_bytes
      end
    end
  end

  describe "LRUNode" do
    it "initializes with a key" do
      node = Mudis::LRUNode.new("test_key")
      
      expect(node.key).to eq("test_key")
      expect(node.prev).to be_nil
      expect(node.next).to be_nil
    end

    it "allows setting prev and next" do
      node1 = Mudis::LRUNode.new("key1")
      node2 = Mudis::LRUNode.new("key2")
      
      node1.next = node2
      node2.prev = node1
      
      expect(node1.next).to eq(node2)
      expect(node2.prev).to eq(node1)
    end
  end

  describe "#insert_lru (private)" do
    it "inserts a node at the head of the LRU list" do
      test_class.send(:insert_lru, 0, "key1")
      
      expect(test_class.lru_heads[0]).to be_a(Mudis::LRUNode)
      expect(test_class.lru_heads[0].key).to eq("key1")
      expect(test_class.lru_tails[0]).to eq(test_class.lru_heads[0])
      expect(test_class.lru_nodes[0]["key1"]).to be_a(Mudis::LRUNode)
    end

    it "maintains order when inserting multiple nodes" do
      test_class.send(:insert_lru, 0, "key1")
      test_class.send(:insert_lru, 0, "key2")
      test_class.send(:insert_lru, 0, "key3")
      
      expect(test_class.lru_heads[0].key).to eq("key3")
      expect(test_class.lru_tails[0].key).to eq("key1")
    end
  end

  describe "#promote_lru (private)" do
    it "moves a node to the head of the LRU list" do
      test_class.send(:insert_lru, 0, "key1")
      test_class.send(:insert_lru, 0, "key2")
      test_class.send(:insert_lru, 0, "key3")
      
      test_class.send(:promote_lru, 0, "key1")
      
      expect(test_class.lru_heads[0].key).to eq("key1")
    end

    it "does nothing if key is already at head" do
      test_class.send(:insert_lru, 0, "key1")
      
      head_before = test_class.lru_heads[0]
      test_class.send(:promote_lru, 0, "key1")
      
      expect(test_class.lru_heads[0].key).to eq("key1")
    end

    it "does nothing if node doesn't exist" do
      expect { test_class.send(:promote_lru, 0, "nonexistent") }.not_to raise_error
    end
  end

  describe "#remove_node (private)" do
    it "removes a node from the middle of the list" do
      test_class.send(:insert_lru, 0, "key1")
      test_class.send(:insert_lru, 0, "key2")
      test_class.send(:insert_lru, 0, "key3")
      
      node = test_class.lru_nodes[0]["key2"]
      test_class.send(:remove_node, 0, node)
      
      expect(test_class.lru_heads[0].key).to eq("key3")
      expect(test_class.lru_heads[0].next.key).to eq("key1")
    end

    it "updates head when removing head node" do
      test_class.send(:insert_lru, 0, "key1")
      test_class.send(:insert_lru, 0, "key2")
      
      node = test_class.lru_heads[0]
      test_class.send(:remove_node, 0, node)
      
      expect(test_class.lru_heads[0].key).to eq("key1")
    end

    it "updates tail when removing tail node" do
      test_class.send(:insert_lru, 0, "key1")
      test_class.send(:insert_lru, 0, "key2")
      
      node = test_class.lru_tails[0]
      test_class.send(:remove_node, 0, node)
      
      expect(test_class.lru_tails[0].key).to eq("key2")
    end
  end

  describe "#evict_key (private)" do
    it "removes key from store and LRU list" do
      test_class.stores[0]["key1"] = { value: "test".b, expires_at: nil }
      test_class.current_bytes[0] = 100
      test_class.send(:insert_lru, 0, "key1")
      
      test_class.send(:evict_key, 0, "key1")
      
      expect(test_class.stores[0]).not_to have_key("key1")
      expect(test_class.lru_nodes[0]).not_to have_key("key1")
      expect(test_class.current_bytes[0]).to eq(92) # 100 - "key1".bytesize(4) - "test".bytesize(4)
    end

    it "does nothing if key doesn't exist" do
      expect { test_class.send(:evict_key, 0, "nonexistent") }.not_to raise_error
    end

    it "updates memory counter correctly" do
      test_class.stores[0]["mykey"] = { value: "myvalue".b, expires_at: nil }
      test_class.current_bytes[0] = 100
      
      test_class.send(:evict_key, 0, "mykey")
      
      # 100 - ("mykey".bytesize + "myvalue".bytesize) = 100 - 12 = 88
      expect(test_class.current_bytes[0]).to eq(88)
    end
  end
end
