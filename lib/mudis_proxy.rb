# frozen_string_literal: true

# Optional Mudis proxy layer for IPC mode.
#
# To enable:
#   require "mudis_proxy"
#
# The proxy will forward calls to `$mudis` (an instance of MudisClient)
# if it is defined, otherwise fallback to standard in-process behaviour.
#
# Note that this file must be required *after* MudisClient and MudisServer
# have been loaded, otherwise the proxy will not be activated.

if defined?(MudisServer)
  # In the master process — no proxy needed.
  return
end

unless defined?(MudisClient)
  warn "[MudisProxy] MudisClient not loaded — proxy not activated"
  return
end

class << Mudis
  def read(*a, **k) = $mudis.read(*a, **k) # rubocop:disable Naming/MethodParameterName,Style/GlobalVars
  def write(*a, **k) = $mudis.write(*a, **k) # rubocop:disable Naming/MethodParameterName,Style/GlobalVars
  def delete(*a, **k) = $mudis.delete(*a, **k) # rubocop:disable Naming/MethodParameterName,Style/GlobalVars
  def fetch(*a, **k, &b) = $mudis.fetch(*a, **k, &b) # rubocop:disable Naming/MethodParameterName,Style/GlobalVars
  def metrics = $mudis.metrics # rubocop:disable Style/GlobalVars
  def reset_metrics! = $mudis.reset_metrics! # rubocop:disable Style/GlobalVars
  def reset! = $mudis.reset! # rubocop:disable Style/GlobalVars
end
