# frozen_string_literal: true

class Ability
  include CanCan::Ability

  # CCN fork — Stage 4, US3 (specs/003-p1-features, research D9): the account roles. Every screen and every
  # /api/ccn/... controller already asks `can?`/`authorize!`, so an editor's and a viewer's limits are
  # expressed once, here, and no controller had to learn about roles.
  def initialize(user)
    case user.role
    when User::EDITOR_ROLE then editor_rules(user)
    when User::VIEWER_ROLE then viewer_rules(user)
    else admin_rules(user) # 'admin', and the ad-hoc 'integration'/'superadmin': upstream's rules, unchanged
    end
  end

  private

  def admin_rules(user)
    can %i[read create update], Template, Abilities::TemplateConditions.collection(user) do |template|
      Abilities::TemplateConditions.entity(template, user:, ability: 'manage')
    end

    can :destroy, Template, account_id: user.account_id
    can :manage, TemplateFolder, account_id: user.account_id
    can :manage, TemplateSharing, template: { account_id: user.account_id }
    can :manage, Submission, account_id: user.account_id
    can :manage, Submitter, account_id: user.account_id
    can :manage, User, account_id: user.account_id
    can :manage, EncryptedConfig, account_id: user.account_id
    can :manage, AccountConfig, account_id: user.account_id
    can :manage, Account, id: user.account_id
    can :manage, WebhookUrl, account_id: user.account_id

    own_records_rules(user)
  end

  # Documents and sending: everything needed to prepare a template, send it and follow the signatures, and
  # nothing that configures the account — settings, personalization, users, webhooks, e-signature, SMTP,
  # storage and the /api/ccn administration endpoints all refuse them through their own authorize! calls.
  def editor_rules(user)
    can %i[read create update], Template, Abilities::TemplateConditions.collection(user) do |template|
      Abilities::TemplateConditions.entity(template, user:, ability: 'manage')
    end

    can :destroy, Template, account_id: user.account_id
    can :manage, TemplateFolder, account_id: user.account_id
    can :manage, Submission, account_id: user.account_id
    can :manage, Submitter, account_id: user.account_id
    can :read, User, account_id: user.account_id

    own_records_rules(user)
  end

  # Read-only: open templates and submissions, download signed documents, change nothing anywhere.
  def viewer_rules(user)
    can :read, Template, Abilities::TemplateConditions.collection(user) do |template|
      Abilities::TemplateConditions.entity(template, user:, ability: 'read')
    end

    can :read, TemplateFolder, account_id: user.account_id
    can :read, Submission, account_id: user.account_id
    can :read, Submitter, account_id: user.account_id
    can :read, User, account_id: user.account_id

    own_records_rules(user)
  end

  # Their own profile, signature, API token and MCP token, whatever their role — ProfileController asks for
  # `manage` on the user themselves, which is also why this rule is scoped to their own id and no wider.
  def own_records_rules(user)
    can :manage, User, id: user.id
    can :manage, EncryptedUserConfig, user_id: user.id
    can :manage, UserConfig, user_id: user.id
    can :manage, AccessToken, user_id: user.id
    can :manage, McpToken, user_id: user.id

    can :manage, :mcp
  end
end
