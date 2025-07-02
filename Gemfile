source "https://rubygems.org"

ruby '3.3.6'

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.1.4"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"
gem "mini_racer", platforms: %i[ ruby jruby ] # fixes Could not find a JavaScript runtime

# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 1.4"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 5.6"

# JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Spree gems
gem 'spree', '~> 4.7.0'
gem 'spree_gateway', '~> 3.10.0'
gem 'spree_auth_devise', '~> 4.7.0'
gem 'spree_extension', '~> 0.1.0'

# This is the current extension being developed
gem 'spree_ipay', path: '.'

group :test do
  gem 'rspec-rails', '~> 5.0'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'shoulda-matchers', '~> 5.0'
  gem 'database_cleaner', '~> 2.0'
  gem 'webmock', '~> 3.14'
  gem 'pg', '~> 1.2'  # For GitHub Actions
  gem 'ffaker', '~> 2.21'  # For test data generation
end

group :development, :test do
  gem 'sqlite3', '~> 1.4'  # For local development
  gem 'pry-byebug', '~> 3.9'  # Debugging
  gem 'dotenv-rails', '~> 2.8'  # For environment variables
end
