// Backend iPay integration for Spree
Spree.ready(($) => {
  'use strict';

  /**
   * Toggle iPay settings based on payment method selection
   */
  const toggleIpaySettings = (event) => {
    const isIpay = $(event.target).val() === 'Spree::PaymentMethod::Ipay';
    $('.ipay-settings').toggle(isIpay);
  };

  // Initialize event listeners
  $(document)
    .on('change', '.payment-method-type-select', toggleIpaySettings)
    .ready(() => {
      // Initialize on page load
      $('.payment-method-type-select').trigger('change');
    });
});
