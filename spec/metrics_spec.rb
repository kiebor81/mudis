# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Mudis Metrics" do # rubocop:disable Metrics/BlockLength
  it "tracks hits and misses" do
    Mudis.write("hit_me", "value")
    Mudis.read("hit_me")
    Mudis.read("miss_me")
    metrics = Mudis.metrics
    expect(metrics[:hits]).to eq(1)
    expect(metrics[:misses]).to eq(1)
  end

  it "includes per-bucket stats" do
    Mudis.write("a", "x" * 50)
    metrics = Mudis.metrics
    expect(metrics).to include(:buckets)
    expect(metrics[:buckets]).to be_an(Array)
    expect(metrics[:buckets].first).to include(:index, :keys, :memory_bytes, :lru_size)
  end

  it "resets only the metrics without clearing cache" do
    Mudis.write("metrics_key", "value")
    Mudis.read("metrics_key")
    Mudis.read("missing_key")
    expect(Mudis.metrics[:hits]).to eq(1)
    expect(Mudis.metrics[:misses]).to eq(1)
    Mudis.reset_metrics!
    expect(Mudis.metrics[:hits]).to eq(0)
    expect(Mudis.metrics[:misses]).to eq(0)
    expect(Mudis.read("metrics_key")).to eq("value")
  end
end
