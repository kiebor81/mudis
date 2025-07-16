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
- Namespacing is opt-in and backward compatible — legacy keys remain untouched unless namespace is provided.
- Supports nested use and thread-safe state via `Thread.current[:mudis_namespace]`.

#### Hard Memory Limits (Memory Guarding)

- Introduced a configurable `Mudis.hard_memory_limit = true` setting.
- When enabled, Mudis will **not allow writes that exceed `Mudis.max_memory_bytes`**.
- Writes are silently rejected (no exception) and recorded in the `:rejected` counter in `Mudis.metrics`.
- This provides better safety for memory-constrained environments or long-lived processes.

### Metrics

- Added new `:rejected` metric to track how many writes were skipped due to hard memory limits.
- Metrics now include: `:hits`, `:misses`, `:evictions`, `:rejected`.

### Configuration

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