# frozen_string_literal: true

begin
  require 'bundler/setup'
rescue LoadError => e
  puts "Error loading bundler: #{e.message}"
end

# Load Rails and Spree tasks if Rails is available
begin
  require 'rails'
  require 'rails/all'
  
  # Load the dummy app if it exists
  if File.exist?(File.expand_path('spec/dummy/config/application.rb'))
    ENV['RAILS_ENV'] ||= 'test'
    require File.expand_path('spec/dummy/config/environment.rb')
  end
  
  # Load Rails Rake tasks
  Rails.application.load_tasks
  
  # Load Spree tasks
  %w[spree_core spree_backend spree_api spree_extension].each do |engine|
    begin
      require engine
      engine_rake = "#{engine}/lib/tasks"
      load "#{engine_rake}/#{engine}_tasks.rake" if File.directory?(engine_rake)
    rescue LoadError => e
      puts "Warning: Could not load #{engine} tasks: #{e.message}"
    end
  end
rescue LoadError => e
  puts "Warning: Could not load Rails: #{e.message}"
end

# Load custom tasks from the lib/tasks directory
Dir.glob('lib/tasks/**/*.rake').each { |r| load r }
