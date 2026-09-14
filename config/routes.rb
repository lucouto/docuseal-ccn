# frozen_string_literal: true

Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: '/letter_opener' if Rails.env.development?

  if !Docuseal.multitenant? && defined?(Sidekiq::Web)
    authenticated :user, ->(u) { u.sidekiq? } do
      mount Sidekiq::Web => '/jobs'
    end
  end

  root 'dashboard#index'

  get 'up' => 'rails/health#show'
  get 'manifest' => 'pwa#manifest'

  devise_for :users, path: '/', only: %i[sessions passwords],
                     controllers: { sessions: 'sessions', passwords: 'passwords' }

  devise_scope :user do
    resource :invitation, only: %i[update] do
      get '' => :edit
    end
  end

  namespace :api, defaults: { format: :json } do
    resource :user, only: %i[show]
    resources :attachments, only: %i[create]
    resources :submitter_email_clicks, only: %i[create]
    resources :submitter_form_views, only: %i[create]
    resources :submitters, only: %i[index show update]
    # CCN fork: submissions from documents, upstream Pro (specs/001-documents-by-any-route, FR-007/FR-013).
    post 'submissions/pdf', to: 'ccn_submissions_documents#pdf'
    post 'submissions/docx', to: 'ccn_submissions_documents#docx'
    post 'submissions/html', to: 'ccn_submissions_documents#html'
    resources :submissions, only: %i[index show create update destroy] do
      resources :documents, only: %i[index], controller: 'submission_documents'
      collection do
        resources :init, only: %i[create], controller: 'submissions'
        resources :emails, only: %i[create], controller: 'submissions', as: :submissions_emails
      end
    end
    # CCN fork: template ingestion upstream reserves for Pro (specs/001-documents-by-any-route, FR-007).
    post 'templates/pdf', to: 'ccn_templates_documents#pdf'
    post 'templates/docx', to: 'ccn_templates_documents#docx'
    post 'templates/doc', to: 'ccn_templates_documents#docx'
    post 'templates/html', to: 'ccn_templates_documents#html'
    post 'templates/merge', to: 'ccn_templates_documents#merge'
    put 'templates/:id/documents', to: 'ccn_templates_documents#update'
    resources :templates, only: %i[update show index destroy] do
      resources :clone, only: %i[create], controller: 'templates_clone'
      resources :submissions, only: %i[index create]
    end
    # CCN fork: administration by API (specs/002-everything-by-api, FR-001..FR-007). Flat controller names;
    # `as:` keeps the helpers clear of upstream's `api_user`.
    scope 'ccn' do
      resources :users, only: %i[index create show update destroy], controller: 'ccn_users', as: 'ccn_users' do
        post :reset_password, on: :member
      end
      resources :webhooks, only: %i[index create show update destroy], controller: 'ccn_webhooks',
                           as: 'ccn_webhooks' do
        member do
          get :secret
          get :events
          post :test
          post 'events/:uuid/resend', action: :resend, as: :resend_event
        end
      end
      resources :account_configs, only: %i[index show update destroy], controller: 'ccn_account_configs',
                                  as: 'ccn_account_configs', param: :key
      resources :template_folders, only: %i[index create update destroy], controller: 'ccn_template_folders',
                                   as: 'ccn_template_folders'
      scope 'templates/:template_id', as: 'ccn_template' do
        resources :versions, only: %i[index create show], controller: 'ccn_template_versions' do
          post :restore, on: :member
        end
        post 'detect_fields', to: 'ccn_template_detect_fields#create'
      end
    end
    resources :tools, only: %i[] do
      post :merge, on: :collection
      post :verify, on: :collection
    end
    scope 'events' do
      resources :form_events, only: %i[index], path: 'form/:type'
      resources :submission_events, only: %i[index], path: 'submission/:type'
    end
  end

  resources :verify_pdf_signature, only: %i[create]
  resource :mfa_setup, only: %i[show new edit create destroy], controller: 'mfa_setup'
  resources :account_configs, only: %i[create destroy]
  resources :account_custom_fields, only: %i[create]
  resources :user_configs, only: %i[create]
  resources :encrypted_user_configs, only: %i[destroy]
  resources :timestamp_server, only: %i[create] unless Docuseal.multitenant?
  resources :dashboard, only: %i[index]
  resources :setup, only: %i[index create]
  resource :newsletter, only: %i[show update]
  resources :enquiries, only: %i[create]
  resources :users, only: %i[new create edit update destroy] do
    resource :send_reset_password, only: %i[update], controller: 'users_send_reset_password'
  end
  resource :user_signature, only: %i[edit update destroy]
  resource :user_initials, only: %i[edit update destroy]
  resources :submissions_archived, only: %i[index], path: 'submissions/archived'
  resources :submissions, only: %i[index], controller: 'submissions_dashboard'
  resources :submissions, only: %i[show destroy] do
    resources :unarchive, only: %i[create], controller: 'submissions_unarchive'
    resources :events, only: %i[index], controller: 'submission_events'
    resources :download, only: %i[index], controller: 'submissions_download'
    resources :resend_email, only: %i[create], controller: 'submissions_resend_email'
  end
  resources :submitters, only: %i[edit update]
  resources :console_redirect, only: %i[index]
  resources :upgrade, only: %i[index], controller: 'console_redirect'
  resources :manage, only: %i[index], controller: 'console_redirect'
  resource :testing_account, only: %i[create destroy]
  resources :testing_api_settings, only: %i[index]
  resources :submitters_autocomplete, only: %i[index]
  resources :submitters_resubmit, only: %i[update]
  resources :template_folders_autocomplete, only: %i[index]
  resources :webhook_secret, only: %i[show update]
  resources :webhook_hmac, only: %i[show]
  resources :webhook_preferences, only: %i[update]
  resource :templates_upload, only: %i[create]
  authenticated do
    resource :templates_upload, only: %i[show], path: 'new'
  end
  resources :templates_archived, only: %i[index], path: 'templates/archived'
  resources :templates_shared, only: %i[index], path: 'templates/shared'
  resources :folders, only: %i[show edit update destroy], controller: 'template_folders'
  resources :template_sharings_testing, only: %i[create]
  resources :templates, only: %i[index], controller: 'templates_dashboard'
  resources :submissions_filters, only: %i[show], param: 'name'
  resources :templates, only: %i[new create edit update show destroy] do
    resources :clone, only: %i[new create], controller: 'templates_clone'
    resource :debug, only: %i[show], controller: 'templates_debug' if Rails.env.development?
    resources :documents, only: %i[index create], controller: 'template_documents'
    resources :documents_modify, only: %i[create], controller: 'template_documents_modify'
    resources :documents_page_objects, only: %i[index], controller: 'template_documents_page_objects'
    resources :documents_crop, only: %i[index create], controller: 'template_documents_crop'
    resources :clone_and_replace, only: %i[create], controller: 'templates_clone_and_replace'
    resources :detect_fields, only: %i[create], controller: 'templates_detect_fields' unless Docuseal.multitenant?
    resources :restore, only: %i[create], controller: 'templates_restore'
    resources :archived, only: %i[index], controller: 'templates_archived_submissions'
    resources :submissions, only: %i[new create]
    resource :folder, only: %i[edit update], controller: 'templates_folders'
    resource :preview, only: %i[show], controller: 'templates_preview'
    resource :form, only: %i[show], controller: 'templates_form_preview'
    resource :code_modal, only: %i[show], controller: 'templates_code_modal'
    resource :preferences, only: %i[show create destroy], controller: 'templates_preferences'
    resources :versions, only: %i[index show create], controller: 'templates_versions'
    resource :share_link, only: %i[show create], controller: 'templates_share_link'
    resource :share_link_qr, only: %i[show], controller: 'templates_share_link_qr'
    resources :recipients, only: %i[create], controller: 'templates_recipients'
    resources :prefillable_fields, only: %i[create], controller: 'templates_prefillable_fields'
    resources :submissions_export, only: %i[index new]
  end
  resources :preview_document_page, only: %i[show], path: '/preview/:signed_key'
  resource :blobs_proxy, only: %i[show], path: '/file/:signed_uuid/*filename',
                         controller: 'api/active_storage_blobs_proxy'
  resource :blobs_proxy, only: %i[show], path: '/blobs_proxy/:signed_uuid/*filename',
                         controller: 'api/active_storage_blobs_proxy'

  if Docuseal.multitenant?
    resource :blobs_proxy_legacy, only: %i[show],
                                  path: '/blobs/proxy/:signed_id/*filename',
                                  controller: 'api/active_storage_blobs_proxy_legacy',
                                  as: :rails_blob
    get '/disk/:encoded_key/*filename' => 'active_storage/disk#show', as: :rails_disk_service
    put '/disk/:encoded_token' => 'active_storage/disk#update', as: :update_rails_disk_service
    post '/direct_uploads' => 'active_storage/direct_uploads#create', as: :rails_direct_uploads

    ActiveSupport.run_load_hooks(:multitenant_routes, self)
  end

  resources :start_form, only: %i[show update], path: 'd', param: 'slug' do
    get :completed
  end

  resource :resubmit_form, controller: 'start_form_resubmit', only: :update
  resources :start_form_self, only: :update
  resource :submit_form_email_2fa, only: %i[create update]
  resources :start_form_email_2fa_send, only: :create

  resources :submit_form, only: %i[], path: '' do
    get :success, on: :collection
  end

  resources :submit_form, only: %i[show update], path: 's', param: 'slug' do
    resources :values, only: %i[index], controller: 'submit_form_values'
    resources :download, only: %i[index], controller: 'submit_form_download'
    resources :documents, only: %i[index], controller: 'submit_form_completed_download'
    resources :decline, only: %i[create], controller: 'submit_form_decline'
    resources :delegate, only: %i[create], controller: 'submit_form_delegate'
    resources :invite, only: %i[create], controller: 'submit_form_invite'
    resources :metadata, only: %i[index], controller: 'submit_form_metadata'
    resources :debug, only: %i[index], controller: 'submissions_debug' if Rails.env.development?
    get :completed
    get :delegated
  end

  resources :submit_form_draw_signature, only: %i[show], path: 'p', param: 'slug'

  resources :submissions_preview, only: %i[show], path: 'e', param: 'slug' do
    get :completed
    resources :download, only: %i[index], controller: 'submissions_preview_download'
  end

  resources :send_submission_email, only: %i[create]

  resources :submitters, only: %i[] do
    resources :download, only: %i[index], controller: 'submitters_download', constraints: { submitter_id: /\d+/ }
    resources :send_email, only: %i[create], controller: 'submitters_send_email'
  end

  resources :submitters, only: %i[], param: 'slug' do
    resources :download, only: %i[index], controller: 'submit_form_completed_download'
  end

  resources :settings, only: %i[index]

  scope '/settings', as: :settings do
    unless Docuseal.multitenant?
      resources :storage, only: %i[index create], controller: 'storage_settings'
      resources :search_entries_reindex, only: %i[create]
      resources :sms, only: %i[index], controller: 'sms_settings'
      resources :mcp, only: %i[index new create destroy], controller: 'mcp_settings'
    end
    if Docuseal.demo? || !Docuseal.multitenant?
      resources :api, only: %i[index create], controller: 'api_settings'
      resource :reveal_access_token, only: %i[show create], controller: 'reveal_access_token'
    end
    resources :email, only: %i[index create destroy], controller: 'email_smtp_settings'
    resources :sso, only: %i[index], controller: 'sso_settings'
    resources :notifications, only: %i[index create], controller: 'notifications_settings'
    resource :esign, only: %i[show create new update destroy], controller: 'esign_settings'
    resources :users, only: %i[index]
    resources :archived_users, only: %i[index], path: 'users/:status', controller: 'users',
                               defaults: { status: :archived }
    resources :integration_users, only: %i[index], path: 'users/:status', controller: 'users',
                                  defaults: { status: :integration }
    resource :personalization, only: %i[show create], controller: 'personalization_settings'
    resources :webhooks, only: %i[index show new create update destroy], controller: 'webhook_settings' do
      post :resend

      resources :events, only: %i[show], controller: 'webhook_events' do
        post :resend, on: :member
        post :refresh, on: :member
      end
    end
    resource :account, only: %i[show update destroy]
    resources :profile, only: %i[index] do
      collection do
        patch :update_contact
        patch :update_password
        patch :update_app_url
      end
    end
  end

  match '/mcp', to: 'mcp#call', via: %i[get post]

  get '/js/:filename', to: 'embed_scripts#show', as: :embed_script

  ActiveSupport.run_load_hooks(:routes, self)
end
