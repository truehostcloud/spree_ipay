# frozen_string_literal: true

require 'bundler/setup'
require 'rspec/core/rake_task'

task :default => :spec

desc 'Run all specs'
RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = '--color --format documentation'
end

desc 'Run a specific test file'
task :spec_file, [:file] do |t, args|
  if args.file
    sh "bundle exec rspec #{args.file}"
  else
    puts 'Please specify a file to test: rake spec_file[path/to/spec.rb]'
  end
end
