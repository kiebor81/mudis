# frozen_string_literal: true

require "zlib"

class Mudis
  # Scoped wrapper for caller-bound access with optional per-caller policy.
  class Bound
    def initialize(namespace:, default_ttl: nil, max_ttl: nil, max_value_bytes: nil)
      raise ArgumentError, "namespace is required" if namespace.nil? || namespace.to_s.empty?

      @namespace = namespace
      @default_ttl = default_ttl
      @max_ttl = max_ttl
      @max_value_bytes = max_value_bytes
      @inflight_mutexes_lock = Mutex.new
      @inflight_mutexes = {}
    end

    attr_reader :namespace

    def read(key)
      Mudis.read(key, namespace: @namespace)
    end

    def write(key, value, expires_in: nil)
      return if exceeds_max_value_bytes?(value)

      Mudis.write(key, value, expires_in: effective_ttl(expires_in), namespace: @namespace)
    end

    def update(key)
      Mudis.update(key, namespace: @namespace) do |current|
        next_value = yield(current)
        exceeds_max_value_bytes?(next_value) ? current : next_value
      end
    end

    def delete(key)
      Mudis.delete(key, namespace: @namespace)
    end

    def exists?(key)
      Mudis.exists?(key, namespace: @namespace)
    end

    def fetch(key, expires_in: nil, force: false, singleflight: false)
      return fetch_without_lock(key, expires_in:, force:) { yield } unless singleflight

      with_inflight_lock(key) do
        fetch_without_lock(key, expires_in:, force:) { yield }
      end
    end

    def clear(key)
      delete(key)
    end

    def replace(key, value, expires_in: nil)
      return if exceeds_max_value_bytes?(value)

      Mudis.replace(key, value, expires_in: effective_ttl(expires_in), namespace: @namespace)
    end

    def inspect(key)
      Mudis.inspect(key, namespace: @namespace)
    end

    def keys
      Mudis.keys(namespace: @namespace)
    end

    def metrics
      Mudis.metrics(namespace: @namespace)
    end

    def clear_namespace
      Mudis.clear_namespace(namespace: @namespace)
    end

    private

    def effective_ttl(expires_in)
      ttl = expires_in || @default_ttl
      return nil unless ttl
      return ttl unless @max_ttl

      [ttl, @max_ttl].min
    end

    def exceeds_max_value_bytes?(value)
      return false unless @max_value_bytes

      raw = Mudis.serializer.dump(value)
      raw = Zlib::Deflate.deflate(raw) if Mudis.compress
      raw.bytesize > @max_value_bytes
    end

    def fetch_without_lock(key, expires_in:, force:)
      unless force
        cached = read(key)
        return cached if cached
      end

      value = yield
      return nil if exceeds_max_value_bytes?(value)

      write(key, value, expires_in: expires_in)
      value
    end

    def with_inflight_lock(lock_key)
      entry = nil
      @inflight_mutexes_lock.synchronize do
        entry = (@inflight_mutexes[lock_key] ||= { mutex: Mutex.new, count: 0 })
        entry[:count] += 1
      end

      entry[:mutex].synchronize { yield }
    ensure
      @inflight_mutexes_lock.synchronize do
        next unless entry

        entry[:count] -= 1
        @inflight_mutexes.delete(lock_key) if entry[:count] <= 0
      end
    end
  end
end
