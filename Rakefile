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

desc "Rebuild the gem"
task :build_local_gem do
  %x(gem build code_build_local.gemspec)
  require_relative "lib/code_build_local/version.rb"
  %x(gem install code_build_local-#{CodeBuildLocal::VERSION}.gem)
end

desc "Rebuild the gem, and open an irb terminal with the gem required"
task :build_local_irb => [:build_local_gem, :irb]
