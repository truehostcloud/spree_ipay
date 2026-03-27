source 'https://rubygems.org'

gemspec

# Ruby version requirement
ruby "~> 3.3.8"

gem 'spree', '>= 5.0', '< 6.0'

group :development, :test do
  gem 'rubocop', '~> 1.58', require: false
  gem 'rubocop-performance', '~> 1.19', require: false
  gem 'rubocop-rails', '~> 2.20', require: false
  gem 'rubocop-rspec', '~> 2.25', require: false
end

gem 'elastic-apm', '~> 4.8.0'

group :test do
  gem 'ffaker', '~> 2.23'
  gem 'pry-byebug', '~> 3.10', platform: :mri
  gem 'rspec', '~> 3.10'
  gem 'webmock', '~> 3.18'
end
