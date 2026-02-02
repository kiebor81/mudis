# frozen_string_literal: true

require "socket"
require "json"
require_relative "mudis"
require_relative "mudis_ipc_config"

# Socket server for handling Mudis operations via IPC mode
# Automatically uses UNIX sockets on Linux/macOS and TCP on Windows
class MudisServer
  include MudisIPCConfig

  # Define command handlers mapping
  # Each command maps to a lambda that takes a request hash and performs the corresponding Mudis operation.
  COMMANDS = {
    "read" => ->(r) { Mudis.read(r[:key], namespace: r[:namespace]) },
    "write" => ->(r) { Mudis.write(r[:key], r[:value], expires_in: r[:ttl], namespace: r[:namespace]) },
    "delete" => ->(r) { Mudis.delete(r[:key], namespace: r[:namespace]) },
    "exists" => ->(r) { Mudis.exists?(r[:key], namespace: r[:namespace]) },
    "fetch" => ->(r) { Mudis.fetch(r[:key], expires_in: r[:ttl], namespace: r[:namespace]) { r[:fallback] } },
    "inspect" => ->(r) { Mudis.inspect(r[:key], namespace: r[:namespace]) },
    "keys" => ->(r) { Mudis.keys(namespace: r[:namespace]) },
    "clear_namespace" => ->(r) { Mudis.clear_namespace(namespace: r[:namespace]) },
    "least_touched" => ->(r) { Mudis.least_touched(r[:limit]) },
    "all_keys" => ->(_) { Mudis.all_keys },
    "current_memory_bytes" => ->(_) { Mudis.current_memory_bytes },
    "max_memory_bytes" => ->(_) { Mudis.max_memory_bytes },
    "metrics" => ->(_) { Mudis.metrics }
  }.freeze

  # Start the MudisServer
  # Automatically selects TCP on Windows, UNIX sockets elsewhere
  # This will run in a separate thread and handle incoming client connections.
  def self.start!
    if MudisIPCConfig.use_tcp?
      start_tcp_server!
    else
      start_unix_server!
    end
  end

  # Start TCP server (for Windows or development)
  def self.start_tcp_server!
    warn "[MudisServer] Using TCP mode - recommended for development only"
    server = TCPServer.new(TCP_HOST, TCP_PORT)
    puts "[MudisServer] Listening on TCP #{TCP_HOST}:#{TCP_PORT}"
    accept_connections(server)
  end

  # Start UNIX socket server (production mode for Linux/macOS)
  def self.start_unix_server!
    File.unlink(SOCKET_PATH) if File.exist?(SOCKET_PATH)
    server = UNIXServer.new(SOCKET_PATH)
    server.listen(128)
    puts "[MudisServer] Listening on UNIX socket #{SOCKET_PATH}"
    accept_connections(server)
  end

  # Accept connections in a loop (works for both TCP and UNIX)
  def self.accept_connections(server)
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
  # @param socket [Socket] The client socket (TCP or UNIX)
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
  # @param socket [Socket] The client socket
  # @param payload [Hash] The response payload
  # @return [void]
  def self.write_response(socket, payload)
    socket.puts(JSON.dump(payload))
  end
end
