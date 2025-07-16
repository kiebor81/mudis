# frozen_string_literal: true

require_relative "lib/mudis/version"

Gem::Specification.new do |spec|
  spec.name          = "mudis"
  spec.version       = MUDIS_VERSION
  spec.authors       = ["kiebor81"]

  spec.summary       = "A fast in-memory Ruby LRU cache with compression and expiry."
  spec.description   = "Thread-safe, bucketed, in-process cache for Ruby apps. Drop-in replacement for Kredis in some scenarios." # rubocop:disable Layout/LineLength
  spec.homepage      = "https://github.com/kiebor81/mudis"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0"
  spec.extra_rdoc_files += Dir["sig/**/*.rbs"]
  spec.files         = Dir["lib/**/*", "README.md"]
  spec.require_paths = ["lib"]
  spec.test_files = Dir["spec/**/*_spec.rb"]
  spec.add_development_dependency "rspec", "~> 3.12"
end
