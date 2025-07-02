source 'https://rubygems.org'

gemspec

# Spree version to test against
gem 'spree', '~> 4.5.0'
gem 'spree_gateway', '~> 3.15.0'

# Test dependencies
group :test do
  gem 'rspec-rails', '~> 5.0'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'shoulda-matchers', '~> 5.0'
  gem 'database_cleaner', '~> 2.0'
  gem 'webmock', '~> 3.14'
  gem 'pg', '~> 1.2'  # For GitHub Actions
end

# Development dependencies
group :development, :test do
  gem 'sqlite3', '~> 1.4'  # For local development
end
