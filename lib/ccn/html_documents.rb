# frozen_string_literal: true

module Ccn
  # HTML in (FR-012): every HTML body (top-level `html`, then `documents[].html`) gets its field elements
  # rewritten into text-tag markers (Ccn::HtmlFieldTags), is rendered by Gotenberg's Chromium route on the
  # requested page size and comes back as a PDF UploadedFile — from there it is a tagged PDF like any other.
  module HtmlDocuments
    module_function

    # @param documents [Array, nil] documents[] to use instead of params[:documents] (already ordered)
    # @return [Array<ActionDispatch::Http::UploadedFile>]
    def files_from(params, documents: nil)
      documents ||= Array.wrap(params[:documents])
      sources = documents.map { |document| Ccn::DocumentParams.indifferent(document) }

      if params[:html].present?
        sources.unshift({ 'html' => params[:html], 'name' => params[:name] }.with_indifferent_access)
      end

      raise Ccn::DocumentParams::Invalid, 'html (or documents[].html) is required' if sources.empty?

      size = page_size(params[:size])

      sources.each_with_index.map do |source, index|
        raise Ccn::DocumentParams::Invalid, "documents[#{index}][html] is required" if source[:html].blank?

        render(source[:html], name: source[:name].presence || "document-#{index + 1}",
                              header: params[:html_header], footer: params[:html_footer], size:)
      end
    end

    # One HTML body → PDF UploadedFile named "<name>.pdf".
    def render(html, name:, header: nil, footer: nil, size: Ccn::DEFAULT_PAGE_SIZE)
      pdf = Ccn::Gotenberg.html_to_pdf(Ccn::HtmlFieldTags.call(html.to_s),
                                       header: header.presence, footer: footer.presence, size:)

      Ccn::DocumentParams.build_uploaded_file(pdf, "#{name}.pdf")
    end

    # A Ccn::PAGE_SIZES key; blank → the instance default (Letter unless CCN_DEFAULT_PAGE_SIZE says otherwise).
    def page_size(value)
      size = value.presence || Ccn::DEFAULT_PAGE_SIZE

      return size.to_s if Ccn::PAGE_SIZES.key?(size.to_s)

      raise Ccn::DocumentParams::Invalid, "size '#{size}' is not one of #{Ccn::PAGE_SIZES.keys.join(', ')}"
    end
  end
end
