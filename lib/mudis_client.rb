# frozen_string_literal: true

require "socket"
require "json"
require "timeout"
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
  def request(payload) # rubocop:disable Metrics/MethodLength
    @mutex.synchronize do
      attempts = 0

      begin
        attempts += 1
        response = nil

        Timeout.timeout(MudisIPCConfig.timeout) do
          sock = open_connection
          sock.puts(JSON.dump(payload))
          response = sock.gets
          sock.close
        end

        return nil unless response

        res = JSON.parse(response, symbolize_names: true)
        raise res[:error] unless res[:ok]

        res[:value]
      rescue Errno::ENOENT, Errno::ECONNREFUSED, Timeout::Error
        if attempts <= MudisIPCConfig.retries
          retry
        end

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

  # Inspect metadata for a key
  def inspect(key, namespace: nil)
    command("inspect", key:, namespace:)
  end

  # Return keys for a namespace
  def keys(namespace:)
    command("keys", namespace:)
  end

  # Clear keys in a namespace
  def clear_namespace(namespace:)
    command("clear_namespace", namespace:)
  end

  # Return least touched keys
  def least_touched(limit = 10)
    command("least_touched", limit:)
  end

  # Return all keys
  def all_keys
    command("all_keys")
  end

  # Return current memory usage
  def current_memory_bytes
    command("current_memory_bytes")
  end

  # Return max memory configured
  def max_memory_bytes
    command("max_memory_bytes")
  end

  # Retrieve metrics from the Mudis server
  def metrics
    command("metrics")
  end

  private

  # Helper to send a command with options
  def command(cmd, **opts)
    request({ cmd:, **opts })
  end
end
