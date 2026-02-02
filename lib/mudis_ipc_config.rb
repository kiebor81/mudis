# frozen_string_literal: true

# Shared configuration for IPC mode (server and client)
module MudisIPCConfig
  SOCKET_PATH = "/tmp/mudis.sock"
  TCP_HOST = "127.0.0.1"
  TCP_PORT = 9876
  DEFAULT_TIMEOUT = 1
  DEFAULT_RETRIES = 1

  # Check if TCP mode should be used (Windows or forced via ENV)
  def self.use_tcp?
    ENV["MUDIS_FORCE_TCP"] == "true" || Gem.win_platform?
  end

  def self.timeout
    (ENV["MUDIS_IPC_TIMEOUT"] || DEFAULT_TIMEOUT).to_f
  end

  def self.retries
    (ENV["MUDIS_IPC_RETRIES"] || DEFAULT_RETRIES).to_i
  end
end
