# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Mudis::Expiry do
  let(:test_class) do
    Class.new do
      extend Mudis::Expiry
      
      @expiry_thread = nil
      @stop_expiry = false
      @buckets = 2
      @mutexes = Array.new(2) { Mutex.new }
      @stores = Array.new(2) { {} }
      @max_ttl = nil
      @default_ttl = nil
      
      class << self
        attr_accessor :expiry_thread, :stop_expiry, :buckets, :mutexes, :stores, :max_ttl, :default_ttl
        
        def evict_key(idx, key)
          @stores[idx].delete(key)
        end
      end
    end
  end

  after do
    test_class.stop_expiry_thread if test_class.expiry_thread&.alive?
  end

  describe "#start_expiry_thread" do
    it "starts a background cleanup thread" do
      test_class.start_expiry_thread(interval: 0.1)
      
      expect(test_class.expiry_thread).to be_alive
    end

    it "does not start duplicate thread if already running" do
      test_class.start_expiry_thread(interval: 0.1)
      first_thread = test_class.expiry_thread
      
      test_class.start_expiry_thread(interval: 0.1)
      
      expect(test_class.expiry_thread).to eq(first_thread)
    end

    it "periodically calls cleanup_expired!" do
      allow(test_class).to receive(:cleanup_expired!)
      
      test_class.start_expiry_thread(interval: 0.05)
      sleep 0.15
      
      expect(test_class).to have_received(:cleanup_expired!).at_least(:once)
    end
  end

  describe "#stop_expiry_thread" do
    it "stops the background thread" do
      test_class.start_expiry_thread(interval: 0.1)
      
      test_class.stop_expiry_thread
      
      expect(test_class.expiry_thread).to be_nil
    end

    it "sets stop signal" do
      test_class.start_expiry_thread(interval: 0.1)
      
      test_class.stop_expiry_thread
      
      expect(test_class.stop_expiry).to be true
    end

    it "does nothing if thread is not running" do
      expect { test_class.stop_expiry_thread }.not_to raise_error
    end
  end

  describe "#cleanup_expired!" do
    it "removes expired keys from all buckets" do
      now = Time.now
      test_class.stores[0]["expired"] = { expires_at: now - 10 }
      test_class.stores[0]["valid"] = { expires_at: now + 10 }
      test_class.stores[1]["also_expired"] = { expires_at: now - 5 }
      
      test_class.cleanup_expired!
      
      expect(test_class.stores[0]).not_to have_key("expired")
      expect(test_class.stores[0]).to have_key("valid")
      expect(test_class.stores[1]).not_to have_key("also_expired")
    end

    it "keeps keys without expiration" do
      test_class.stores[0]["no_expiry"] = { expires_at: nil }
      
      test_class.cleanup_expired!
      
      expect(test_class.stores[0]).to have_key("no_expiry")
    end

    it "is thread-safe" do
      10.times do |i|
        test_class.stores[0]["key#{i}"] = { expires_at: Time.now - 1 }
      end
      
      threads = 3.times.map do
        Thread.new { test_class.cleanup_expired! }
      end
      
      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "#effective_ttl (private)" do
    it "returns provided expires_in when no constraints" do
      result = test_class.send(:effective_ttl, 300)
      
      expect(result).to eq(300)
    end

    it "returns nil when expires_in is nil and no default" do
      result = test_class.send(:effective_ttl, nil)
      
      expect(result).to be_nil
    end

    it "uses default_ttl when expires_in is nil" do
      test_class.default_ttl = 600
      
      result = test_class.send(:effective_ttl, nil)
      
      expect(result).to eq(600)
    end

    it "clamps to max_ttl when expires_in exceeds it" do
      test_class.max_ttl = 100
      
      result = test_class.send(:effective_ttl, 500)
      
      expect(result).to eq(100)
    end

    it "allows expires_in below max_ttl" do
      test_class.max_ttl = 1000
      
      result = test_class.send(:effective_ttl, 500)
      
      expect(result).to eq(500)
    end

    it "applies max_ttl over default_ttl" do
      test_class.max_ttl = 100
      test_class.default_ttl = 500
      
      result = test_class.send(:effective_ttl, nil)
      
      expect(result).to eq(100)
    end

    it "returns nil when both expires_in and default_ttl are nil" do
      test_class.max_ttl = 1000
      test_class.default_ttl = nil
      
      result = test_class.send(:effective_ttl, nil)
      
      expect(result).to be_nil
    end
  end
end
