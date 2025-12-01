# frozen_string_literal: true

class Mudis
  # Expiry module handles TTL-based expiration and background cleanup
  module Expiry
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

    private

    # Calculates the effective TTL for an entry, respecting max_ttl if set
    def effective_ttl(expires_in)
      ttl = expires_in || @default_ttl
      return nil unless ttl
      return ttl unless @max_ttl

      [ttl, @max_ttl].min
    end
  end
end
