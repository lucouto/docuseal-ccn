# frozen_string_literal: true

module Api
  # CCN fork — /api/ccn/users (specs/002-everything-by-api, US1). Thin over Ccn::ManageUsers, which holds the
  # UI's rules; authorization is explicit (CanCan's resource loading would read the controller name).
  class CcnUsersController < ApiBaseController
    include Ccn::AdminErrors

    before_action { authorize!(:manage, User) }
    before_action :load_user, only: %i[show update destroy reset_password]

    def index
      users = paginate(Ccn::ManageUsers.list(current_account, status: params[:status]))

      render json: {
        data: users.map { |user| Ccn::ManageUsers.serialize(user) },
        pagination: { count: users.size, next: users.last&.id, prev: users.first&.id }
      }
    end

    def show
      render json: Ccn::ManageUsers.serialize(@user)
    end

    def create
      render json: Ccn::ManageUsers.invite(current_account, current_user, user_attrs, send_email: send_email?)
    end

    def update
      render json: Ccn::ManageUsers.update(@user, current_user, user_attrs)
    end

    def destroy
      render json: Ccn::ManageUsers.archive(@user, current_user)
    end

    def reset_password
      render json: Ccn::ManageUsers.send_reset_password(@user)
    end

    private

    def load_user
      @user = current_account.users.find(params[:id])

      authorize!(:manage, @user)
    end

    # Attributes at the top level (the API's style) or wrapped in `user` (the UI's form style).
    def user_attrs
      (params[:user].presence || params).to_unsafe_h
    end

    def send_email?
      !params.key?(:send_email) || Ccn::DocumentParams.boolean(params[:send_email])
    end
  end
end
