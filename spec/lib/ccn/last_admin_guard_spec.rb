# frozen_string_literal: true

# CCN fork — Stage 4, US3 (specs/003-p1-features, research D10): an account cannot be left without an
# administrator, whichever path tries it.
describe Ccn::LastAdminGuard do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account:) }

  def message_of(user)
    user.errors.full_messages
  end

  context 'when this is the account\'s only active administrator' do
    it 'refuses a role change away from admin' do
      expect(admin.update(role: 'editor')).to be(false)
      expect(message_of(admin)).to eq(['At least one administrator must remain on the account'])
      expect(admin.reload.role).to eq('admin')
    end

    it 'refuses being archived' do
      expect(admin.update(archived_at: Time.current)).to be(false)
      expect(admin.reload.archived_at).to be_nil
    end

    it 'refuses being moved to another account' do
      expect(admin.update(account: create(:account))).to be(false)
      expect(admin.reload.account_id).to eq(account.id)
    end

    it 'allows a change that keeps them an active administrator' do
      expect(admin.update(first_name: 'Luciano')).to be(true)
    end

    it 'does not count an editor as an administrator' do
      create(:user, account:, role: 'editor')

      expect(admin.update(role: 'viewer')).to be(false)
    end

    it 'does not count an archived administrator' do
      create(:user, account:, archived_at: Time.current)

      expect(admin.update(role: 'editor')).to be(false)
    end

    # The automation account never signs in interactively: counting it would lock every human out.
    it 'does not count an integration user' do
      create(:user, account:, role: 'integration')

      expect(admin.update(archived_at: Time.current)).to be(false)
    end

    it 'does not count an administrator of another account' do
      create(:user, account: create(:account))

      expect(admin.update(role: 'editor')).to be(false)
    end
  end

  context 'when another active administrator remains' do
    let!(:second_admin) { create(:user, account:) }

    it 'allows a demotion' do
      expect(admin.update(role: 'editor')).to be(true)
    end

    it 'allows an archive' do
      expect(admin.update(archived_at: Time.current)).to be(true)
    end

    it 'refuses the demotion of the one left afterwards' do
      admin.update!(role: 'viewer')

      expect(second_admin.update(role: 'viewer')).to be(false)
    end
  end

  it 'never applies to a user being created' do
    expect(build(:user, account:, role: 'viewer')).to be_valid
  end

  it 'leaves an editor free to change' do
    editor = create(:user, account:, role: 'editor')

    expect(editor.update(role: 'viewer')).to be(true)
    expect(editor.update(archived_at: Time.current)).to be(true)
  end

  it 'translates the refusal' do
    I18n.with_locale(:fr) { admin.update(role: 'editor') }

    expect(message_of(admin)).to eq(['Il doit rester au moins un administrateur sur le compte'])
  end
end
