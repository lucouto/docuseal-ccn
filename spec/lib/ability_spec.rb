# frozen_string_literal: true

require 'cancan/matchers'

# CCN fork — Stage 4, US3 (specs/003-p1-features, research D9, SC-004): what each account role may do. Every
# screen and every /api/ccn/... controller authorizes through these rules, so this matrix is what decides the
# 200/403 of the request spec next door (spec/requests/ccn_roles_spec.rb).
describe Ability do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:, role:) }
  let(:ability) { described_class.new(user) }
  let(:colleague) { create(:user, account:) }
  let(:template) { Template.new(account:) }
  let(:folder) { TemplateFolder.new(account:) }
  let(:submission) { Submission.new(account:) }
  let(:submitter) { Submitter.new(account:) }
  let(:account_config) { AccountConfig.new(account:) }
  let(:webhook) { WebhookUrl.new(account:) }
  let(:smtp_config) { EncryptedConfig.new(account:) }

  shared_examples 'their own profile and tokens' do
    it 'manages their own profile, signature, API token and MCP token' do
      expect(ability).to be_able_to(:manage, user)
      expect(ability).to be_able_to(:manage, UserConfig.new(user:))
      expect(ability).to be_able_to(:manage, EncryptedUserConfig.new(user:))
      expect(ability).to be_able_to(:manage, AccessToken.new(user:))
      expect(ability).to be_able_to(:manage, McpToken.new(user:))
      expect(ability).to be_able_to(:manage, :mcp)
    end

    it 'cannot reach another account' do
      other = create(:account)

      expect(ability).not_to be_able_to(:read, Template.new(account: other))
      expect(ability).not_to be_able_to(:read, Submission.new(account: other))
      expect(ability).not_to be_able_to(:manage, other)
    end
  end

  context 'when the user is an administrator' do
    let(:role) { 'admin' }

    it_behaves_like 'their own profile and tokens'

    it 'manages documents and sending' do
      expect(ability).to be_able_to(:create, template)
      expect(ability).to be_able_to(:update, template)
      expect(ability).to be_able_to(:destroy, template)
      expect(ability).to be_able_to(:manage, folder)
      expect(ability).to be_able_to(:manage, submission)
      expect(ability).to be_able_to(:manage, submitter)
    end

    it 'manages the account, its settings, its users and its webhooks' do
      expect(ability).to be_able_to(:manage, account)
      expect(ability).to be_able_to(:manage, account_config)
      expect(ability).to be_able_to(:manage, webhook)
      expect(ability).to be_able_to(:manage, smtp_config)
      expect(ability).to be_able_to(:manage, colleague)
      expect(ability).to be_able_to(:create, User.new(account:))
    end
  end

  context 'when the user is an editor' do
    let(:role) { 'editor' }

    it_behaves_like 'their own profile and tokens'

    it 'manages documents and sending, as an administrator does' do
      expect(ability).to be_able_to(:read, template)
      expect(ability).to be_able_to(:create, template)
      expect(ability).to be_able_to(:update, template)
      expect(ability).to be_able_to(:destroy, template)
      expect(ability).to be_able_to(:manage, folder)
      expect(ability).to be_able_to(:manage, submission)
      expect(ability).to be_able_to(:manage, submitter)
    end

    it 'sees the list of users but changes nobody but themselves' do
      expect(ability).to be_able_to(:read, User)
      expect(ability).to be_able_to(:read, colleague)
      expect(ability).not_to be_able_to(:update, colleague)
      expect(ability).not_to be_able_to(:destroy, colleague)
      expect(ability).not_to be_able_to(:create, User.new(account:))
    end

    it 'cannot configure the account' do
      expect(ability).not_to be_able_to(:read, account)
      expect(ability).not_to be_able_to(:update, account)
      expect(ability).not_to be_able_to(:read, account_config)
      expect(ability).not_to be_able_to(:update, account_config)
      expect(ability).not_to be_able_to(:read, webhook)
      expect(ability).not_to be_able_to(:create, webhook)
      expect(ability).not_to be_able_to(:read, smtp_config)
      expect(ability).not_to be_able_to(:update, smtp_config)
    end
  end

  context 'when the user is a viewer' do
    let(:role) { 'viewer' }

    it_behaves_like 'their own profile and tokens'

    it 'reads documents and submissions' do
      expect(ability).to be_able_to(:read, template)
      expect(ability).to be_able_to(:read, folder)
      expect(ability).to be_able_to(:read, submission)
      expect(ability).to be_able_to(:read, submitter)
      expect(ability).to be_able_to(:read, colleague)
    end

    it 'changes nothing' do
      expect(ability).not_to be_able_to(:create, template)
      expect(ability).not_to be_able_to(:update, template)
      expect(ability).not_to be_able_to(:destroy, template)
      expect(ability).not_to be_able_to(:create, folder)
      expect(ability).not_to be_able_to(:update, folder)
      expect(ability).not_to be_able_to(:create, submission)
      expect(ability).not_to be_able_to(:update, submission)
      expect(ability).not_to be_able_to(:destroy, submission)
      expect(ability).not_to be_able_to(:create, submitter)
      expect(ability).not_to be_able_to(:update, submitter)
      expect(ability).not_to be_able_to(:update, colleague)
    end

    it 'cannot configure the account' do
      expect(ability).not_to be_able_to(:read, account)
      expect(ability).not_to be_able_to(:read, account_config)
      expect(ability).not_to be_able_to(:read, webhook)
      expect(ability).not_to be_able_to(:read, smtp_config)
      expect(ability).not_to be_able_to(:create, User.new(account:))
    end
  end

  # The automation account keeps the rules it had before this stage: nothing about it changes when roles land.
  context 'when the user is the integration account' do
    let(:role) { 'integration' }

    it 'is still an administrator in all but name' do
      expect(ability).to be_able_to(:manage, account)
      expect(ability).to be_able_to(:manage, account_config)
      expect(ability).to be_able_to(:manage, colleague)
      expect(ability).to be_able_to(:create, template)
    end
  end
end
