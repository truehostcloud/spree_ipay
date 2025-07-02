# frozen_string_literal: true

source 'https://rubygems.org'

# Ruby version
ruby '3.1.4'

# Rails version
gem 'rails', '~> 7.0.4.3'  # Known working version with Ruby 3.1.4

# Spree gems
gem 'spree', '~> 4.5.0'  # Stable version with good Ruby 3.1 support
gem 'spree_gateway', '~> 3.10.0'  # Compatible with Spree 4.5.x
gem 'spree_auth_devise', '~> 4.5.0'  # Compatible with Spree 4.5.x

# This is the current extension being developed
# It will be loaded from the local filesystem
gem 'spree_ipay', path: '.'

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
