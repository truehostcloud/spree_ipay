//= require spree/frontend

SpreeIpay = {
  checkPaymentStatus: function(orderNumber) {
    var statusUrl = '/spree_ipay/status_check';
    
    return $.ajax({
      url: statusUrl,
      type: 'GET',
      dataType: 'json'
    });
  },

  startStatusPolling: function(orderNumber, callback) {
    var pollInterval = 3000; // 3 seconds
    var maxAttempts = 60; // 3 minutes total
    var attempts = 0;

    var poll = function() {
      attempts++;
      
      SpreeIpay.checkPaymentStatus(orderNumber)
        .done(function(response) {
          if (response.status === 'completed') {
            callback('success', response);
          } else if (response.status === 'failed') {
            callback('failed', response);
          } else if (attempts >= maxAttempts) {
            callback('timeout', response);
          } else {
            setTimeout(poll, pollInterval);
          }
        })
        .fail(function() {
          if (attempts >= maxAttempts) {
            callback('error', { message: 'Failed to check payment status' });
          } else {
            setTimeout(poll, pollInterval);
          }
        });
    };

    poll();
  },

  showPaymentStatus: function(message, type) {
    var alertClass = type === 'success' ? 'alert-success' : 'alert-danger';
    var statusHtml = '<div class="alert ' + alertClass + '">' + message + '</div>';
    
    $('#payment-status').html(statusHtml);
  }
};

$(document).ready(function() {
  // Auto-start polling if we're on checkout completion page with pending iPay payment
  if ($('#ipay-payment-pending').length > 0) {
    var orderNumber = $('#ipay-payment-pending').data('order-number');
    
    SpreeIpay.showPaymentStatus('Processing your payment, please wait...', 'info');
    
    SpreeIpay.startStatusPolling(orderNumber, function(status, response) {
      switch(status) {
        case 'success':
          SpreeIpay.showPaymentStatus('Payment completed successfully!', 'success');
          setTimeout(function() {
            window.location.href = '/orders/' + orderNumber;
          }, 2000);
          break;
        case 'failed':
          SpreeIpay.showPaymentStatus('Payment failed. Please try again.', 'error');
          break;
        case 'timeout':
          SpreeIpay.showPaymentStatus('Payment status check timed out. Please check your order status.', 'error');
          break;
        case 'error':
          SpreeIpay.showPaymentStatus('Error checking payment status. Please refresh the page.', 'error');
          break;
      }
    });
  }
});