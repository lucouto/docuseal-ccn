# frozen_string_literal: true

require 'net/http'

module Ccn
  # Client for the Gotenberg conversion sidecar (FORK-PLAN.md §5.2): the LibreOffice route turns office
  # documents into PDF, the Chromium route renders HTML. Plain Net::HTTP multipart (no extra gem). Every
  # failure is a typed error that the callers turn into HTTP 422; nothing is retried or falls back silently.
  module Gotenberg
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 60
    LIBREOFFICE_PATH = 'forms/libreoffice/convert'
    CHROMIUM_HTML_PATH = 'forms/chromium/convert/html'

    class Error < StandardError; end
    class Unavailable < Error; end
    class TimedOut < Error; end

    class Rejected < Error
      attr_reader :status

      def initialize(status, body = nil)
        @status = status

        super("Gotenberg answered #{status}: #{body.to_s[0, 200]}")
      end
    end

    CONNECTION_ERRORS = [Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
                         SocketError, Net::HTTPBadResponse, EOFError].freeze
    TIMEOUT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout].freeze

    module_function

    def configured?
      !Ccn::GOTENBERG_URL.nil?
    end

    # Office document (docx, doc, odt, rtf, xlsx, xls) → PDF bytes.
    def docx_to_pdf(io, filename)
      post(LIBREOFFICE_PATH, [['files', io, { filename: filename.to_s }]])
    end

    # HTML (+ optional header / footer HTML) → PDF bytes on the given paper size (a Ccn::PAGE_SIZES key).
    def html_to_pdf(html, header: nil, footer: nil, size: Ccn::DEFAULT_PAGE_SIZE)
      width, height = Ccn::PAGE_SIZES.fetch(size.to_s) { raise ArgumentError, "unknown page size: #{size}" }

      form = [
        ['files', StringIO.new(html.to_s), { filename: 'index.html', content_type: 'text/html' }],
        ['paperWidth', width.to_s], ['paperHeight', height.to_s], %w[printBackground true]
      ]
      form << ['files', StringIO.new(header), { filename: 'header.html', content_type: 'text/html' }] if header.present?
      form << ['files', StringIO.new(footer), { filename: 'footer.html', content_type: 'text/html' }] if footer.present?

      post(CHROMIUM_HTML_PATH, form)
    end

    def post(path, form)
      raise Unavailable, 'GOTENBERG_URL is not configured' unless configured?

      uri = URI.parse("#{Ccn::GOTENBERG_URL}/#{path}")
      boundary = "ccn-#{SecureRandom.hex(16)}"
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      request.body = multipart_body(form, boundary)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: OPEN_TIMEOUT,
                                                     read_timeout: READ_TIMEOUT, write_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      raise Rejected.new(response.code.to_i, response.body) unless response.is_a?(Net::HTTPSuccess)

      response.body
    rescue *TIMEOUT_ERRORS => e
      raise TimedOut, e.message
    rescue *CONNECTION_ERRORS => e
      raise Unavailable, e.message
    end

    # form = [[name, value], [name, io_or_string, { filename:, content_type: }], ...]. Net::HTTP#set_form only
    # encodes the multipart body while sending, so nothing that inspects the request (WebMock in CI, logging)
    # sees it; encoding it here keeps the body a plain binary string. Everything is concatenated as bytes so a
    # non-ASCII filename and binary file content never meet in one encoding.
    def multipart_body(form, boundary)
      parts = form.map do |name, value, opts|
        head = "Content-Disposition: form-data; name=\"#{name}\""

        if opts
          content_type = opts[:content_type] || 'application/octet-stream'
          head += "; filename=\"#{opts[:filename]}\"\r\nContent-Type: #{content_type}"
          value.rewind if value.respond_to?(:rewind)
          content = value.respond_to?(:read) ? value.read : value.to_s
        else
          content = value.to_s
        end

        "--#{boundary}\r\n#{head}\r\n\r\n".b + content.to_s.b + "\r\n".b
      end

      parts.join + "--#{boundary}--\r\n".b
    end
  end
end
