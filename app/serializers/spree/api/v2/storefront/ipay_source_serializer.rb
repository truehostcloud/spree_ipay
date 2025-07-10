# frozen_string_literal: true

module Spree
  module Api
    module V2
      module Storefront
        class IpaySourceSerializer < BaseSerializer
          set_type :ipay_source

          attributes :id, :transaction_id, :status, :created_at
        end
      end
    end
  end
end
