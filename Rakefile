require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

desc "Open a terminal with this gem required"
task :irb do
  require 'irb'
  require 'irb/completion'
  require 'code_build_local'
  ARGV.clear
  IRB.start
end
