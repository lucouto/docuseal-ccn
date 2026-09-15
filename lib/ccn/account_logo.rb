# frozen_string_literal: true

module Ccn
  # Stage 4, US2 (specs/003-p1-features): the account's own logo, shown to signers and in their e-mails in
  # place of the DocuSeal mark. One `include` in Account (research D8), so a rebase touches a single line.
  #
  # The attachment is named `logo` on purpose: both blob proxies already serve an attachment of that name
  # without a session (upstream's Pro name), which is what lets an e-mail client fetch it.
  module AccountLogo
    extend ActiveSupport::Concern

    CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
    # A client that claims one of these is claiming nothing in particular, so its bytes are taken at face
    # value rather than treated as a mismatch.
    GENERIC_TYPES = ['', 'application/octet-stream', 'binary/octet-stream'].freeze
    MAX_BYTES = 2.megabytes

    included do
      has_one_attached :logo

      validate :ccn_logo_format
    end

    # An e-mail can only carry the logo when the instance knows its own absolute URL: with APP_URL unset and
    # no app_url setting, Docuseal.default_url_options falls back to localhost — a broken image in an inbox,
    # so the e-mail keeps the DocuSeal mark instead and the settings page says why.
    def self.email_host_configured?
      return true if ENV['APP_URL'].present?

      EncryptedConfig.find_by(key: EncryptedConfig::APP_URL_KEY)&.value.present?
    end

    # The signer-facing pages are rendered from whichever of these the controller happened to set
    # (a Submitter on the signing page, a Submission or a Template on the start form and its variants).
    def self.account_for(*records)
      records.compact.lazy.filter_map { |record| record.try(:account) }.first
    end

    private

    # Runs only on the save that attaches: a stored logo is not re-read (nor the storage service hit) every
    # time the account is saved for some other reason.
    def ccn_logo_format
      change = attachment_changes['logo']

      return if change.blank? || !change.respond_to?(:attachable)

      ccn_validate_logo_size(change.blob)
      ccn_validate_logo_type(change)
    end

    def ccn_validate_logo_size(blob)
      return if blob.byte_size.to_i <= MAX_BYTES

      errors.add(:base, I18n.t('ccn_logo_too_large', max: MAX_BYTES / 1.megabyte))
    end

    # The magic bytes decide: an SVG (scripted content in an e-mail client) renamed `.png` and declared
    # `image/png` reads as application/xml here, whatever the browser said. A declared type that names a
    # *different* type is refused too, but a client that claims nothing in particular — a blank type, or the
    # `application/octet-stream` some file managers send for a perfectly good PNG — is taken at its bytes.
    def ccn_validate_logo_type(change)
      declared = ccn_declared_content_type(change).to_s
      detected = ccn_detected_content_type(change.attachable)

      return if CONTENT_TYPES.include?(detected) && (declared == detected || GENERIC_TYPES.include?(declared))

      errors.add(:base, I18n.t('ccn_logo_invalid_type'))
    end

    def ccn_declared_content_type(change)
      attachable = change.attachable

      declared =
        if attachable.is_a?(Hash)
          attachable[:content_type]
        elsif attachable.respond_to?(:content_type)
          attachable.content_type
        end

      declared.presence || change.blob.content_type
    end

    # Magic bytes only — no filename hint, which is client-controlled. Bytes we cannot read (a signed id, a
    # blob attached from elsewhere) are not accepted rather than trusted: nothing in the fork attaches a logo
    # any way other than as an uploaded file.
    def ccn_detected_content_type(attachable)
      io = attachable.is_a?(Hash) ? attachable[:io] : attachable

      return unless io.respond_to?(:read) && io.respond_to?(:rewind)

      io.rewind
      Marcel::MimeType.for(io)
    ensure
      io.rewind if io.respond_to?(:rewind)
    end
  end
end
