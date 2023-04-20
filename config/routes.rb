Rails.application.routes.draw do

  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'

  devise_for :users, only: [], skip: [:sessions]

  scope module: :api, path: :api do
    draw :v1_devise
    draw :v1
  end

  # Sentry tunneling
  post '/api/error-reporting' => 'api/sentry#tunnel'

  # Health Check ALB
  get '/health' => 'application#health'

end
