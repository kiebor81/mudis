# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Mudis::Persistence do
  let(:test_class) do
    Class.new do
      extend Mudis::Persistence
      
      @persistence_enabled = true
      @persistence_path = "tmp/test_persistence.json"
      @persistence_format = :json
      @persistence_safe_write = true
      @buckets = 2
      @mutexes = Array.new(2) { Mutex.new }
      @stores = Array.new(2) { {} }
      @lru_nodes = Array.new(2) { {} }
      @lru_heads = Array.new(2) { nil }
      @lru_tails = Array.new(2) { nil }
      @current_bytes = Array.new(2, 0)
      @compress = false
      @serializer = JSON
      
      class << self
        attr_accessor :persistence_enabled, :persistence_path, :persistence_format, 
                      :persistence_safe_write, :buckets, :mutexes, :stores, :compress, :serializer
        
        def decompress_and_deserialize(raw)
          JSON.load(raw)
        end
        
        def write(key, value, expires_in: nil)
          # Stub write method
          @stores[0][key] = { value: JSON.dump(value), expires_at: nil, created_at: Time.now }
        end
      end
    end
  end

  after do
    File.unlink(test_class.persistence_path) if File.exist?(test_class.persistence_path)
  end

  describe "#save_snapshot!" do
    it "saves cache data to disk" do
      test_class.stores[0]["key1"] = { 
        value: JSON.dump("value1"), 
        expires_at: nil, 
        created_at: Time.now 
      }
      
      test_class.save_snapshot!
      
      expect(File.exist?(test_class.persistence_path)).to be true
    end

    it "handles errors gracefully" do
      allow(test_class).to receive(:snapshot_dump).and_raise("Test error")
      
      expect { test_class.save_snapshot! }.to output(/Failed to save snapshot/).to_stderr
    end

    it "does nothing when persistence is disabled" do
      test_class.persistence_enabled = false
      
      test_class.save_snapshot!
      
      expect(File.exist?(test_class.persistence_path)).to be false
    end
  end

  describe "#load_snapshot!" do
    it "loads cache data from disk" do
      data = [{ key: "test_key", value: "test_value", expires_in: nil }]
      File.write(test_class.persistence_path, JSON.dump(data))
      
      expect(test_class).to receive(:write).with("test_key", "test_value", expires_in: nil)
      
      test_class.load_snapshot!
    end

    it "handles missing file gracefully" do
      expect { test_class.load_snapshot! }.not_to raise_error
    end

    it "handles errors gracefully" do
      File.write(test_class.persistence_path, "invalid json")
      
      expect { test_class.load_snapshot! }.to output(/Failed to load snapshot/).to_stderr
    end

    it "does nothing when persistence is disabled" do
      test_class.persistence_enabled = false
      File.write(test_class.persistence_path, JSON.dump([]))
      
      expect(test_class).not_to receive(:write)
      
      test_class.load_snapshot!
    end
  end

  describe "#install_persistence_hook!" do
    it "installs at_exit hook" do
      expect(test_class).to receive(:at_exit)
      
      test_class.install_persistence_hook!
    end

    it "only installs hook once" do
      test_class.install_persistence_hook!
      
      expect(test_class).not_to receive(:at_exit)
      
      test_class.install_persistence_hook!
    end

    it "does nothing when persistence is disabled" do
      test_class.persistence_enabled = false
      
      expect(test_class).not_to receive(:at_exit)
      
      test_class.install_persistence_hook!
    end
  end
end
