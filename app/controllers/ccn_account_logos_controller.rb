# frozen_string_literal: true

# CCN fork — Stage 4, US2 (specs/003-p1-features): Settings → Personalization → Company logo. The API twin is
# Api::CcnAccountLogoController; both attach through Ccn::AccountLogo's validation, this one reporting a
# refusal as the flash alert the rest of the settings pages use.
class CcnAccountLogosController < ApplicationController
  before_action { authorize!(:manage, current_account) }

  def create
    file = params[:file]

    return redirect_with(alert: I18n.t('ccn_logo_file_required')) if file.blank?

    current_account.logo.attach(file)

    if current_account.errors.any?
      redirect_with(alert: current_account.errors.full_messages.to_sentence)
    else
      redirect_with(notice: I18n.t('settings_have_been_saved'))
    end
  end

  def destroy
    current_account.logo.purge

    redirect_with(notice: I18n.t('settings_have_been_saved'))
  end

  private

  def redirect_with(**flash)
    redirect_back(fallback_location: settings_personalization_path, **flash)
  end
end
