# frozen_string_literal: true
require "socket"
require "json"
require_relative "mudis"

class MudisServer
  SOCKET_PATH = "/tmp/mudis.sock"

  def self.start!
    # Clean up old socket if it exists
    File.unlink(SOCKET_PATH) if File.exist?(SOCKET_PATH)

    server = UNIXServer.new(SOCKET_PATH)
    server.listen(128)
    puts "[MudisServer] Listening on #{SOCKET_PATH}"

    Thread.new do
      loop do
        client = server.accept
        Thread.new(client) do |sock|
          handle_client(sock)
        end
      end
    end
  end

  def self.handle_client(sock)
    request_line = sock.gets
    return unless request_line

    req = JSON.parse(request_line, symbolize_names: true)
    cmd  = req[:cmd]
    key  = req[:key]
    ns   = req[:namespace]
    val  = req[:value]
    ttl  = req[:ttl]

    begin
      case cmd
      when "read"
        result = Mudis.read(key, namespace: ns)
        sock.puts(JSON.dump({ ok: true, value: result }))

      when "write"
        Mudis.write(key, val, expires_in: ttl, namespace: ns)
        sock.puts(JSON.dump({ ok: true }))

      when "delete"
        Mudis.delete(key, namespace: ns)
        sock.puts(JSON.dump({ ok: true }))

      when "exists"
        sock.puts(JSON.dump({ ok: true, value: Mudis.exists?(key, namespace: ns) }))

      when "fetch"
        result = Mudis.fetch(key, expires_in: ttl, namespace: ns) { req[:fallback] }
        sock.puts(JSON.dump({ ok: true, value: result }))

      when "metrics"
        sock.puts(JSON.dump({ ok: true, value: Mudis.metrics }))

      when "reset_metrics"
        Mudis.reset_metrics!
        sock.puts(JSON.dump({ ok: true }))
        
      when "reset"
        Mudis.reset!
        sock.puts(JSON.dump({ ok: true }))

      else
        sock.puts(JSON.dump({ ok: false, error: "unknown command: #{cmd}" }))
      end
    rescue => e
      sock.puts(JSON.dump({ ok: false, error: e.message }))
    ensure
      sock.close
    end
  end
end
