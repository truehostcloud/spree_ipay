# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'spree_ipay'
  spec.version       = '1.0.10'
  spec.authors       = ['Simon Njunge']
  spec.email         = ['simon.k@cloudoon.com']
  spec.summary       = 'iPay payment integration for Spree Commerce'
  spec.description   = 'Spree extension that integrates iPay payment gateway with server-to-server communication'
  spec.homepage      = 'https://github.com/yourusername/spree_ipay'
  spec.license       = 'MIT'

  spec.files = Dir['{app,config,db,lib}/**/*', 'LICENSE', 'MIT-LICENSE', 'Rakefile', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'spree', '>= 5.0', '< 6.0'
  spec.required_ruby_version = '~> 3.3.6'

  spec.add_dependency 'rails', '~> 7.2.0'
  spec.add_dependency 'httparty', '~> 0.16.0'
  spec.add_dependency 'rack-attack', '~> 6.7'
  spec.add_dependency 'elastic-apm', '~> 4.8.0'

  spec.add_development_dependency 'capybara', '~> 3.38'
  spec.add_development_dependency 'database_cleaner-active_record', '~> 2.0'
  spec.add_development_dependency 'factory_bot_rails', '~> 6.2.0'
  spec.add_development_dependency 'pry', '~> 0.14.1'
  spec.add_development_dependency 'rspec-rails', '~> 6.0.0'
  spec.add_development_dependency 'sqlite3', '~> 1.4.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
end