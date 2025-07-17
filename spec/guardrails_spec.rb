# frozen_string_literal: true

require "spec_helper"
require "climate_control"

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
  end
end
