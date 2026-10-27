# frozen_string_literal: true

module Ccn
  # Per-template sender: the `ccn_from_email` template preference ("JMJ 2027 <contact@wyd2027.org>") becomes the
  # From — and, when nothing else sets one, the Reply-To — of every e-mail sent to that template's submitters.
  # Only domains listed in CCN_SMTP_FROM_DOMAINS (comma-separated; authenticated at the SMTP relay) are accepted;
  # with the variable unset the preference is refused and ignored. Absent preference = SMTP_FROM, as upstream.
  #
  # The mailer cannot set the From itself: ActionMailerConfigsInterceptor overwrites it with SMTP_FROM at
  # delivery. So the mailer leaves the address in HEADER, and the interceptor takes it back out (`pop!`) and
  # uses it instead of SMTP_FROM.
  module TemplateSender
    HEADER = 'X-CCN-From'
    PREFERENCE_KEY = 'ccn_from_email'

    module_function

    def allowed_domains
      ENV.fetch('CCN_SMTP_FROM_DOMAINS', '').split(',').map { |domain| domain.strip.downcase }.compact_blank
    end

    # The normalized `"Name" <address>` when the value is one address on an allowed domain, else nil.
    def normalize(value)
      address = Mail::Address.new(value.to_s.strip)

      return if address.address.to_s.match(User::EMAIL_REGEXP).to_s != address.address.to_s
      return unless allowed_domains.include?(address.domain.to_s.downcase)

      address.display_name.present? ? %("#{address.display_name.delete('"')}" <#{address.address}>) : address.address
    rescue Mail::Field::ParseError
      nil
    end

    def address_for(template)
      value = template&.preferences&.dig(PREFERENCE_KEY).presence

      normalize(value) if value
    end

    # The account e-mail config's reply_to, else the template's sender — upstream would fall back to the
    # request's creator, whose personal address is not where replies to a mission's mailing should go.
    def reply_to(template, email_config)
      email_config&.value&.dig('reply_to').presence || address_for(template)
    end

    # Called by the mailer: records the template's sender for the interceptor, returns it (nil when none).
    def claim!(headers, template)
      address = address_for(template)

      headers[HEADER] = address if address

      address
    end

    # Called by the interceptor: removes the header from the outgoing message and returns its address if allowed.
    def pop!(message)
      value = message[HEADER]&.value

      message[HEADER] = nil

      normalize(value) if value
    end
  end
end
