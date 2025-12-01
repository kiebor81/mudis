# frozen_string_literal: true

class Mudis
  # Persistence module handles snapshot save/load operations for warm boot support
  module Persistence
    # Saves the current cache state to disk for persistence
    def save_snapshot!
      return unless @persistence_enabled

      data = snapshot_dump
      safe_write_snapshot(data)
    rescue StandardError => e
      warn "[Mudis] Failed to save snapshot: #{e.class}: #{e.message}"
    end

    # Loads the cache state from disk for persistence
    def load_snapshot!
      return unless @persistence_enabled
      return unless File.exist?(@persistence_path)

      data = read_snapshot
      snapshot_restore(data)
    rescue StandardError => e
      warn "[Mudis] Failed to load snapshot: #{e.class}: #{e.message}"
    end

    # Installs an at_exit hook to save the snapshot on process exit
    def install_persistence_hook!
      return unless @persistence_enabled
      return if defined?(@persistence_hook_installed) && @persistence_hook_installed

      at_exit { save_snapshot! }
      @persistence_hook_installed = true
    end

    private

    # Collect a JSON/Marshal-safe array of { key, value, expires_in }
    def snapshot_dump # rubocop:disable Metrics/MethodLength
      entries = []
      now = Time.now
      @buckets.times do |idx|
        mutex = @mutexes[idx]
        store = @stores[idx]
        mutex.synchronize do
          store.each do |key, raw|
            exp_at = raw[:expires_at]
            next if exp_at && now > exp_at

            value = decompress_and_deserialize(raw[:value])
            expires_in = exp_at ? (exp_at - now).to_i : nil
            entries << { key: key, value: value, expires_in: expires_in }
          end
        end
      end
      entries
    end

    # Restore via existing write-path so LRU/limits/compression/TTL are honored
    def snapshot_restore(entries)
      return unless entries && !entries.empty?

      entries.each do |e|
        begin # rubocop:disable Style/RedundantBegin
          write(e[:key], e[:value], expires_in: e[:expires_in])
        rescue StandardError => ex
          warn "[Mudis] Failed to restore key #{e[:key].inspect}: #{ex.message}"
        end
      end
    end

    # Serializer for snapshot persistence
    # Defaults to Marshal if not JSON
    def serializer_for_snapshot
      (@persistence_format || :marshal).to_sym == :json ? JSON : :marshal
    end

    # Safely writes snapshot data to disk
    # Uses safe write if configured
    def safe_write_snapshot(data) # rubocop:disable Metrics/MethodLength
      path = @persistence_path
      dir = File.dirname(path)
      Dir.mkdir(dir) unless Dir.exist?(dir)

      payload =
        if (@persistence_format || :marshal).to_sym == :json
          serializer_for_snapshot.dump(data)
        else
          Marshal.dump(data)
        end

      if @persistence_safe_write
        tmp = "#{path}.tmp-#{$$}-#{Thread.current.object_id}"
        File.open(tmp, "wb") { |f| f.write(payload) }
        File.rename(tmp, path)
      else
        File.open(path, "wb") { |f| f.write(payload) }
      end
    end

    # Reads snapshot data from disk
    # Uses safe read if configured
    def read_snapshot
      if (@persistence_format || :marshal).to_sym == :json
        # Use JSON.parse instead of JSON.load to support symbolize_names option
        serializer_for_snapshot.parse(File.binread(@persistence_path), symbolize_names: true)
      else
        ## safe to use Marshal here as we control the file
        Marshal.load(File.binread(@persistence_path)) # rubocop:disable Security/MarshalLoad
      end
    end
  end
end
