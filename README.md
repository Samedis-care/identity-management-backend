# Identity Management

Identity Management is a custom IAM system that provides authentication and optionally authorization for multiple applications and tenants. It is composed of a React frontend and a Ruby on Rails backend using MongoDB as the database system and Shrine for data storage.

Identity Management is hosted at https://ident.services. The API documentation can be accessed under https://ident.services/api-docs/index.html.

## Authentication

The system supports email and password login with optional two-factor authentication (2FA). It also allows OAuth login from Facebook, Google, Microsoft, Apple, and Twitter. Each OAuth login can be enabled optionally.

When registering with email and password, users will be presented with a Google Recaptcha v2 if configured.

Users create, manage, and delete their own accounts.

## Authorization

The system uses organization units, groups, and roles and functionalities (also called cando) to manage authorization. A functionality is defined by an identifier consisting of app name, module, and function. A functionality also has a localized name and description. Roles have one or more functionalities assigned to them. Groups have roles assigned to them.

Each app has its own OU (Organization unit) tree template which is copied for each tenant inside the app. If the app does not make use of tenants, there is a single "system" tenant to handle authorization. The OU tree works similarly to Active Directory.

Furthermore, there are modules which can be defined as YAML files to extend a single tenant's OU tree.

## Roles and Administration

To administrate the system, the following roles have been defined:

- Global admin (access to everything)
- App admin (access to a single application and all underlying tenants)
- Tenant admin (access to a single tenant inside a single application)

The global admin can manage users, an email blacklist (to prevent signing up with junk mail), and apps.

The app admin can manage their app configuration, functionalities, roles, documents (called contents, for example, terms of service, privacy policy, app information (shown on login screen)), the OU tree template, and tenants. Furthermore, they can view all users part of their app and optionally remove the user from the app (this does not delete the user account).

The app configuration includes a name (used as ID), a short name and full name (used as labels), the application URL, locales supported by the app, default locale, email configuration (from, reply-to, logo, footer (localized HTML), SMTP server address, port, username, password, auth mode, TLS config, connection timeout), and theme settings.

Tenant admins can set a short name and a full name, upload a tenant image, and set which authorization modules (the ones that extend the OU tree) are used. They can modify the OU tree to their liking and assign users to groups inside the OU tree. They also have the same user overview as the app admin, but only see the users in their own tenant.


## Configuration

The backend has multiple configuration files as well as database seed files. The configuration files come with examples (`application.yml` => `application.yml.example`, `mongoid.yml` => `mongoid.yml.example`). The database seed files can be found under `config/apps/app_name/actor_defaults/*.yml` (OU tree templates for app and extension modules), `config/apps/app_name/seeds/candos.yml` (functionalities with title and description non localized) and `config/apps/app_name/seeds/roles.yml` (roles with app, name, title, description non localized, and "candos" (functionalities) assigned to the role).
Title and description used in these seed files are localized in `config/apps/app_name/locales/candos/<lang-code>.yml` and `config/apps/app_name/locales/roles/<lang-code>.yml`.

### Initial Setup

1. Clone this repository
2. Configure `application.yml` and `mongoid.yml`
3. Make sure MongoDB runs in replSet mode (`rs0`)
4. Ensure you're using the correct Ruby version (see the file ".ruby-version")
5. Run `bundle install`
6. Run `rails db:migrate`
7. Run `rails db:mongoid:create_indexes`
8. Run `manual=true rails db:seed`
9. Run `rails app:admin name="identity-management" email="admin@ident.services"`
10. Register your app with `rails app:register name="your-app" url="https://target.domain.tld"`
11. Make yourself admin for your app with the `rails app:admin` command.

The global admin account is email `admin@ident.services` and password `##################` (18 * `#`). Please change the password immediately.

### Updating

1. `git pull`
2. `rails db:mongoid:remove_undefined_indexes`
3. `rails db:mongoid:create_indexes`
4. `rails db:migrate`
5. If any seed files changed see below

### Changing the seed files and applying changes

1. Open a rails console (`rails c`)
2. Run `Actors::App.all.each(&:ensure_defaults!)`
3. Run `Actors::Tenant.all.each(&:ensure_defaults!)`

## Building / Hosting

Build the docker file and route `/api/*` and `/api-docs/*` to the docker container using a reverse proxy.
