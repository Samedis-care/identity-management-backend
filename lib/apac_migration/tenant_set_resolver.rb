module ApacMigration
  # Resolves the exact set of documents that belong to the APAC region, so the
  # copier never has to guess. Source of truth for the tenant ids is SCB; here
  # they come either from `Actors::Tenant.apac` (region field, set via
  # `apac:mark_region`) or from an explicit override list (TENANT_IDS).
  class TenantSetResolver
    # Master-data / MDM tenant — hex of "samedis-care". region is nil, so it is
    # never in `.apac`; it is a system tenant that must exist on every cluster.
    MDM_TENANT_ID = BSON::ObjectId('73616d656469732d63617265')

    def initialize(tenant_ids: nil)
      @explicit_ids = normalize(tenant_ids) if tenant_ids.present?
    end

    # Tenant _ids whose data belongs on the target: the region-driven APAC set
    # (or explicit override) PLUS always-required system tenants (MDM).
    def apac_tenant_ids
      @apac_tenant_ids ||= ((@explicit_ids || Actors::Tenant.apac.pluck(:_id)) + system_tenant_ids).uniq
    end

    # App-level skeleton actors below each App: its direct children (containers,
    # the app "users" Group used by ensure_app_membership!, app-admins /
    # tenant-admins groups, the app Organization) plus everything under the app
    # Organization. Excludes Tenants (copied separately) and Mappings (per-user;
    # would reference non-migrated EU users). These are app structure only — no
    # tenant identity data — needed for app-level flows (login → app membership)
    # to work on the target.
    def app_skeleton_ids
      @app_skeleton_ids ||= begin
        apps = app_actor_ids
        org_ids = Actor.unscoped.where(:parent_id.in => apps, _type: 'Actors::Organization').distinct(:_id)
        ids  = Actor.unscoped.where(:parent_id.in => apps)
                    .where(:_type.nin => %w[Actors::Tenant Actors::Mapping]).distinct(:_id)
        ids += Actor.unscoped.where(:parent_ids.in => org_ids)
                    .where(:_type.nin => %w[Actors::Mapping]).distinct(:_id)
        ids.uniq
      end
    end

    # All EU (non-APAC) tenants that exist in the SOURCE. The leak guard uses
    # this as a blacklist: a target record tied to one of these is a genuine EU
    # leak — whereas a record created natively on the live APAC cluster (not
    # present in the source at all) is legitimate and must NOT be flagged.
    def eu_tenant_ids
      @eu_tenant_ids ||= Actors::Tenant.unscoped.distinct(:_id) - apac_tenant_ids
    end

    # System tenants required on every cluster regardless of region: the MDM
    # tenant, plus each App's own internal "system" tenant (created by
    # `Actors::App#ensure_im_app!`-style bootstraps as a direct child of the
    # app's ContainerTenants — e.g. identity-management's admin-org holder).
    # These carry app-internal config, not customer/EU identity data.
    def system_tenant_ids
      @system_tenant_ids ||= begin
        ids = [MDM_TENANT_ID].select { |id| Actor.unscoped.where(_id: id, _type: 'Actors::Tenant').exists? }
        ids + Actor.unscoped.where(_type: 'Actors::App').filter_map do |app|
          Actors::Tenant.unscoped.where(name: 'system', parent: app.container_tenants).first&.id
        end
      end.uniq
    end

    # Mappings that grant app-level admin rights (Actors::App#admins /
    # #tenant_admins groups), restricted to tenant_id: nil so only genuine
    # app-wide staff admin grants are included — NOT the app's generic "users"
    # membership group (app_container_users), which holds one mapping per
    # registered app user and would leak EU user actor ids if copied wholesale.
    def system_admin_mapping_ids
      @system_admin_mapping_ids ||= begin
        group_ids = Actor.unscoped.where(_type: 'Actors::App').flat_map do |app|
          [app.admins, app.tenant_admins].compact.map(&:id)
        end
        Actors::Mapping.unscoped.where(:parent_id.in => group_ids, tenant_id: nil).distinct(:_id)
      end
    end

    # All App definition nodes (incl. the identity-management base app), copied
    # wholesale. App skeleton/config only — no tenant identity data — needed so
    # the actor tree, app-level admin groups and roles' actors_app_id resolve.
    def app_actor_ids
      @app_actor_ids ||= Actor.unscoped.where(_type: 'Actors::App').distinct(:_id)
    end

    # All actors in the APAC tenant subtree: the tenant nodes themselves plus
    # every descendant (Organization / Ou / Group / Mapping all carry the
    # tenant id in `parent_ids`). Every Mapping selected here is, by definition,
    # an APAC mapping — EU mappings of shared users are never in this set.
    def subtree_actor_criteria
      Actor.unscoped.or(
        { :_id.in => apac_tenant_ids },
        { :parent_ids.in => apac_tenant_ids }
      )
    end

    # User ids (identities) with at least one mapping into an APAC tenant, plus
    # always-required system users (global_admin). Their Actors::User nodes come
    # along automatically via actor_user_ids — User and Actors::User are always
    # copied together.
    def user_ids
      @user_ids ||= (Actors::Mapping.unscoped
                                    .where(:tenant_id.in => apac_tenant_ids)
                                    .distinct(:user_id).compact + system_user_ids).uniq
    end

    # System users required on every cluster: global_admin (if present — some
    # environments use a synthetic global_admin actor instead of named staff)
    # plus whoever holds app-admin/tenant-admin rights via system_admin_mapping_ids.
    def system_user_ids
      @system_user_ids ||= begin
        node = Actors::User.unscoped.where(name: :global_admin).first
        ids = node ? ::User.unscoped.where(actor_id: node.id).distinct(:_id) : []
        ids + Actors::Mapping.unscoped.where(:_id.in => system_admin_mapping_ids).distinct(:user_id).compact
      end.uniq
    end

    # Personal Actors::User nodes for the migrated users. These live in the
    # global user_container, NOT inside any tenant subtree, so they must be
    # selected explicitly.
    def actor_user_ids
      @actor_user_ids ||= ::User.unscoped.where(:_id.in => user_ids)
                                .distinct(:actor_id).compact
    end

    # Structural ancestor nodes (App + ContainerApps/ContainerTenants/
    # ContainerUsers/root) referenced via parent_ids by the copied tenant
    # subtrees and user nodes. They must exist on the target with their original
    # _ids so the actor tree, path resolution and the roles/functionalities
    # `actors_app_id` references stay intact. These carry app skeleton/config
    # only — no tenant identity data, and no other tenants (siblings are
    # separate child docs, never ancestors).
    def structural_ancestor_ids
      @structural_ancestor_ids ||= begin
        pids  = subtree_actor_criteria.distinct(:parent_ids)
        pids += Actor.unscoped.where(:_id.in => actor_user_ids).distinct(:parent_ids)
        pids.compact.uniq
      end
    end

    # Invites are scoped by tenant_id, but the field is `type: Object` and the
    # values are stored inconsistently — some as String, some as BSON::ObjectId.
    # Match BOTH representations so no APAC invite is missed.
    def invite_tenant_id_matchers
      @invite_tenant_id_matchers ||= apac_tenant_ids + apac_tenant_ids.map(&:to_s)
    end

    def invite_criteria
      Invite.unscoped.where(:tenant_id.in => invite_tenant_id_matchers)
    end

    private

    def normalize(ids)
      Array(ids).filter_map do |id|
        id.is_a?(BSON::ObjectId) ? id : (BSON::ObjectId(id.to_s) rescue nil)
      end
    end
  end
end
