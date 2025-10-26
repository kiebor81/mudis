# frozen_string_literal: true

require "socket"
require "json"
require_relative "mudis"

# Simple UNIX socket server for handling Mudis operations via IPC mode
class MudisServer
  SOCKET_PATH = "/tmp/mudis.sock"

  # Define command handlers mapping
  # Each command maps to a lambda that takes a request hash and performs the corresponding Mudis operation.
  COMMANDS = {
    "read"          => ->(r) { Mudis.read(r[:key], namespace: r[:namespace]) },
    "write"         => ->(r) { Mudis.write(r[:key], r[:value], expires_in: r[:ttl], namespace: r[:namespace]) },
    "delete"        => ->(r) { Mudis.delete(r[:key], namespace: r[:namespace]) },
    "exists"        => ->(r) { Mudis.exists?(r[:key], namespace: r[:namespace]) },
    "fetch"         => ->(r) { Mudis.fetch(r[:key], expires_in: r[:ttl], namespace: r[:namespace]) { r[:fallback] } },
    "metrics"       => ->(_) { Mudis.metrics },
    "reset_metrics" => ->(_) { Mudis.reset_metrics! },
    "reset"         => ->(_) { Mudis.reset! }
  }.freeze

  # Start the MudisServer
  # This will run in a separate thread and handle incoming client connections.
  def self.start! # rubocop:disable Metrics/MethodLength
    # Clean up old socket if it exists
    File.unlink(SOCKET_PATH) if File.exist?(SOCKET_PATH)

    server = UNIXServer.new(SOCKET_PATH)
    server.listen(128)
    puts "[MudisServer] Listening on #{SOCKET_PATH}"

    # Accept connections in a separate thread
    # This allows the server to handle multiple clients concurrently.
    Thread.new do
      loop do
        client = server.accept
        Thread.new(client) do |sock|
          handle_client(sock)
        end
      end
    end
  end

  # Handle a single client connection
  # Reads the request, processes it, and sends back the response
  # @param socket [UNIXSocket] The client socket
  # @return [void]
  def self.handle_client(socket)
    request = JSON.parse(socket.gets, symbolize_names: true)
    return unless request

    response = process_request(request)
    write_response(socket, ok: true, value: response)
  rescue StandardError => e
    write_response(socket, ok: false, error: e.message)
  ensure
    socket.close
  end

  # Process a request hash and return the result
  # Raises an error if the command is unknown
  # @param req [Hash] The request hash containing :cmd and other parameters
  # @return [Object] The result of the command execution
  def self.process_request(req)
    handler = COMMANDS[req[:cmd]]
    raise "Unknown command: #{req[:cmd]}" unless handler

    handler.call(req)
  end

  # Write a response to the client socket
  # @param socket [UNIXSocket] The client socket
  # @param payload [Hash] The response payload
  # @return [void]
  def self.write_response(socket, payload)
    socket.puts(JSON.dump(payload))
  end

end
