// iPay payment processor
Spree.routes = Spree.routes || {};
Spree.routes.ipay_payments = Spree.pathFor("api/ipay/payments");

Spree.ready(($) => {
  "use strict";

  // Show flash message
  const showFlash = (type, message) => {
    const flashDiv = $(`<div class="alert alert-${type}">${message}</div>`);
    $(".progress-steps").before(flashDiv);
    flashDiv.slideDown();
    setTimeout(() => flashDiv.slideUp(400, () => flashDiv.remove()), 5000);
  };

  // Handle iPay payment form submission
  $(".checkout_form_payment").on("submit", function(e) {
    const $form = $(this);
    const $submitButton = $form.find('input[type="submit"], button[type="submit"]');

    if ($("#payment_method_spree_ipay").is(":checked")) {
      e.preventDefault();
      
      // Show loading state
      const originalText = $submitButton.val() || $submitButton.text();
      $submitButton
        .prop("disabled", true)
        .val(Spree.translations.processing || "Processing...");

      // Clear previous errors
      $(".form-error").remove();
      $(".field_with_errors").removeClass("field_with_errors");

      // Get form data
      const formData = $form.serialize();

      // Submit the form via AJAX with JSON support
      $.ajax({
        url: Spree.pathFor("checkout/update/payment"),
        method: "POST",
        data: formData,
        dataType: "json",
        headers: {
          "X-CSRF-Token": $('meta[name="csrf-token"]').attr("content"),
          "Accept": "application/json"
        }
      })
      .done((response) => {
        if (response.redirect) {
          // Handle redirects (existing functionality)
          window.location.href = response.redirect;
        } else if (response.status === 'success') {
          // New: Handle JSON success response
          if (response.next_step) {
            window.location.href = Spree.pathFor(`checkout/${response.next_step}`);
          } else {
            window.location.reload();
          }
        } else {
          // Fallback to existing behavior
          window.location.reload();
        }
      })
      .fail((xhr) => {
        let errorMessage = "Payment processing failed";
        try {
          const response = JSON.parse(xhr.responseText);
          errorMessage = response.error || response.message || errorMessage;
          
          // Handle form validation errors
          if (response.errors) {
            $.each(response.errors, (field, messages) => {
              const $field = $(`[name*="${field}"]`).first();
              if ($field.length) {
                const $errorDiv = $(`<div class="form-error">${Array.isArray(messages) ? messages.join(", ") : messages}</div>`);
                $field
                  .after($errorDiv)
                  .closest(".form-group")
                  .addClass("field_with_errors");
              }
            });
          }
        } catch (e) {
          console.error("Error parsing error response:", e);
        }
        showFlash('error', errorMessage);
        $submitButton.prop("disabled", false).val(originalText);
      });
    }
  });
});
