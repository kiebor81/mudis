![mudis_signet](design/mudis.png "Mudis")

**Mudis** is a fast, thread-safe, in-memory, sharded LRU (Least Recently Used) cache for Ruby applications. Inspired by Redis, it provides value serialization, optional compression, per-key expiry, and metric tracking in a lightweight, dependency-free package that lives inside your Ruby process.

It’s ideal for scenarios where performance and process-local caching are critical, and where a full Redis setup is overkill or otherwise not possible.

---

## Design

#### Write - Read - Eviction

![mudis_flow](design/mudis_flow.png "Write - Read - Eviction")

#### Cache Key Lifecycle

![mudis_lru](design/mudis_lru.png "Mudis Cache Key Lifecycle")

---

## Features

- **Thread-safe**: Uses per-bucket mutexes for high concurrency.
- **Sharded**: Buckets data across multiple internal stores to minimize lock contention.
- **LRU Eviction**: Automatically evicts least recently used items as memory fills up.
- **Expiry Support**: Optional TTL per key with background cleanup thread.
- **Compression**: Optional Zlib compression for large values.
- **Metrics**: Tracks hits, misses, and evictions.

---

## Installation

Add this line to your Gemfile:

```ruby
gem 'mudis'
```

Or install it manually:

```bash
gem install mudis
```

---

## Configuration (Rails)

In your Rails app, create an initializer:

```ruby
# config/initializers/mudis.rb

Mudis.serializer = JSON        # or Marshal | Oj
Mudis.compress = true          # Compress values using Zlib
Mudis.max_value_bytes = 2_000_000  # Reject values > 2MB
Mudis.start_expiry_thread(interval: 60) # Cleanup every 60s

at_exit do
  Mudis.stop_expiry_thread
end
```

> If your `lib/` folder isn't eager loaded, explicitly `require 'mudis'` in this file.

---

## Basic Usage

```ruby
require 'mudis'

# Write a value with optional TTL
Mudis.write('user:123', { name: 'Alice' }, expires_in: 600)

# Read it back
Mudis.read('user:123') # => { "name" => "Alice" }

# Check if it exists
Mudis.exists?('user:123') # => true

# Atomically update
Mudis.update('user:123') { |data| data.merge(age: 30) }

# Delete a key
Mudis.delete('user:123')
```

---

## Rails Service Integration

For simplified or transient use in a controller, you can wrap your cache logic in a reusable thin class:

```ruby
class MudisService
  attr_reader :cache_key

  def initialize(cache_key)
    @cache_key = cache_key
  end

  def write(data, expires_in: nil)
    Mudis.write(cache_key, data, expires_in: expires_in)
  end

  def read(default: nil)
    Mudis.read(cache_key) || default
  end

  def update
    Mudis.update(cache_key) { |current| yield(current) }
  end

  def delete
    Mudis.delete(cache_key)
  end

  def exists?
    Mudis.exists?(cache_key)
  end
end
```

Use it like:

```ruby
cache = MudisCacheService.new("user:#{current_user.id}")
cache.write({ preferences: "dark" }, expires_in: 3600)
cache.read # => { "preferences" => "dark" }
```

---

## Metrics

Track cache effectiveness:

```ruby
Mudis.metrics
# => { hits: 15, misses: 5, evictions: 3 }
```

Optionally, return these metrics from a controller for remote analysis and monitoring.

```ruby
class MudisController < ApplicationController

  def metrics
    render json: {
      mudis_metrics: Mudis.metrics,
      memory_used_bytes: Mudis.current_memory_bytes,
      memory_max_bytes: Mudis.max_memory_bytes,
      keys: Mudis.all_keys.size
    }
  end

end

```

---

## Advanced Configuration

| Setting                  | Description                                 | Default            |
|--------------------------|---------------------------------------------|--------------------|
| `Mudis.serializer`       | JSON, Marshal, or Oj                        | `JSON`             |
| `Mudis.compress`         | Enable Zlib compression                     | `false`            |
| `Mudis.max_value_bytes`  | Max allowed size in bytes for a value       | `nil` (no limit)   |
| `Mudis.buckets`          | Number of cache shards (via ENV var)        | `32`               |
| `start_expiry_thread`    | Background TTL cleanup loop (every N sec)   | Disabled by default|

To customize the number of buckets, set the `MUDIS_BUCKETS` environment variable.

---

## Graceful Shutdown

Don’t forget to stop the expiry thread when your app exits:

```ruby
at_exit { Mudis.stop_expiry_thread }
```

---

## Known Limitations

- Data is **process-local** and **non-persistent**.
- Not suitable for cross-process or cross-language use.
- Keys are globally scoped (no namespacing by default).
- Compression introduces CPU overhead.

---

## Roadmap

- [ ] Namespaced cache keys
- [ ] Stats per bucket
- [ ] Optional max memory cap per bucket
- [ ] Built-in fetch/read-or-write DSL

---

## License

MIT License © kiebor81

---

## Contributing

PRs are welcome! To get started:

```bash
git clone https://github.com/yourusername/mudis
cd mudis
bundle install
rspec
```

---

## Contact

For issues, suggestions, or feedback, please open a GitHub issue
