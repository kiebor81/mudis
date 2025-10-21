```ruby
# config/initializers/mudis_proxy.rb
unless defined?(MudisServer)
  module Mudis
    def self.read(*a, **k) = $mudis.read(*a, **k)
    def self.write(*a, **k) = $mudis.write(*a, **k)
    def self.delete(*a, **k) = $mudis.delete(*a, **k)
    def self.fetch(*a, **k, &b) = $mudis.fetch(*a, **k, &b)
  end
end
```

```ruby
# config/puma.rb
preload_app!

before_fork do
  require_relative "../lib/mudis"
  require_relative "../lib/mudis_server"

  Mudis.configure do |c|
    c.serializer = JSON
    c.compress = true
    c.max_value_bytes = 2_000_000
    c.hard_memory_limit = true
    c.max_bytes = 1_073_741_824
  end

  Mudis.start_expiry_thread(interval: 60)
  MudisServer.start!

  at_exit { Mudis.stop_expiry_thread }
end

on_worker_boot do
  require_relative "../lib/mudis_client"
  $mudis = MudisClient.new
end
```