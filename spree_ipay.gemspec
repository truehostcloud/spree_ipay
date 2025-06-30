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

  spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage

  spec.files = Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'importmap-rails', '~> 1.2.1'
  spec.add_development_dependency 'rspec-rails'
  spec.add_development_dependency 'sqlite3'
end