# frozen_string_literal: true

require "socket"
require "json"
require_relative "mudis_ipc_config"

# Thread-safe client for communicating with the MudisServer
# Automatically uses UNIX sockets on Linux/macOS and TCP on Windows
class MudisClient
  include MudisIPCConfig

  def initialize
    @mutex = Mutex.new
  end

  # Open a connection to the server (TCP or UNIX)
  def open_connection
    if MudisIPCConfig.use_tcp?
      TCPSocket.new(TCP_HOST, TCP_PORT)
    else
      UNIXSocket.open(SOCKET_PATH)
    end
  end

  # Send a request to the MudisServer and return the response
  # @param payload [Hash] The request payload
  # @return [Object] The response value from the server
  def request(payload) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    @mutex.synchronize do
      sock = open_connection
      sock.puts(JSON.dump(payload))
      response = sock.gets
      sock.close

      return nil unless response

      res = JSON.parse(response, symbolize_names: true)
      raise res[:error] unless res[:ok]

      res[:value]
    rescue Errno::ENOENT, Errno::ECONNREFUSED
      warn "[MudisClient] Cannot connect to MudisServer. Is it running?"
      nil
    rescue JSON::ParserError
      warn "[MudisClient] Invalid JSON response from server"
      nil
    rescue IOError, SystemCallError => e
      warn "[MudisClient] Connection error: #{e.message}"
      nil
    end
  end

  # --- Forwarded Mudis methods ---

  # Read a value from the Mudis server
  def read(key, namespace: nil)
    command("read", key:, namespace:)
  end

  # Write a value to the Mudis server
  def write(key, value, expires_in: nil, namespace: nil)
    command("write", key:, value:, ttl: expires_in, namespace:)
  end

  # Delete a value from the Mudis server
  def delete(key, namespace: nil)
    command("delete", key:, namespace:)
  end

  # Check if a key exists in the Mudis server
  def exists?(key, namespace: nil)
    command("exists", key:, namespace:)
  end

  # Fetch a value, computing and storing it if not present
  def fetch(key, expires_in: nil, namespace: nil)
    val = read(key, namespace:)
    return val if val

    new_val = yield
    write(key, new_val, expires_in:, namespace:)
    new_val
  end

  # Retrieve metrics from the Mudis server
  def metrics
    command("metrics")
  end

  # Reset metrics on the Mudis server
  def reset_metrics!
    command("reset_metrics")
  end

  # Reset the Mudis server cache state
  def reset!
    command("reset")
  end

  private

  # Helper to send a command with options
  def command(cmd, **opts)
    request({ cmd:, **opts })
  end

end
