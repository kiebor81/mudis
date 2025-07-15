# lib/mudis.rb
require 'json'
require 'thread'
require 'zlib'

# Mudis is a thread-safe, in-memory, sharded, LRU cache with optional compression and expiry.
# It is designed for high concurrency and performance within a Ruby application.
class Mudis
  # --- Global Configuration and State ---

  @serializer = JSON                            # Default serializer (can be changed to Marshal or Oj)
  @compress = false                             # Whether to compress values with Zlib
  @metrics = { hits: 0, misses: 0, evictions: 0 } # Metrics tracking read/write behavior
  @metrics_mutex = Mutex.new                    # Mutex for synchronizing access to metrics
  @max_value_bytes = nil                        # Optional size cap per value
  @stop_expiry = false                          # Signal for stopping expiry thread

  class << self
    attr_accessor :serializer, :compress, :max_value_bytes

    # Returns a snapshot of metrics (thread-safe)
    def metrics
      @metrics_mutex.synchronize { @metrics.dup }
    end
  end

  # Node structure for the LRU doubly-linked list
  class LRUNode
    attr_accessor :key, :prev, :next
    def initialize(key)
      @key = key
      @prev = nil
      @next = nil
    end
  end

  # Number of cache buckets (shards). Default: 32
  def self.buckets
    @buckets ||= (ENV['MUDIS_BUCKETS']&.to_i || 32)
  end

  # --- Internal Structures ---

  @stores = Array.new(buckets) { {} }           # Array of hash buckets for storage
  @mutexes = Array.new(buckets) { Mutex.new }   # Per-bucket mutexes
  @lru_heads = Array.new(buckets) { nil }       # Head node for each LRU list
  @lru_tails = Array.new(buckets) { nil }       # Tail node for each LRU list
  @lru_nodes = Array.new(buckets) { {} }        # Map of key => LRU node
  @current_bytes = Array.new(buckets, 0)        # Memory usage per bucket
  @max_bytes = 1_073_741_824                    # 1 GB global max cache size
  @threshold_bytes = (@max_bytes * 0.9).to_i     # Eviction threshold at 90%
  @expiry_thread = nil                          # Background thread for expiry cleanup

  class << self
    # Starts a thread that periodically removes expired entries
    def start_expiry_thread(interval: 60)
      return if @expiry_thread&.alive?

      @stop_expiry = false
      @expiry_thread = Thread.new do
        loop do
          break if @stop_expiry
          sleep interval
          cleanup_expired!
        end
      end
    end

    # Signals and joins the expiry thread
    def stop_expiry_thread
      @stop_expiry = true
      @expiry_thread&.join
      @expiry_thread = nil
    end

    # Computes which bucket a key belongs to
    def bucket_index(key)
      key.hash % buckets
    end

    # Checks if a key exists and is not expired
    def exists?(key)
      !!read(key)
    end

    # Reads and returns the value for a key, updating LRU and metrics
    def read(key)
      raw_entry = nil
      idx = bucket_index(key)
      mutex = @mutexes[idx]

      mutex.synchronize do
        raw_entry = @stores[idx][key]
        if raw_entry && raw_entry[:expires_at] && Time.now > raw_entry[:expires_at]
          evict_key(idx, key)
          raw_entry = nil
        end

        metric(:hits) if raw_entry
        metric(:misses) unless raw_entry
      end

      return nil unless raw_entry

      value = decompress_and_deserialize(raw_entry[:value])
      promote_lru(idx, key)
      value
    end

    # Writes a value to the cache with optional expiry and LRU tracking
    def write(key, value, expires_in: nil)
      raw = serializer.dump(value)
      raw = Zlib::Deflate.deflate(raw) if compress
      size = key.bytesize + raw.bytesize
      return if max_value_bytes && raw.bytesize > max_value_bytes

      idx = bucket_index(key)
      mutex = @mutexes[idx]
      store = @stores[idx]

      mutex.synchronize do
        evict_key(idx, key) if store[key]

        while @current_bytes[idx] + size > (@threshold_bytes / buckets) && @lru_tails[idx]
          evict_key(idx, @lru_tails[idx].key)
          metric(:evictions)
        end

        store[key] = {
          value: raw,
          expires_at: expires_in ? Time.now + expires_in : nil,
          created_at: Time.now
        }

        insert_lru(idx, key)
        @current_bytes[idx] += size
      end
    end

    # Atomically updates the value for a key using a block
    def update(key)
      idx = bucket_index(key)
      mutex = @mutexes[idx]
      store = @stores[idx]

      raw_entry = nil
      mutex.synchronize do
        raw_entry = store[key]
        return nil unless raw_entry
      end

      value = decompress_and_deserialize(raw_entry[:value])
      new_value = yield(value)
      new_raw = serializer.dump(new_value)
      new_raw = Zlib::Deflate.deflate(new_raw) if compress

      mutex.synchronize do
        old_size = key.bytesize + raw_entry[:value].bytesize
        new_size = key.bytesize + new_raw.bytesize
        store[key][:value] = new_raw
        @current_bytes[idx] += (new_size - old_size)
        promote_lru(idx, key)
      end
    end

    # Deletes a key from the cache
    def delete(key)
      idx = bucket_index(key)
      mutex = @mutexes[idx]

      mutex.synchronize do
        evict_key(idx, key)
      end
    end

    # Removes expired keys across all buckets
    def cleanup_expired!
      now = Time.now
      buckets.times do |idx|
        mutex = @mutexes[idx]
        store = @stores[idx]
        mutex.synchronize do
          store.keys.each do |key|
            if store[key][:expires_at] && now > store[key][:expires_at]
              evict_key(idx, key)
            end
          end
        end
      end
    end

    # Returns an array of all cache keys
    def all_keys
      keys = []
      buckets.times do |idx|
        mutex = @mutexes[idx]
        store = @stores[idx]
        mutex.synchronize { keys.concat(store.keys) }
      end
      keys
    end

    # Returns total memory used across all buckets
    def current_memory_bytes
      @current_bytes.sum
    end

    # Returns configured maximum memory allowed
    def max_memory_bytes
      @max_bytes
    end

    private

    # Decompresses and deserializes a raw value
    def decompress_and_deserialize(raw)
      val = compress ? Zlib::Inflate.inflate(raw) : raw
      serializer.load(val)
    end

    # Thread-safe metric increment
    def metric(name)
      @metrics_mutex.synchronize { @metrics[name] += 1 }
    end

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

