# frozen_string_literal: true
require "socket"
require "json"

class MudisClient
  SOCKET_PATH = "/tmp/mudis.sock"

  def initialize
    @mutex = Mutex.new
  end

  def request(payload)
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

  def read(key, namespace: nil)
    request(cmd: "read", key: key, namespace: namespace)
  end

  def write(key, value, expires_in: nil, namespace: nil)
    request(cmd: "write", key: key, value: value, ttl: expires_in, namespace: namespace)
  end

  def delete(key, namespace: nil)
    request(cmd: "delete", key: key, namespace: namespace)
  end

  def exists?(key, namespace: nil)
    request(cmd: "exists", key: key, namespace: namespace)
  end

  def fetch(key, expires_in: nil, namespace: nil)
    val = read(key, namespace: namespace)
    return val if val

    new_val = yield
    write(key, new_val, expires_in: expires_in, namespace: namespace)
    new_val
  end

  def metrics
    request(cmd: "metrics")
  end

  def reset_metrics!
    request(cmd: "reset_metrics")
  end

  def reset!
    request(cmd: "reset")
  end

end
