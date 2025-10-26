# frozen_string_literal: true

require "socket"
require "json"

# thread-safe client for communicating with the MudisServer via UNIX socket.
class MudisClient
  SOCKET_PATH = "/tmp/mudis.sock"

  def initialize
    @mutex = Mutex.new
  end

  # Send a request to the MudisServer and return the response
  # @param payload [Hash] The request payload
  # @return [Object] The response value from the server
  def request(payload) # rubocop:disable Metrics/MethodLength
    @mutex.synchronize do
      UNIXSocket.open(SOCKET_PATH) do |sock|
        sock.puts(JSON.dump(payload))
        response = sock.gets
        res = JSON.parse(response, symbolize_names: true)
        raise res[:error] unless res[:ok]

        res[:value]
      end
    rescue Errno::ENOENT
      warn "[MudisClient] Socket missing; master likely not running MudisServer"
      nil
    end
  end

  # --- Forwarded Mudis methods ---

  # Read a value from the Mudis server
  def read(key, namespace: nil)
    request(cmd: "read", key: key, namespace: namespace)
  end

  # Write a value to the Mudis server
  def write(key, value, expires_in: nil, namespace: nil)
    request(cmd: "write", key: key, value: value, ttl: expires_in, namespace: namespace)
  end

  # Delete a value from the Mudis server
  def delete(key, namespace: nil)
    request(cmd: "delete", key: key, namespace: namespace)
  end

  # Check if a key exists in the Mudis server
  def exists?(key, namespace: nil)
    request(cmd: "exists", key: key, namespace: namespace)
  end

  # Fetch a value, computing and storing it if not present
  def fetch(key, expires_in: nil, namespace: nil)
    val = read(key, namespace: namespace)
    return val if val

    new_val = yield
    write(key, new_val, expires_in: expires_in, namespace: namespace)
    new_val
  end

  # Retrieve metrics from the Mudis server
  def metrics
    request(cmd: "metrics")
  end

  # Reset metrics on the Mudis server
  def reset_metrics!
    request(cmd: "reset_metrics")
  end

  # Reset the Mudis server cache state
  def reset!
    request(cmd: "reset")
  end
end
