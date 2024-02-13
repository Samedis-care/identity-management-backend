namespace :v1 do

  class DomainConstraint
    def self.matches?(request)
      provider = request.params[:provider]
      CustomAuthProvider.exists?(domain: provider)
    end
  end

  devise_for :users, skip: [:confirmations, :passwords, :sessions, :registration], controllers: {
    omniauth_callbacks: "api/v1/devise/omniauth_callbacks"
  }, noswagger: true

  constraints(DomainConstraint) do
    constraints(provider: /[^\/]+/) do
      devise_scope :user do
        get '/users/auth/:provider/callback', to: 'devise/omniauth_callbacks#dynamic_provider_callback', as: :user_custom_omniauth_callback

        # test for having bookmarkable URL to start a custom oauth2 login
        get '/users/auth/:provider/:app', to: 'devise/omniauth_callbacks#dynamic_provider_authorize', as: :user_custom_omniauth_authorize_app_get
        post '/users/auth/:provider/:app', to: 'devise/omniauth_callbacks#dynamic_provider_authorize', as: :user_custom_omniauth_authorize_app

        get '/users/auth/:provider', to: 'devise/omniauth_callbacks#dynamic_provider_authorize', as: :user_custom_omniauth_authorize_get
        post '/users/auth/:provider', to: 'devise/omniauth_callbacks#dynamic_provider_authorize', as: :user_custom_omniauth_authorize
      end
    end
  end

  post '*app/users/auth/:oauth', to: redirect { |path, req|
    "/api/v1/users/auth/#{path[:oauth]}?#{ { app: path[:app] }.to_param }"
  }

  devise_scope :user do
    post "/register" => "devise/registrations#create"
    post "/users/confirmation" => "devise/confirmations#create", as: :user_confirmation
  end

  devise_scope :user do
    scope path: '*app' do
      post "/register" => "devise/registrations#create"
      post "/users/password" => "devise/passwords#create"
      put "/users/password" => "devise/passwords#update"
      get "/users/confirmation/:confirmation_token" => "devise/confirmations#show"
      post "/users/confirmation" => "devise/confirmations#create", as: :app_user_confirmation
    end
  end

  # use_doorkeeper do
  #   controllers :tokens => "doorkeeper/tokens", only: [:revoke]
  #   controllers :token_info => "doorkeeper/token_info", only: [:show]
  #   skip_controllers :applications, :authorized_applications, :authorizations
  # end

  # scope path: '*app' do
  #   use_doorkeeper do
  #     controllers :tokens => "doorkeeper/tokens", only: [:token]
  #     skip_controllers :token_info, :applications, :authorized_applications, :authorizations
  #   end
  # end

  scope :oauth do
    scope module: :doorkeeper do
      post :revoke, controller: :tokens, swagger: :tokens_revoke
      # scope :token do
      #   get :info, controller: :token_info
      # end
    end
  end

  scope path: '*app', module: :app do
    scope :oauth do
      scope module: :doorkeeper do
        resource :token, only: [:create]
        scope :token do
          get :info, controller: :token_info, action: :show
        end
      end
    end
  end

end
