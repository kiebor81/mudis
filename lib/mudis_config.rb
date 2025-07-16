# frozen_string_literal: true

# MudisConfig holds all configuration values for Mudis,
# and provides defaults that can be overridden via Mudis.configure.
class MudisConfig
  attr_accessor :serializer,
                :compress,
                :max_value_bytes,
                :hard_memory_limit,
                :max_bytes

  def initialize
    @serializer = JSON                        # Default serialization strategy
    @compress = false                         # Whether to compress values with Zlib
    @max_value_bytes = nil                    # Max size per value (optional)
    @hard_memory_limit = false                # Enforce max_bytes as hard cap
    @max_bytes = 1_073_741_824                # 1 GB default max cache size
  end
end
