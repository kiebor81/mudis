# spec/mudis_spec.rb
require_relative 'spec_helper'

RSpec.describe Mudis do
  before(:each) do
    Mudis.stop_expiry_thread
    Mudis.instance_variable_set(:@buckets, nil)
    Mudis.instance_variable_set(:@stores, Array.new(Mudis.buckets) { {} })
    Mudis.instance_variable_set(:@mutexes, Array.new(Mudis.buckets) { Mutex.new })
    Mudis.instance_variable_set(:@lru_heads, Array.new(Mudis.buckets) { nil })
    Mudis.instance_variable_set(:@lru_tails, Array.new(Mudis.buckets) { nil })
    Mudis.instance_variable_set(:@lru_nodes, Array.new(Mudis.buckets) { {} })
    Mudis.instance_variable_set(:@current_bytes, Array.new(Mudis.buckets, 0))
    Mudis.instance_variable_set(:@metrics, { hits: 0, misses: 0, evictions: 0 })
    Mudis.serializer = JSON
    Mudis.compress = false
    Mudis.max_value_bytes = nil
  end

  describe '.write and .read' do
    it 'writes and reads a value' do
      Mudis.write('foo', { bar: 'baz' })
      result = Mudis.read('foo')
      expect(result).to eq({ 'bar' => 'baz' })
    end

    it 'returns nil for non-existent keys' do
      expect(Mudis.read('nope')).to be_nil
    end
  end

  describe '.exists?' do
    it 'returns true if key exists' do
      Mudis.write('check', [1, 2, 3])
      expect(Mudis.exists?('check')).to be true
    end

    it 'returns false if key does not exist' do
      expect(Mudis.exists?('missing')).to be false
    end
  end

  describe '.delete' do
    it 'deletes a key' do
      Mudis.write('temp', 42)
      Mudis.delete('temp')
      expect(Mudis.read('temp')).to be_nil
    end
  end

  describe '.update' do
    it 'updates a cached value' do
      Mudis.write('counter', 5)
      Mudis.update('counter') { |v| v + 1 }
      expect(Mudis.read('counter')).to eq(6)
    end
  end

  describe 'expiry handling' do
    it 'expires values after specified time' do
      Mudis.write('short_lived', 'gone soon', expires_in: 1)
      sleep 2
      expect(Mudis.read('short_lived')).to be_nil
    end
  end

  describe '.metrics' do
    it 'tracks hits and misses' do
      Mudis.write('hit_me', 'value')
      Mudis.read('hit_me')   # hit
      Mudis.read('miss_me')  # miss
      metrics = Mudis.metrics
      expect(metrics[:hits]).to eq(1)
      expect(metrics[:misses]).to eq(1)
    end
  end

  describe 'LRU eviction' do
    it 'evicts old entries when size limit is reached' do
      Mudis.stop_expiry_thread
  
      # Force one bucket
      Mudis.instance_variable_set(:@buckets, 1)
      Mudis.instance_variable_set(:@stores, [{}])
      Mudis.instance_variable_set(:@mutexes, [Mutex.new])
      Mudis.instance_variable_set(:@lru_heads, [nil])
      Mudis.instance_variable_set(:@lru_tails, [nil])
      Mudis.instance_variable_set(:@lru_nodes, [{}])
      Mudis.instance_variable_set(:@current_bytes, [0])
  
      # Set very small threshold
      Mudis.instance_variable_set(:@threshold_bytes, 60)
      Mudis.max_value_bytes = 100
  
      big_val1 = 'a' * 50
      big_val2 = 'b' * 50
  
      Mudis.write('a', big_val1)
      Mudis.write('b', big_val2)
  
      expect(Mudis.read('a')).to be_nil
      expect(Mudis.read('b')).not_to be_nil
    end
  end
    
  describe '.all_keys' do
    it 'lists all stored keys' do
      Mudis.write('k1', 1)
      Mudis.write('k2', 2)
      expect(Mudis.all_keys).to include('k1', 'k2')
    end
  end

  describe '.current_memory_bytes' do
    it 'returns a non-zero byte count after writes' do
      Mudis.write('size_test', 'a' * 100)
      expect(Mudis.current_memory_bytes).to be > 0
    end
  end
end