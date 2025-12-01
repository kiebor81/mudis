# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

desc "Run tests with coverage and open report"
task :coverage do
  ENV["COVERAGE"] = "true"
  Rake::Task[:spec].invoke
  
  coverage_file = File.join(__dir__, "coverage", "index.html")
  if File.exist?(coverage_file)
    puts "\nOpening coverage report..."
    system("start", coverage_file) if Gem.win_platform?
    system("open", coverage_file) if RUBY_PLATFORM.include?("darwin")
    system("xdg-open", coverage_file) if RUBY_PLATFORM.include?("linux")
  else
    puts "Coverage report not found at #{coverage_file}"
  end
end

task default: %i[spec rubocop]
