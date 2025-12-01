# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/tmp/"
  add_filter "lib/mudis_server.rb" if Gem.win_platform?
  add_filter "lib/mudis_client.rb" if Gem.win_platform?
end

require "climate_control"

require_relative "../lib/mudis"
require_relative "../lib/mudis_client"
require_relative "../lib/mudis_server"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    Mudis.reset!
  end
end
