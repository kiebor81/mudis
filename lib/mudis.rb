# frozen_string_literal: true

require "json"
require "thread" # rubocop:disable Lint/RedundantRequireStatement
require "zlib"

require_relative "mudis_config"

# Mudis is a thread-safe, in-memory, sharded, LRU cache with optional compression and expiry.
# It is designed for high concurrency and performance within a Ruby application.
class Mudis # rubocop:disable Metrics/ClassLength
  # --- Global Configuration and State ---

  @serializer = JSON                            # Default serializer (can be changed to Marshal or Oj)
  @compress = false                             # Whether to compress values with Zlib
  @metrics = { hits: 0, misses: 0, evictions: 0, rejected: 0 } # Metrics tracking read/write behaviour
  @metrics_mutex = Mutex.new                    # Mutex for synchronizing access to metrics
  @max_value_bytes = nil                        # Optional size cap per value
  @stop_expiry = false                          # Signal for stopping expiry thread

  class << self
    attr_accessor :serializer, :compress, :hard_memory_limit
    attr_reader :max_bytes, :max_value_bytes

    # Configures Mudis with a block, allowing customization of settings
    def configure
      yield(config)
      apply_config!
    end

    # Returns the current configuration object
    def config
      @config ||= MudisConfig.new
    end

    # Applies the current configuration to Mudis
    def apply_config!
      validate_config!

      self.serializer = config.serializer
      self.compress = config.compress
      self.max_value_bytes = config.max_value_bytes
      self.hard_memory_limit = config.hard_memory_limit
      self.max_bytes = config.max_bytes
    end

    # Validates the current configuration, raising errors for invalid settings
    def validate_config! # rubocop:disable Metrics/AbcSize
      if config.max_value_bytes && config.max_value_bytes > config.max_bytes
        raise ArgumentError,
              "max_value_bytes cannot exceed max_bytes"
      end

      raise ArgumentError, "max_value_bytes must be > 0" if config.max_value_bytes && config.max_value_bytes <= 0

      raise ArgumentError, "buckets must be > 0" if config.buckets && config.buckets <= 0
    end

    # Returns a snapshot of metrics (thread-safe)
    def metrics # rubocop:disable Metrics/MethodLength
      @metrics_mutex.synchronize do
        {
          hits: @metrics[:hits],
          misses: @metrics[:misses],
          evictions: @metrics[:evictions],
          rejected: @metrics[:rejected],
          total_memory: current_memory_bytes,
          buckets: buckets.times.map do |idx|
            {
              index: idx,
              keys: @stores[idx].size,
              memory_bytes: @current_bytes[idx],
              lru_size: @lru_nodes[idx].size
            }
          end
        }
      end
    end

    # Resets metric counters (thread-safe)
    def reset_metrics!
      @metrics_mutex.synchronize do
        @metrics = { hits: 0, misses: 0, evictions: 0, rejected: 0 }
      end
    end

    # Fully resets all internal state (except config)
    def reset!
      stop_expiry_thread

      @buckets = nil
      b = buckets

      @stores        = Array.new(b) { {} }
      @mutexes       = Array.new(b) { Mutex.new }
      @lru_heads     = Array.new(b) { nil }
      @lru_tails     = Array.new(b) { nil }
      @lru_nodes     = Array.new(b) { {} }
      @current_bytes = Array.new(b, 0)

      reset_metrics!
    end

    # Sets the maximum size for a single value in bytes
    def max_bytes=(value)
      raise ArgumentError, "max_bytes must be > 0" if value.to_i <= 0

      @max_bytes = value
      @threshold_bytes = (@max_bytes * 0.9).to_i
    end

    # Sets the maximum size for a single value in bytes, raising an error if invalid
    def max_value_bytes=(value)
      raise ArgumentError, "max_value_bytes must be > 0" if value && value.to_i <= 0

      @max_value_bytes = value
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
    return @buckets if @buckets

    val = config.buckets || ENV["MUDIS_BUCKETS"]&.to_i || 32
    raise ArgumentError, "bucket count must be > 0" if val <= 0

    @buckets = val
  end

  # --- Internal Structures ---

  @stores = Array.new(buckets) { {} }           # Array of hash buckets for storage
  @mutexes = Array.new(buckets) { Mutex.new }   # Per-bucket mutexes
  @lru_heads = Array.new(buckets) { nil }       # Head node for each LRU list
  @lru_tails = Array.new(buckets) { nil }       # Tail node for each LRU list
  @lru_nodes = Array.new(buckets) { {} }        # Map of key => LRU node
  @current_bytes = Array.new(buckets, 0)        # Memory usage per bucket
  @max_bytes = 1_073_741_824                    # 1 GB global max cache size
  @threshold_bytes = (@max_bytes * 0.9).to_i # Eviction threshold at 90%
  @expiry_thread = nil # Background thread for expiry cleanup
  @hard_memory_limit = false # Whether to enforce hard memory cap

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
    def exists?(key, namespace: nil)
      key = namespaced_key(key, namespace)
      !!read(key)
    end

    # Reads and returns the value for a key, updating LRU and metrics
    def read(key, namespace: nil) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
      key = namespaced_key(key, namespace)
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
    def write(key, value, expires_in: nil, namespace: nil) # rubocop:disable Metrics/MethodLength,Metrics/CyclomaticComplexity,Metrics/AbcSize,Metrics/PerceivedComplexity
      key = namespaced_key(key, namespace)
      raw = serializer.dump(value)
      raw = Zlib::Deflate.deflate(raw) if compress
      size = key.bytesize + raw.bytesize
      return if max_value_bytes && raw.bytesize > max_value_bytes

      if hard_memory_limit && current_memory_bytes + size > max_memory_bytes
        metric(:rejected)
        return
      end

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
    def update(key, namespace: nil) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
      key = namespaced_key(key, namespace)
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
    def delete(key, namespace: nil)
      key = namespaced_key(key, namespace)
      idx = bucket_index(key)
      mutex = @mutexes[idx]

      mutex.synchronize do
        evict_key(idx, key)
      end
    end

    # Fetches a value for a key, writing it if not present or expired
    # The block is executed to generate the value if it doesn't exist
    # Optionally accepts an expiration time
    # If force is true, it always fetches and writes the value
    def fetch(key, expires_in: nil, force: false, namespace: nil)
      key = namespaced_key(key, namespace)
      unless force
        cached = read(key)
        return cached if cached
      end

      value = yield
      write(key, value, expires_in: expires_in)
      value
    end

    # Clears a specific key from the cache, a semantic synonym for delete
    # This method is provided for clarity in usage
    # It behaves the same as delete
    def clear(key, namespace: nil)
      delete(key, namespace: namespace)
    end

    # Replaces the value for a key if it exists, otherwise does nothing
    # This is useful for updating values without needing to check existence first
    # It will write the new value and update the expiration if provided
    # If the key does not exist, it will not create a new entry
    def replace(key, value, expires_in: nil, namespace: nil)
      return unless exists?(key, namespace: namespace)

      write(key, value, expires_in: expires_in, namespace: namespace)
    end

    # Inspects a key and returns all meta data for it
    def inspect(key, namespace: nil) # rubocop:disable Metrics/MethodLength
      key = namespaced_key(key, namespace)
      idx = bucket_index(key)
      store = @stores[idx]
      mutex = @mutexes[idx]

      mutex.synchronize do
        entry = store[key]
        return nil unless entry

        {
          key: key,
          bucket: idx,
          expires_at: entry[:expires_at],
          created_at: entry[:created_at],
          size_bytes: key.bytesize + entry[:value].bytesize,
          compressed: compress
        }
      end
    end

    # Removes expired keys across all buckets
    def cleanup_expired!
      now = Time.now
      buckets.times do |idx|
        mutex = @mutexes[idx]
        store = @stores[idx]
        mutex.synchronize do
          store.keys.each do |key| # rubocop:disable Style/HashEachMethods
            evict_key(idx, key) if store[key][:expires_at] && now > store[key][:expires_at]
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

    # Executes a block with a specific namespace, restoring the old namespace afterwards
    def with_namespace(namespace)
      old_ns = Thread.current[:mudis_namespace]
      Thread.current[:mudis_namespace] = namespace
      yield
    ensure
      Thread.current[:mudis_namespace] = old_ns
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

    # Namespaces a key with an optional namespace
    def namespaced_key(key, namespace = nil)
      ns = namespace || Thread.current[:mudis_namespace]
      ns ? "#{ns}:#{key}" : key
    end
  end
end
