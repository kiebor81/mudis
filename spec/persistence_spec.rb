# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "Mudis soft persistence" do
  let(:path) { "tmp/test_mudis_snapshot.dump" }

  before do
    FileUtils.rm_f(path)
    Mudis.reset!
    Mudis.configure do |c|
      c.persistence_enabled = true
      c.persistence_path    = path
      c.persistence_format  = :marshal
    end
  end

  it "saves on exit and loads on next boot" do
    Mudis.write("k1", "v1", expires_in: 60)
    # simulate shutdown
    Mudis.save_snapshot!
    Mudis.reset!

    # simulate fresh boot (apply config + load)
    Mudis.apply_config! # if not public, re-configure to trigger load
    Mudis.load_snapshot!

    expect(Mudis.read("k1")).to eq("v1")
  end

  it "does nothing when file missing" do
    Mudis.reset!
    Mudis.configure { |c| c.persistence_enabled = true; c.persistence_path = path } # rubocop:disable Style/Semicolon
    Mudis.load_snapshot! # no file
    expect(Mudis.read("any")).to be_nil
  end
end
