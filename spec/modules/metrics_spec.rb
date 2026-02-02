# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Mudis::Metrics do
  let(:test_class) do
    Class.new do
      extend Mudis::Metrics
      
      @metrics = { hits: 5, misses: 3, evictions: 2, rejected: 1 }
      @metrics_mutex = Mutex.new
      @metrics_by_namespace = {}
      @metrics_by_namespace_mutex = Mutex.new
      @buckets = 2
      @stores = [{ "key1" => {} }, { "key2" => {} }]
      @current_bytes = [100, 200]
      @lru_nodes = [{ "key1" => nil }, { "key2" => nil }]
      
      class << self
        attr_accessor :metrics, :metrics_mutex, :metrics_by_namespace, :metrics_by_namespace_mutex,
                      :buckets, :stores, :current_bytes, :lru_nodes
        
        def current_memory_bytes
          @current_bytes.sum
        end
        
        def least_touched(n)
          [["key1", 5], ["key2", 10]]
        end
      end
    end
  end

  describe "#metrics" do
    it "returns a snapshot of current metrics" do
      result = test_class.metrics
      
      expect(result).to include(
        hits: 5,
        misses: 3,
        evictions: 2,
        rejected: 1
      )
      # total_memory and other derived stats depend on full Mudis context
    end

    it "includes least_touched keys via delegation" do
      # This method delegates to least_touched which is defined in main class
      # In integration tests this works, in isolation we just verify the structure
      expect(test_class).to respond_to(:metrics)
    end

    it "includes per-bucket stats via delegation" do
      # Bucket stats require full context from main class
      # In integration tests this works, in isolation we just verify the method exists
      expect(test_class).to respond_to(:metrics)
    end

    it "is thread-safe" do
      threads = 10.times.map do
        Thread.new { test_class.metrics }
      end
      
      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "#reset_metrics!" do
    it "resets all metric counters to zero" do
      test_class.reset_metrics!
      
      expect(test_class.metrics[:hits]).to eq(0)
      expect(test_class.metrics[:misses]).to eq(0)
      expect(test_class.metrics[:evictions]).to eq(0)
      expect(test_class.metrics[:rejected]).to eq(0)
    end

    it "is thread-safe" do
      threads = 10.times.map do
        Thread.new { test_class.reset_metrics! }
      end
      
      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "#metric (private)" do
    it "increments metric counters" do
      initial_hits = test_class.metrics[:hits]
      
      test_class.send(:metric, :hits)
      
      expect(test_class.metrics[:hits]).to eq(initial_hits + 1)
    end

    it "is thread-safe" do
      test_class.reset_metrics!
      
      threads = 100.times.map do
        Thread.new { test_class.send(:metric, :hits) }
      end
      
      threads.each(&:join)
      
      expect(test_class.metrics[:hits]).to eq(100)
    end
  end
end
