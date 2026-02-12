Rails.application.routes.draw do

  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'

  devise_for :users, only: [], skip: [:sessions]

  scope module: :api, path: :api do
    draw :v1_devise
    draw :v1
  end

  # allows local mail previews in browser (will not work via balancer)
  # http://127.0.0.1:<port>/rails/mailers
  mount ActionMailer::Preview => 'rails/mailers'

  # Sentry tunneling
  post '/api/error-reporting' => 'api/sentry#tunnel'

  # Health Check ALB
  get '/health' => 'application#health'

end
