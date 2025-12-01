# frozen_string_literal: true

class Mudis
  # Node structure for the LRU doubly-linked list
  class LRUNode
    attr_accessor :key, :prev, :next

    def initialize(key)
      @key = key
      @prev = nil
      @next = nil
    end
  end

  # LRU module handles the Least Recently Used eviction strategy
  # Maintains doubly-linked lists per bucket for O(1) promote/evict operations
  module LRU
    private

    # Removes a key from storage and LRU
    def evict_key(idx, key)
      store = @stores[idx]
      entry = store.delete(key)
      return unless entry

      @current_bytes[idx] -= (key.bytesize + entry[:value].bytesize)

      node = @lru_nodes[idx].delete(key)
      remove_node(idx, node) if node
    end

    # Inserts a key at the head of the LRU list
    def insert_lru(idx, key)
      node = LRUNode.new(key)
      node.next = @lru_heads[idx]
      @lru_heads[idx].prev = node if @lru_heads[idx]
      @lru_heads[idx] = node
      @lru_tails[idx] ||= node
      @lru_nodes[idx][key] = node
    end

    # Promotes a key to the front of the LRU list
    def promote_lru(idx, key)
      node = @lru_nodes[idx][key]
      return unless node && @lru_heads[idx] != node

      remove_node(idx, node)
      insert_lru(idx, key)
    end

    # Removes a node from the LRU list
    def remove_node(idx, node)
      if node.prev
        node.prev.next = node.next
      else
        @lru_heads[idx] = node.next
      end

      if node.next
        node.next.prev = node.prev
      else
        @lru_tails[idx] = node.prev
      end
    end
  end
end
