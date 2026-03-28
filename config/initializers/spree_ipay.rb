# frozen_string_literal: true

# Spree 5 loads the extension classes directly via Zeitwerk and the engine.
# This file intentionally stays minimal so older serializer monkey-patches do not
# interfere with payment method serialization in the host application.

Spree::PermittedAttributes.source_attributes.push(
	:phone,
	:status,
	:transaction_id,
	:transaction_reference,
	:transaction_amount,
	:transaction_timestamp,
	:metadata
).uniq!