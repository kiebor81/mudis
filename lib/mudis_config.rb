# frozen_string_literal: true

# MudisConfig holds all configuration values for Mudis,
# and provides defaults that can be overridden via Mudis.configure.
class MudisConfig
  attr_accessor :serializer,
                :compress,
                :max_value_bytes,
                :hard_memory_limit,
                :max_bytes,
                :eviction_threshold,
                :buckets,
                :max_ttl,
                :default_ttl,
                # Persistence settings
                :persistence_enabled,
                :persistence_path,
                :persistence_format,
                :persistence_safe_write

  def initialize # rubocop:disable Metrics/MethodLength
    @serializer = JSON                        # Default serialization strategy
    @compress = false                         # Whether to compress values with Zlib
    @max_value_bytes = nil                    # Max size per value (optional)
    @hard_memory_limit = false                # Enforce max_bytes as hard cap
    @max_bytes = 1_073_741_824                # 1 GB default max cache size
    @eviction_threshold = 0.9                # Evict when bucket exceeds threshold
    @buckets = nil                            # use nil to signal fallback to ENV or default
    @max_ttl = nil                            # Max TTL for cache entries (optional)
    @default_ttl = nil                        # Default TTL for cache entries (optional)
    # Persistence settings
    @persistence_enabled = false              # Whether persistence is enabled
    @persistence_path = "mudis_data"          # Default path for persistence files
    @persistence_format = :json               # Default persistence file format
    @persistence_safe_write = true            # Whether to use safe write for persistence
  end
end
