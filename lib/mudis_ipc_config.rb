# frozen_string_literal: true

# Shared configuration for IPC mode (server and client)
module MudisIPCConfig
  SOCKET_PATH = "/tmp/mudis.sock"
  TCP_HOST = "127.0.0.1"
  TCP_PORT = 9876

  # Check if TCP mode should be used (Windows or forced via ENV)
  def self.use_tcp?
    ENV["MUDIS_FORCE_TCP"] == "true" || Gem.win_platform?
  end
end
