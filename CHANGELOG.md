## [Unreleased]

## [0.1.0]

- Initial release

## [0.2.0]

- Added `.fetch` block-based cache helper
- Added `.clear(key)` – alias for `.delete`
- Added `.replace(key, value)` – only if key exists
- Added `.inspect(key)` – returns cache metadata

## [0.3.0]

#### Namespacing Support

- Added `with_namespace(namespace) { ... }` block syntax to scope cache keys.
- All public methods (`write`, `read`, `delete`, `exists?`, etc.) now accept an optional `namespace:` keyword.
- Keys are internally expanded as `"namespace:key"` at write/read time.
- Namespacing is opt-in, manually scped keys are still handled
- Supports nested use and thread-safe state via `Thread.current[:mudis_namespace]`.

#### Hard Memory Limits (Memory Guarding)

- Introduced a configurable `Mudis.hard_memory_limit = true` setting.
- When enabled, Mudis will not allow writes that exceed `Mudis.max_memory_bytes`.
- Writes are silently rejected (no exception) and recorded in the `:rejected` counter in `Mudis.metrics`.
- This provides better safety for memory-constrained environments or long-lived processes.

#### Metrics

- Added new `:rejected` metric to track how many writes were skipped due to hard memory limits.
- Metrics now include: `:hits`, `:misses`, `:evictions`, `:rejected`.

#### Configuration

These settings can be configured:

```ruby
Mudis.hard_memory_limit = true
Mudis.max_memory_bytes = 500_000_000
Mudis.with_namespace("my_feature") { ... }
```

## [0.3.1]

#### `max_bytes` Setter Exposed

- `Mudis.max_bytes` exposed for config.
- When `max_bytes` is updated, `threshold_bytes` is automatically recalculated
- Example usage:

```ruby
  Mudis.max_bytes = 500_000_000
```

## [0.4.0]

#### Per Bucket Stats

- Added deep check for bucket index and return in metrics
- Simplified metrics call back

#### Configure Interface on Public API

- Added `Mudis.configure` block-style DSL for setting cache behaviour
- Introduced `MudisConfig` to encapsulate serializer, compression, memory, and limit settings
- Configuration is now centralized and idiomatic:

```ruby
  Mudis.configure do |c|
    c.serializer = JSON
    c.compress = true
    c.max_value_bytes = 2_000_000
    c.hard_memory_limit = true
    c.max_bytes = 500_000_000
  end
```

#### Reset and Cache Reset (for developers)

- Added `Mudis.reset!` to fully clear all internal cache state, memory usage, LRU tracking, and metrics.
- This is useful in test environments or dev consoles when a full wipe of the cache is needed.
- Added `Mudis.reset_metrics!` to clear only the metrics (hits, misses, evictions, rejected) wihtout touching the cache.

## [0.4.1]

Minor updates to gemspec to include missing detail arouns min versions

## [0.4.2]

RBS updates to static type definitions

## [0.4.3]

#### Guard Clauses

Added common-sense guard rails for setters in the following scenarios

- `max_bytes or max_value_bytes <= 0`
- `MUDIS_BUCKETS <= 0`
- `max_value_bytes > max_bytes`

## [0.4.4]

Gemspec summary and description corrections.

## [0.5.0]

#### Max TTL

- Added configuration property `max_ttl`. 
- Added guards for when `expires_in` > `max_ttl` or when `max_ttl` = 0

#### Default TTL

- Added configuration property `default_ttl`.
- Added fallback logic to `default_ttl` when `expires_in` not provided

#### Least Touched

- Added metrics for touch times on keys
- Added `least_touched` function to dev API and `metrics` result

## [0.6.0]

### Namespace Batch Functions

- Added `keys(namespace:)` to return all keys in namespace
- Added `clear_namespace(namespace:)` to erase all keys within the given namespace

### Fixed Buckets

- Found an issue where setting buckets would not take if Mudis was already initialised.
- Setting `Mudis.buckets` now properly resets and re-initialises with a hot reload

### Re-organised Specs

- Split specs into separate files to minismize collisions and improve readability

## [0.7.0]

### Inter-Process Caching (IPC Mode)

- Introduced IPC Mode enabling shared caching across multiple processes (e.g., Puma cluster).
- Added `MudisServer` and `MudisClient` for local UNIX-socket communication between workers.
- Allows all processes to share a single in-memory Mudis instance without Redis or Memcached.
- Maintains full support for TTL, compression, namespacing, metrics, and memory-limit settings.
- Communication occurs over `/tmp/mudis.sock` using a lightweight JSON protocol.

## [0.7.1]

#### Proxy Support
- Added optional `mudis_proxy.rb` allowing workers to continue calling the `Mudis` API seamlessly.
- Proxied methods include: `read`, `write`, `delete`, `fetch`, `metrics`, `reset_metrics!`, `reset!`.

---