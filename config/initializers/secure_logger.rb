# frozen_string_literal: true

# Ensure the services directory is in the autoload path
services_path = File.join(Rails.root, 'app', 'services')
unless $LOAD_PATH.include?(services_path)
  $LOAD_PATH.unshift(services_path)
  ActiveSupport::Dependencies.autoload_paths << services_path
end

# Load the SecureLogger
require 'spree/ipay/secure_logger'

Rails.logger.debug 'SecureLogger initializer loaded successfully'
