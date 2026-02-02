# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Mudis::Bound do
  before do
    Mudis.reset!
    Mudis.serializer = JSON
    Mudis.compress = false
  end

  it "scopes reads and writes to the bound namespace" do
    bound = Mudis.bind(namespace: "caller")
    bound.write("k", "v")

    expect(Mudis.read("k")).to be_nil
    expect(bound.read("k")).to eq("v")
    expect(Mudis.read("k", namespace: "caller")).to eq("v")
  end

  it "applies default_ttl and max_ttl within the scope" do
    bound = Mudis.bind(namespace: "caller", default_ttl: 120, max_ttl: 30)
    bound.write("k", "v")

    meta = bound.inspect("k")
    expect(meta[:expires_at]).not_to be_nil
    expect(meta[:expires_at]).to be_within(5).of(Time.now + 30)
  end

  it "rejects values that exceed max_value_bytes" do
    bound = Mudis.bind(namespace: "caller", max_value_bytes: 10)
    bound.write("k", "a" * 20)

    expect(bound.read("k")).to be_nil
  end

  it "rejects updates that exceed max_value_bytes" do
    bound = Mudis.bind(namespace: "caller", max_value_bytes: 10)
    bound.write("k", "ok")

    bound.update("k") { "a" * 20 }
    expect(bound.read("k")).to eq("ok")
  end

  it "fetches within the bound namespace" do
    bound = Mudis.bind(namespace: "caller")
    value = bound.fetch("k") { "v" }

    expect(value).to eq("v")
    expect(Mudis.read("k")).to be_nil
    expect(bound.read("k")).to eq("v")
  end

  it "executes the block once with singleflight: true" do
    bound = Mudis.bind(namespace: "caller")
    count = 0
    count_mutex = Mutex.new
    results = []
    results_mutex = Mutex.new

    threads = 5.times.map do
      Thread.new do
        value = bound.fetch("sf", singleflight: true) do
          count_mutex.synchronize { count += 1 }
          sleep 0.05
          "v"
        end
        results_mutex.synchronize { results << value }
      end
    end

    threads.each(&:join)
    expect(count).to eq(1)
    expect(results).to all(eq("v"))
    expect(bound.read("sf")).to eq("v")
  end

  it "exposes metrics scoped to the bound namespace" do
    bound = Mudis.bind(namespace: "caller")
    bound.write("k", "v")
    bound.read("k")
    bound.read("missing")

    metrics = bound.metrics
    expect(metrics[:namespace]).to eq("caller")
    expect(metrics[:hits]).to eq(1)
    expect(metrics[:misses]).to eq(1)
  end
end
