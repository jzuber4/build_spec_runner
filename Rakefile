require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

desc "Open a terminal with this gem required"
task :irb do
  require 'irb'
  require 'irb/completion'
  require 'build_spec_runner'
  ARGV.clear
  IRB.start
end
