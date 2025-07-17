# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Mudis Reset Features" do
  before { Mudis.reset! }

  describe ".reset!" do
    it "clears all stores, memory, and metrics" do
      Mudis.write("reset_key", "value")
      expect(Mudis.read("reset_key")).to eq("value")
      Mudis.reset!
      expect(Mudis.metrics[:hits]).to eq(0)
      expect(Mudis.all_keys).to be_empty
      expect(Mudis.read("reset_key")).to be_nil
    end
  end

  describe ".reset_metrics!" do
    it "resets only the metrics without clearing cache" do
      Mudis.write("metrics_key", "value")
      Mudis.read("metrics_key")
      Mudis.read("missing_key")
      expect(Mudis.metrics[:hits]).to eq(1)
      expect(Mudis.metrics[:misses]).to eq(1)
      Mudis.reset_metrics!
      expect(Mudis.metrics[:hits]).to eq(0)
      expect(Mudis.read("metrics_key")).to eq("value")
    end
  end
end
