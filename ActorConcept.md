# Identity Management Actor concept
## Tree structure

The current tree structure that is being set up when running `rails db:seed` will generate the following root nodes.

> - Users (type: `container`) every newly registered user automatically is placed here and never moved
>> Every child item is of actor type `user` and is automatically created and placed here via hook when a new User record is created
> - Apps (type: `container`) every app that will be using Identity Management will be put in here
>> Every child item here is of actor type `app` „identity-management“ itself as the first default app. Add you own app under this node.
>>> The apps can have as many children of actor type `group` like „Admins“, „Users“, „Tenant-Admins“ etc. to organize groupings of roles for every needed authorization
> - Tenants (type: `container`)
>> Every child item is of actor type `tenant` and is named after the Client
>>> Each tenant can have as many children of actor type `group` to organize their internal roles (e.g. nurses, doctors,..)

## Roles and Functionalities

For ease of tracking these the identity-management repository has the files `db/seeds/candos.yml` and `db/seeds/roles.yml`. In those every functionality can be written in the „CANDO“ readable format (instead of ObjectIDs that no human can remember). And the `roles.yml` combines those into logical groups.

>Feel free to add what you need to both of the files and re-run `rails db:seed`.
>The seeding will only add data, or change texts. But will not delete any existing records from the database.

## Assigning Roles

The IM Frontend will allow to assign Roles to any Actor (except those of type `user` as we want to prevent granting any rights to a user directly).

Optimally the roles get placed at the Actor of type `group`. But even `app` and `container` types are fine for the most basic roles (like „your-app user“ that will then grant the right to log in to your-app).

### Actor Mappings

The main versatility is with the actor type `mapping` where one actor can become member or like „symbolically“ linked to any other actor.

> Theoretically that way a User could be mapped into another User and that way inherit full access of the other user

Mappings can be nested up to 10 Levels (basically just a hard coded Limit in the MongoDB aggregation).

Example:
A user is mapped into `Tenants/Tenant Corporation/Users`. And therefor gains all roles/functionalites that are given to `Tenants/Tenant Corporation/Users` and the parent `Tenants/Tenant Corporation` and possibly to every `Tenants`.
Then the tenant `Tenants/Tenant Corporation` is being mapped into `Apps/your-app/Users`.
So the User will inherit from the tenant everything that the tenant inherited and that way is granted to be a User of your-app.
