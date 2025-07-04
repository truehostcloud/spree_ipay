RSpec.configure do |config|
  config.before :suite do
    # Load all the factories
    FactoryBot.find_definitions
  end

  config.around :each do |example|
    # Reset Spree preferences before each test
    Spree::Config.reset
    example.run
  end
end
