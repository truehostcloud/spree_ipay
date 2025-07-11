source 'https://rubygems.org'

# Use local gemspec
gemspec

# Ruby version requirement
ruby "~> 3.3.8"

# Spree core dependencies
gem 'deface', '~> 1.9.0'
gem 'spree', '>= 4.5.0', '< 5.0.0'
gem 'spree_backend', '>= 4.5.0', '< 5.0.0'
gem 'spree_extension', '~> 0.1.0'

group :development, :test do
  gem 'rubocop', '~> 1.58', require: false
  gem 'rubocop-performance', '~> 1.19', require: false
  gem 'rubocop-rails', '~> 2.20', require: false
  gem 'rubocop-rspec', '~> 2.25', require: false
  gem 'elastic-apm', '~> 4.8.0', require: false
end

group :test do
  gem 'ffaker', '~> 2.23'
  gem 'pry-byebug', '~> 3.10', platform: :mri
  gem 'rspec', '~> 3.10'
  gem 'webmock', '~> 3.18'
end
