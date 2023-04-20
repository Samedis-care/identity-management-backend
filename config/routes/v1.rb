namespace :v1 do

  namespace :access_control do
    scope module: :app, path: 'app/:name' do
      resources :groups, only: [:index]
    end
    resources :apps, module: :apps, only: [] do
      resources :groups, only: [:index]
    end
    resources :tenant, module: :tenant, only: [] do
      resources :groups, only: [:index]
      resources :users, only: [:index, :show, :update, :destroy]
    end
  end

  resources :users
  resources :email_blacklist
  resources :app_admin

  resources :apps, module: :apps, only: []  do
    namespace :picker do
      resources :roles, only: [] do
        resources :user_organization, module: :roles, only: [:index, :show]
        resources :functionalities, module: :roles, only: [:index, :show]
      end
      resources :functionalities, only: [] do
        resources :roles, module: :functionalities, only: [:index, :show]
      end
      resources :users, only: [] do
        resources :groups, module: :users, only: [:index, :show]
      end
      resources :user_organization, only: [:index]
    end
    resources :groups, only: [:index, :show]
    resources :functionalities
    resources :functionalities, module: :functionalities, path: :functionalities do
      resources :roles, only: %i(index show create destroy)
    end
    resources :roles
    resources :roles, module: :roles, path: :roles do
      resources :actors, only: [:index, :show]
      resources :actor_roles, only: [:index, :show, :create, :destroy]
      resources :functionalities, only: %i(index show create destroy)
    end
    resources :users, only: [:index, :show, :update, :destroy] do
      resources :functionalities, module: :users, only: [:index, :show]
      resources :roles, module: :users, only: [:index, :show]
      resources :actors, module: :users, only: [:index, :show, :create, :destroy]
      resources :tenants, module: :users, only: [:index, :show]
    end
    resources :organizations
    resources :organizations_tree, only: [:index, :show]
    resources :organizations, module: :organizations, path: 'organizations' do
      resources :actor_roles, only: [:index, :show, :create, :destroy]
    end
    resources :contents
    resources :tenants
    resources :tenants, module: :tenants, only: [] do
      resources :organizations
      resources :organizations_tree, only: [:index, :show]
      resources :organizations, module: :organizations, only: [] do
        resources :actor_roles, only: [:index, :show, :create, :destroy]
        resources :mappable_users, only: [:index], module: :picker, path: 'picker/mappable_users'
        resources :mappings, only: [:index, :show, :create, :destroy]
      end
      resources :users, only: [:index, :show, :update] do
        resources :functionalities, module: :users, only: [:index, :show]
        resources :roles, module: :users, only: [:index, :show]
        resources :actors, module: :users, only: [:index, :show, :create, :destroy]
        #resources :tenants, module: :users, only: [:index, :show]
      end
      namespace :picker do
        resources :user_organization, only: [:index]
        resources :mappable_users, only: [:index]
        resources :users, only: [] do
          resources :groups, module: :users, only: [:index, :show], as: :v1_apps_tenants_picker_users_groups
        end
      end
    end
  end

  namespace :picker do
    resources :actors, only: [:index] do
      resources :mappings, only: [:index, :show]
    end
    resources :tenant, only: [] do
      resources :users, only: [:index, :show, :update], controller: :tenant_users
    end
  end

  namespace :app do
    resource :logo, path: 'logo/:name', only: :show, noswagger: true
    resource :info, path: 'info/:name', only: :show
  end

  scope module: :app, path: '*app' do
    # resource :user, only: [:index, :update, :destroy]
    get 'user' => 'user#index'
    put 'user' => 'user#update'
    delete 'user' => 'user#destroy'

    resources :content_acceptance, param: :name, only: [:show]
    resources :content_acceptance, only: [:update]

    resources :tenant, module: :tenant, only: [] do
      resources :invitations, only: [:create, :update, :destroy], constraints: { id: /[a-z0-9\{\}]*/ }
    end
  end

  namespace :user do
    resources :apps, only: [:index]
    resources :account_activity, only: [:index]
    resources :account_logins, only: [:index, :destroy]
    resources :quits, only: [:destroy]
    resources :authenticate_otp, only: [:create]
    resources :tenants, path: :tenant, only: [:index, :create, :show, :update, :destroy]
  end

  # Maintenance checks
  get 'server_under_maintenance' => "general#server_under_maintenance", noswagger: true
  get 'maintenance' => 'general#maintenance', noswagger: true

end
