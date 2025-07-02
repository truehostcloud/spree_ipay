# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Spree version to test against
ruby '3.3.8'

# Pin Rails to a version compatible with Spree 4.10.0
gem 'rails', '~> 7.0.8'

# Spree gems
gem 'spree', '~> 4.10.0'
gem 'spree_gateway', '~> 3.10.0'  # Compatible with Spree 4.10.0
gem 'spree_auth_devise', '~> 4.10.0'

group :test do
  gem 'rspec-rails', '~> 5.0'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'shoulda-matchers', '~> 5.0'
  gem 'database_cleaner', '~> 2.0'
  gem 'webmock', '~> 3.14'
  gem 'pg', '~> 1.2'  # For GitHub Actions
  gem 'ffaker', '~> 2.21'  # For test data generation
  gem 'puma', '~> 5.6'  # Web server for test environment
end

group :development, :test do
  gem 'sqlite3', '~> 1.4'  # For local development
  gem 'pry-byebug', '~> 3.9'  # Debugging
  gem 'dotenv-rails', '~> 2.8'  # For environment variables
end
