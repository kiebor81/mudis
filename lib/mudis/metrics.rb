# frozen_string_literal: true

class Mudis
  # Metrics module handles tracking of cache hits, misses, evictions and memory usage
  module Metrics
    # Returns a snapshot of metrics (thread-safe)
    def metrics(namespace: nil) # rubocop:disable Metrics/MethodLength
      return namespace_metrics(namespace) if namespace

      @metrics_mutex.synchronize do
        {
          hits: @metrics[:hits],
          misses: @metrics[:misses],
          evictions: @metrics[:evictions],
          rejected: @metrics[:rejected],
          total_memory: current_memory_bytes,
          least_touched: least_touched(10),
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

      @metrics_by_namespace_mutex.synchronize do
        @metrics_by_namespace = {}
      end
    end

    private

    # Thread-safe metric increment
    def metric(name, namespace: nil)
      @metrics_mutex.synchronize { @metrics[name] += 1 }
      return unless namespace

      @metrics_by_namespace_mutex.synchronize do
        @metrics_by_namespace[namespace] ||= { hits: 0, misses: 0, evictions: 0, rejected: 0 }
        @metrics_by_namespace[namespace][name] += 1
      end
    end

    def namespace_metrics(namespace)
      @metrics_by_namespace_mutex.synchronize do
        entry = @metrics_by_namespace[namespace] || { hits: 0, misses: 0, evictions: 0, rejected: 0 }
        entry.merge(namespace: namespace)
      end
    end
  end
end
