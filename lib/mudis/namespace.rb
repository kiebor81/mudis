# frozen_string_literal: true

class Mudis
  # Namespace module handles logical key separation and scoping
  module Namespace
    # Returns all keys in a specific namespace
    def keys(namespace:)
      raise ArgumentError, "namespace is required" unless namespace

      prefix = "#{namespace}:"
      all_keys.select { |key| key.start_with?(prefix) }.map { |key| key.delete_prefix(prefix) }
    end

    # Clears all keys in a specific namespace
    def clear_namespace(namespace:)
      raise ArgumentError, "namespace is required" unless namespace

      prefix = "#{namespace}:"
      buckets.times do |idx|
        mutex = @mutexes[idx]
        store = @stores[idx]

        mutex.synchronize do
          keys_to_delete = store.keys.select { |key| key.start_with?(prefix) }
          keys_to_delete.each { |key| evict_key(idx, key) }
        end
      end
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

    # Namespaces a key with an optional namespace
    def namespaced_key(key, namespace = nil)
      ns = namespace || Thread.current[:mudis_namespace]
      ns ? "#{ns}:#{key}" : key
    end
  end
end
