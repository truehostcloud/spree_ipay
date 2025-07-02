# frozen_string_literal: true

require_relative 'config/application'
require 'rake'

Rails.application.load_tasks

# Load tasks from spree_core and other engines
%w[spree_core spree_backend spree_api spree_extension].each do |engine|
  begin
    require engine
    engine_rake = "#{engine}/lib/tasks"
    load "#{engine_rake}/#{engine}_tasks.rake" if Dir.exist?(engine_rake)
  rescue LoadError
    # Skip if the engine is not available
  end
end

# Load custom tasks from the lib/tasks directory
Dir.glob('lib/tasks/**/*.rake').each { |r| load r }
