namespace :v1 do
  # begin
  namespace :access_control do
    scope module: :app, path: 'app/:name' do
      resources :groups, only: %i(index)
    end
    resources :apps, module: :apps, only: [] do
      resources :groups, only: %i(index)
      resources :tenant, module: :tenant, only: [] do
        resources :users, only: %i(index show update destroy)
      end
    end
    resources :tenant, module: :tenant, only: [] do
      resources :groups, only: %i(index)
      resources :users, only: %i(index show update destroy)
      resources :profiles
      resources :roles, only: %i(index show)
    end
  end

  resources :users
  resources :email_blacklist
  resources :app_admin

  resources :apps, module: :apps, only: [] do
    namespace :picker do
      resources :roles, only: [] do
        resources :user_organization, module: :roles, only: %i(index show)
        resources :functionalities, module: :roles, only: %i(index show)
      end
      resources :functionalities, only: [] do
        resources :roles, module: :functionalities, only: %i(index show)
      end
      resources :users, only: [] do
        resources :groups, module: :users, only: %i(index show)
      end
      resources :user_organization, only: %i(index)
    end
    resources :groups, only: %i(index show)
    resources :functionalities
    resources :functionalities, module: :functionalities, path: :functionalities do
      resources :roles, only: %i(index show create destroy)
    end
    resources :roles
    resources :roles, module: :roles, path: :roles do
      resources :actors, only: %i(index show)
      resources :actor_roles, only: %i(index show create destroy)
      resources :functionalities, only: %i(index show create destroy)
    end
    resources :users, only: %i(index show update destroy) do
      resources :functionalities, module: :users, only: %i(index show)
      resources :roles, module: :users, only: %i(index show)
      resources :actors, module: :users, only: %i(index show create destroy)
      resources :tenants, module: :users, only: %i(index show)
    end
    resources :organizations
    resources :organizations_tree, only: %i(index show)
    resources :organizations, module: :organizations, path: 'organizations' do
      resources :actor_roles, only: %i(index show create destroy)
    end
    resources :contents
    resources :tenants
    resources :tenants, module: :tenants, only: [] do
      resources :organizations
      resources :organizations_tree, only: %i(index show)
      resources :organizations, module: :organizations, only: [] do
        resources :actor_roles, only: %i(index show create destroy)
        resources :mappable_users, only: %i(index), module: :picker, path: 'picker/mappable_users'
        resources :mappings, only: %i(index show create destroy)
      end
      resources :users, only: %i(index show update) do
        resources :functionalities, module: :users, only: %i(index show)
        resources :roles, module: :users, only: %i(index show)
        resources :actors, module: :users, only: %i(index show create destroy)
      end
      namespace :picker do
        resources :user_organization, only: %i(index)
        resources :mappable_users, only: %i(index)
        resources :users, only: [] do
          resources :groups, module: :users, only: %i(index show), as: :v1_apps_tenants_picker_users_groups
        end
      end
    end
  end

  namespace :picker do
    resources :actors, only: %i(index) do
      resources :mappings, only: %i(index show)
    end
    resources :tenant, only: [] do
      resources :users, only: %i(index show update), controller: :tenant_users
    end
  end

  namespace :app do
    resource :logo, path: 'logo/:name', only: :show, noswagger: true
    resource :info, path: 'info/:name', only: :show
  end

  scope module: :app, path: '*app' do
    get 'user' => 'user#index'
    put 'user' => 'user#update'
    delete 'user' => 'user#destroy'

    resources :content_acceptance, param: :name, only: [:show]
    resources :content_acceptance, only: [:update]

    scope path: ':tenant_id', module: :tenant do
      resources :invitations, only: %i(create update destroy)
    end
  end

  namespace :user do
    resources :apps, only: %i(index)
    resources :account_activity, only: %i(index)
    resources :account_logins, only: %i(index destroy)
    resources :quits, only: %i(destroy)
    resources :authenticate_otp, only: %i(create)
    resources :tenants, path: :tenant, only: %i(index create show update destroy)
    resources :leave_tenant, only: %i(destroy)

    put 'invitations/:id' => 'invitations#update', constraints: { id: /[a-z0-9]*/ }, as: 'invitation_accept', noswagger: true
  end

  # Maintenance checks
  get 'server_under_maintenance' => 'general#server_under_maintenance', noswagger: true
  get 'maintenance' => 'general#maintenance', noswagger: true
  # end
end
