namespace :app do
  help_app_register =  <<~EOL
    Register an App for IM authentication.
    Usage:
        rails app:register name="my-app-name" url="https://domain.local"

    Optional switches:
        mailer_from="info@domain.local"         (defaults to info@[domain])
        mailer_reply_to="no-reply@domain.local" (defaults to no-reply@[domain])
        update=yes
        RAILS_ENV=live
  EOL

  help_app_admin =  <<~EOL
    Set an User as App-Admin.
    Usage:
        rails app:admin name="my-app-name" email="account@domain.local"
    Optional switches:
        RAILS_ENV=live
  EOL

  desc help_app_register

  task :register => :environment do |task, args|
    Actor.logs! false # silence

    puts "=" * 80
    puts help_app_register
    puts "=" * 80

    abort 'Please define a URL like url="https://domain.local"' unless ENV['url'].present?
    abort 'Please define an app name like name="my-app-name"' unless ENV['name'].present?

    puts "For environment: #{Rails.env} - register url: #{ENV['url']}"

    app = Actors::App.available.named(ENV['name']).first_or_initialize(short_name: ENV['name'])
    if app.persisted? && !ENV['update'].eql?('yes')
      abort "An app name #{ENV['name']} already exists. Please choose a different name or set update=yes"
    end

    if ENV['mailer_from'].present?
      app.actor_settings[:mailer] ||= {}
      app.actor_settings[:mailer][:from] = ENV['mailer_from']
    end
    if ENV['mailer_reply_to'].present?
      app.actor_settings[:mailer] ||= {}
      app.actor_settings[:mailer][:reply_to] = ENV['mailer_reply_to']
    end
    app.config.url = ENV['url']
    app.save!

    if app.errors.any?
      abort "Some error happened trying to save your app!"
    end

    Actors::Group.where(parent: app, short_name: 'users').first_or_create(system: true)
    app.save!
    app.create_app_view!

    puts "=" * 80
    puts "App registered successfully."
    puts "=" * 80

  end

  desc help_app_admin

  task :admin => :environment do |task, args|
    Actor.logs! false # silence

    puts "=" * 80
    puts help_app_admin
    puts "=" * 80

    abort 'Please define an app name like name="my-app-name"' unless ENV['name'].present?
    abort 'Please define an email like email="account@domain.local"' unless ENV['email'].present?

    puts "For environment: #{Rails.env} - adding: #{ENV['email']} to app administrators of #{ENV['name']}"

    app = Actors::App.available.named(ENV['name']).first

    unless app.present?
      abort "An app named #{ENV['name']} could not be found. Please check the name."
    end
    unless app.admins.present?
      abort "The app-admin group for #{ENV['name']} could not be found."
    end

    if ENV['email'].present?
      user = User.available.email(ENV['email'])
      unless app.admins.map_into!(user)
        abort "Failed to add the user."
      end
    end

    puts "=" * 80
    puts "App-Admin added successfully."
    puts "=" * 80

  end

end