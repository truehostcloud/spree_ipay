# frozen_string_literal: true

module Spree
  module Api
    module V2
      module Platform
        class IpaySourceSerializer < BaseSerializer
          include ResourceSerializerConcern

          attributes :id, :phone, :status, :transaction_id, :transaction_reference,
                    :transaction_amount, :transaction_timestamp, :metadata,
                    :created_at, :updated_at

          belongs_to :payment_method, serializer: 'Spree::Api::V2::Platform::PaymentMethod'
          has_many :payments, serializer: 'Spree::Api::V2::Platform::Payment'
        end
      end
    end
  end
end
