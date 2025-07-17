# frozen_string_literal: true

require_relative "lib/mudis/version"

Gem::Specification.new do |spec|
  spec.name          = "mudis"
  spec.version       = MUDIS_VERSION
  spec.authors       = ["kiebor81"]

  spec.summary       = "A fast in-memory, thread-safe and high performance Ruby LRU cache with compression and auto-expiry." # rubocop:disable Layout/LineLength
  spec.description   = "Mudis is a fast, thread-safe, in-memory, sharded LRU cache for Ruby applications. Inspired by Redis, it provides value serialization, optional compression, per-key expiry, and metric tracking in a lightweight, dependency-free package." # rubocop:disable Layout/LineLength
  spec.homepage      = "https://github.com/kiebor81/mudis"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0"
  spec.extra_rdoc_files += Dir["sig/**/*.rbs"]
  spec.files         = Dir["lib/**/*", "README.md"]
  spec.require_paths = ["lib"]
  spec.test_files = Dir["spec/**/*_spec.rb"]
  spec.add_development_dependency "climate_control", "~> 1.1.0"
  spec.add_development_dependency "rspec", "~> 3.12"
end
