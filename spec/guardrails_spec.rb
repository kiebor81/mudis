# frozen_string_literal: true

require "spec_helper"
require "climate_control"

RSpec.describe "Mudis TTL Guardrail" do # rubocop:disable Metrics/BlockLength
  before do
    Mudis.reset!
    Mudis.configure do |c|
      c.max_ttl = 60 # 60 seconds max
    end
  end

  describe "default_ttl configuration" do # rubocop:disable Metrics/BlockLength
    before do
      Mudis.reset!
      Mudis.configure do |c|
        c.default_ttl = 60
      end
    end

    it "applies default_ttl when expires_in is nil" do
      Mudis.write("foo", "bar") # no explicit expires_in
      meta = Mudis.inspect("foo")
      expect(meta[:expires_at]).not_to be_nil
      expect(meta[:expires_at]).to be_within(5).of(Time.now + 60)
    end

    it "respects expires_in if explicitly given" do
      Mudis.write("short_lived", "bar", expires_in: 10)
      meta = Mudis.inspect("short_lived")
      expect(meta[:expires_at]).not_to be_nil
      expect(meta[:expires_at]).to be_within(5).of(Time.now + 10)
    end

    it "applies max_ttl over default_ttl if both are set" do
      Mudis.configure do |c|
        c.default_ttl = 120
        c.max_ttl = 30
      end

      Mudis.write("capped", "baz") # no explicit expires_in
      meta = Mudis.inspect("capped")
      expect(meta[:expires_at]).not_to be_nil
      expect(meta[:expires_at]).to be_within(5).of(Time.now + 30)
    end

    it "stores forever if default_ttl and expires_in are nil" do
      Mudis.configure do |c|
        c.default_ttl = nil
      end

      Mudis.write("forever", "ever")
      meta = Mudis.inspect("forever")
      expect(meta[:expires_at]).to be_nil
    end
  end

  it "clamps expires_in to max_ttl if it exceeds max_ttl" do
    Mudis.write("foo", "bar", expires_in: 300) # user requests 5 minutes

    metadata = Mudis.inspect("foo")
    ttl = metadata[:expires_at] - metadata[:created_at]

    expect(ttl).to be <= 60
    expect(ttl).to be > 0
  end

  it "respects expires_in if below max_ttl" do
    Mudis.write("bar", "baz", expires_in: 30) # under the max_ttl

    metadata = Mudis.inspect("bar")
    ttl = metadata[:expires_at] - metadata[:created_at]

    expect(ttl).to be_within(1).of(30)
  end

  it "allows nil expires_in (no expiry) if not required" do
    Mudis.write("baz", "no expiry")

    metadata = Mudis.inspect("baz")
    expect(metadata[:expires_at]).to be_nil
  end
end

RSpec.describe "Mudis Configuration Guardrails" do # rubocop:disable Metrics/BlockLength
  after { Mudis.reset! }

  describe "bucket configuration" do
    it "defaults to 32 buckets if ENV is nil" do
      Mudis.instance_variable_set(:@buckets, nil) # force recomputation
      ClimateControl.modify(MUDIS_BUCKETS: nil) do
        expect(Mudis.send(:buckets)).to eq(32)
      end
    end

    it "raises if MUDIS_BUCKETS is 0 or less" do
      expect do
        Mudis.instance_variable_set(:@buckets, nil) # force recomputation
        ClimateControl.modify(MUDIS_BUCKETS: "0") { Mudis.send(:buckets) }
      end.to raise_error(ArgumentError, /bucket count must be > 0/)

      expect do
        Mudis.instance_variable_set(:@buckets, nil) # force recomputation
        ClimateControl.modify(MUDIS_BUCKETS: "-5") { Mudis.send(:buckets) }
      end.to raise_error(ArgumentError, /bucket count must be > 0/)
    end
  end

  describe "memory configuration" do
    it "raises if max_bytes is set to 0 or less" do
      expect do
        Mudis.max_bytes = 0
      end.to raise_error(ArgumentError, /max_bytes must be > 0/)

      expect do
        Mudis.max_bytes = -1
      end.to raise_error(ArgumentError, /max_bytes must be > 0/)
    end

    it "raises if max_value_bytes is 0 or less via config" do
      expect do
        Mudis.configure do |c|
          c.max_value_bytes = 0
        end
      end.to raise_error(ArgumentError, /max_value_bytes must be > 0/)
    end

    it "raises if max_value_bytes exceeds max_bytes" do
      expect do
        Mudis.configure do |c|
          c.max_bytes = 1_000_000
          c.max_value_bytes = 2_000_000
        end
      end.to raise_error(ArgumentError, /max_value_bytes cannot exceed max_bytes/)
    end

    it "raises if eviction_threshold is <= 0 or > 1" do
      expect do
        Mudis.configure do |c|
          c.eviction_threshold = 0
        end
      end.to raise_error(ArgumentError, /eviction_threshold must be > 0 and <= 1/)

      expect do
        Mudis.configure do |c|
          c.eviction_threshold = 1.5
        end
      end.to raise_error(ArgumentError, /eviction_threshold must be > 0 and <= 1/)
    end
  end
end
