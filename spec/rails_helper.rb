# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require 'bundler/setup'
require 'spree/testing_support/dummy_app'
require 'rspec/rails'
require 'factory_bot_rails'
require 'database_cleaner/active_record'

# Load support files
Dir["./spec/support/**/*.rb"].sort.each { |f| require f }

# Load factories
FactoryBot.definition_file_paths = ['spec/factories']
FactoryBot.find_definitions

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
  
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
