# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'spree_ipay'
  spec.version       = '1.0.0'
  spec.authors       = ['Your Name']
  spec.email         = ['your.email@example.com']
  spec.summary       = 'iPay payment integration for Spree Commerce'
  spec.description   = 'Spree extension that integrates iPay payment gateway with server-to-server communication'
  spec.homepage      = 'https://github.com/yourusername/spree_ipay'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 2.7.0'

  spec.files = Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']
  spec.require_paths = ['lib']

  # Core dependencies
  spec.required_ruby_version = '>= 3.3.6'
  spec.add_dependency 'rails', '~> 7.1.4'
  
  # Spree dependencies
  spec.add_dependency 'spree_core', '~> 4.7.0'
  spec.add_dependency 'spree_backend', '~> 4.7.0'
  spec.add_dependency 'spree_api', '~> 4.7.0'
  spec.add_dependency 'spree_auth_devise', '~> 4.7.0'
  spec.add_dependency 'spree_gateway', '~> 3.10.0'
  spec.add_dependency 'spree_extension', '~> 0.1.0'

  # Development and test dependencies
  spec.add_development_dependency 'database_cleaner', '~> 2.0'
  spec.add_development_dependency 'factory_bot_rails', '~> 6.2'
  spec.add_development_dependency 'pg', '~> 1.2'  # For testing with PostgreSQL
  spec.add_development_dependency 'rspec-rails', '~> 5.0'
  spec.add_development_dependency 'shoulda-matchers', '~> 5.0'
  spec.add_development_dependency 'sqlite3', '~> 1.4'  # For local testing
  spec.add_development_dependency 'webmock', '~> 3.14'  # For stubbing HTTP requests
end