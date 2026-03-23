Rails.application.routes.draw do

  get '/api-docs' => 'openapi_specs#show', defaults: { version: 'v1', spec: 'public' }
  get '/api-docs/:version/:spec' => 'openapi_specs#show'
  get '/api-docs/:version/:spec/index.html' => 'openapi_specs#show'

  devise_for :users, only: [], controllers: {
    unlocks: 'api/v1/app/unlocks',
    omniauth_callbacks: 'api/v1/devise/omniauth_callbacks'
  }

  scope module: :api, path: :api do
    draw :admin
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
