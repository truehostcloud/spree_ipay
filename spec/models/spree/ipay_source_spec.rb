require '/home/symomkuu/spree_ipay/spec/rails_helper'

RSpec.describe Spree::IpaySource, type: :model do
  it 'can be instantiated' do
    expect(Spree::IpaySource.new).to be_a(Spree::IpaySource)
  end

  it 'normalizes Kenyan phone numbers with leading 0' do
    source = described_class.new(phone: '0700123456')
    source.valid?
    expect(source.phone).to eq('254700123456')
  end

  it 'removes non-digit characters' do
    source = described_class.new(phone: '+254-700-123-456')
    source.valid?
    expect(source.phone).to eq('254700123456')
  end

  it 'is invalid if phone is blank' do
    source = described_class.new(phone: '')
    expect(source).not_to be_valid
  end
end
