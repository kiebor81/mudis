# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Mudis Namespace Operations" do # rubocop:disable Metrics/BlockLength
  before(:each) do
    Mudis.reset!
  end

  it "uses thread-local namespace in block" do
    Mudis.with_namespace("test") do
      Mudis.write("foo", "bar")
    end
    expect(Mudis.read("foo", namespace: "test")).to eq("bar")
    expect(Mudis.read("foo")).to be_nil
  end

  it "supports explicit namespace override" do
    Mudis.write("x", 1, namespace: "alpha")
    Mudis.write("x", 2, namespace: "beta")
    expect(Mudis.read("x", namespace: "alpha")).to eq(1)
    expect(Mudis.read("x", namespace: "beta")).to eq(2)
    expect(Mudis.read("x")).to be_nil
  end

  it "does not double-prefix keys in exists? under thread namespace" do
    Mudis.with_namespace("ns") do
      Mudis.write("k", "v")
      expect(Mudis.exists?("k")).to be true
    end
  end

  it "does not double-prefix keys in fetch under thread namespace" do
    Mudis.with_namespace("ns") do
      value = Mudis.fetch("k") { "v" }
      expect(value).to eq("v")
      expect(Mudis.read("k")).to eq("v")
    end
  end

  it "does not double-prefix keys in replace under thread namespace" do
    Mudis.with_namespace("ns") do
      Mudis.write("k", "v")
      Mudis.replace("k", "v2")
      expect(Mudis.read("k")).to eq("v2")
    end
  end

  describe ".keys" do
    it "returns only keys for the given namespace" do
      Mudis.write("user:1", "Alice", namespace: "users")
      Mudis.write("user:2", "Bob", namespace: "users")
      Mudis.write("admin:1", "Charlie", namespace: "admins")

      result = Mudis.keys(namespace: "users")
      expect(result).to contain_exactly("user:1", "user:2")
    end

    it "returns an empty array if no keys exist for namespace" do
      expect(Mudis.keys(namespace: "nonexistent")).to eq([])
    end

    it "raises an error if namespace is missing" do
      expect { Mudis.keys(namespace: nil) }.to raise_error(ArgumentError, /namespace is required/)
    end
  end

  describe ".clear_namespace" do
    it "deletes all keys in the given namespace" do
      Mudis.write("a", 1, namespace: "ns1")
      Mudis.write("b", 2, namespace: "ns1")
      Mudis.write("x", 9, namespace: "ns2")

      expect(Mudis.read("a", namespace: "ns1")).to eq(1)
      expect(Mudis.read("b", namespace: "ns1")).to eq(2)

      Mudis.clear_namespace(namespace: "ns1")

      expect(Mudis.read("a", namespace: "ns1")).to be_nil
      expect(Mudis.read("b", namespace: "ns1")).to be_nil
      expect(Mudis.read("x", namespace: "ns2")).to eq(9)
    end

    it "does nothing if namespace has no keys" do
      expect { Mudis.clear_namespace(namespace: "ghost") }.not_to raise_error
    end

    it "raises an error if namespace is nil" do
      expect { Mudis.clear_namespace(namespace: nil) }.to raise_error(ArgumentError, /namespace is required/)
    end
  end
end
