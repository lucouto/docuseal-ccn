# frozen_string_literal: true

# CCN fork — `documents_copy_email_attach_files`: a template can keep the files a signer uploaded in `file` fields
# (a passport photo) out of that signer's documents-copy e-mail, while the signed PDF and the audit log stay attached.
# The team's completed notification is not affected.
describe SubmitterMailer do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user, only_field_types: %w[text file]) }
  let(:submission) { create(:submission, template:, created_by_user: user, completed_at: Time.current) }
  let(:file_field) { template.fields.find { |f| f['type'] == 'file' } }
  let(:submitter) do
    create(:submitter, submission:, account:, email: 'signer@example.com', completed_at: Time.current,
                       uuid: template.submitters.first['uuid'])
  end

  def attach(record, name, filename, content_type)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("#{filename} data"), filename:, content_type:)

    ActiveStorage::Attachment.create!(blob:, name:, record:)
  end

  before do
    photo = attach(submitter, :attachments, 'passport.jpg', 'image/jpeg')
    submitter.update!(values: { file_field['uuid'] => [photo.uuid] })

    attach(submitter, :documents, 'signed.pdf', 'application/pdf')
    attach(submission, :audit_trail, 'audit.pdf', 'application/pdf')

    # The result is already generated: EnsureResultGenerated returns the submitter's documents as they are.
    LockEvent.create!(key: "result_attachments:#{submitter.id}", event_name: :complete)
  end

  def filenames(mail)
    mail.attachments.map(&:filename)
  end

  it 'attaches the signed PDF, the audit log and the uploaded file when the preference is absent' do
    expect(filenames(described_class.documents_copy_email(submitter)))
      .to contain_exactly('signed.pdf', 'audit.pdf', 'passport.jpg')
  end

  it 'leaves the uploaded file out when documents_copy_email_attach_files is false' do
    template.update!(preferences: { 'documents_copy_email_attach_files' => false })

    expect(filenames(described_class.documents_copy_email(submitter))).to contain_exactly('signed.pdf', 'audit.pdf')
  end

  it 'still attaches the uploaded file to the completed notification' do
    template.update!(preferences: { 'documents_copy_email_attach_files' => false })

    expect(filenames(described_class.completed_email(submitter, user)))
      .to contain_exactly('signed.pdf', 'audit.pdf', 'passport.jpg')
  end
end
