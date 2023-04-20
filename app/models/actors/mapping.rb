module Actors

  class Mapping < Actor

    before_validation :ensure_user_data
    before_validation :ensure_references
    after_save :user_cache_expire!
    after_save :merge_group_candos!

    validates :map_actor_id, presence: true
    belongs_to :mapped_into, class_name: Actor, primary_key: :map_actor_id, inverse_of: :mappings, optional: true

    belongs_to :user, class_name: '::User', optional: true, inverse_of: nil

    field :app_id, type: BSON::ObjectId
    field :user_id, type: BSON::ObjectId
    field :tenant_id, type: BSON::ObjectId
    field :parent_template_actor_id, type: BSON::ObjectId
    field :cached_role_ids, type: Array
    field :cached_role_names, type: Array
    field :cached_candos, type: Array

    # def user=(map_user)
    #   if map_user.is_a?(User)
    #     self.map_actor_id = map_user&.actor&.id
    #   end
    # end

    # def user_id=(map_id)
    #   map_user = User.available.where(_id: map_id).first
    #   if map_user.is_a?(User)
    #     self.user = map_user
    #   end
    # end

    def ensure_user_data
      _user = self.map_actor.user
      self.name = _user.email
      self.short_name = _user.name
      self.full_name = _user.name
    end

    def ensure_references
      self.app_id ||= self.app&.id
      self.user_id ||= self.map_actor.user&.id
      self.tenant_id ||= tenant&.id
      self.parent_template_actor_id ||= parent.template_actor&.id
    end

    def user_cache_expire!
      self.map_actor.user.cache_expire!
    end

    # delete orphaned actor mappings
    def self.cleanup_orphans!
      Actors::Mapping.where(:map_actor_id.nin => Actor.pluck(:_id)).delete_all
    end

    def self.get_tenant_candos
      collection.aggregate(
        aggregation_tenant_candos
      )
    end

    # Determines all the candos users grouped by 
    # stringified tenant_id as key and
    # stringified candos (array) as value
    # merges the resulting tenant_candos_cached field into
    # each resulting user
    def self.merge_tenant_candos!
      collection.aggregate(
        aggregation_tenant_candos +
        [
          {
            '$merge' => {
              'into' => 'users',
              'on' => '_id',
              'whenMatched' => 'merge',
              'whenNotMatched' => 'discard'
            }
          }
        ]
      ).to_a
    end

    def self.aggregation_tenant_candos
      [
        {
          '$match' => criteria.selector
        }
      ] + [
        {
          '$match': {
            '_type': 'Actors::Mapping'
          }
        }, {
          '$group': {
            '_id': {
              'user_id': '$user_id', 
              'tid': {
                '$convert': {
                  'input': '$tenant_id', 
                  'to': 'string'
                }
              }
            }, 
            'cached_candos': {
              '$push': '$cached_candos'
            }
          }
        }, {
          '$project': {
            'cached_candos': {
              '$reduce': {
                'input': '$cached_candos', 
                'initialValue': [], 
                'in': {
                  '$setUnion': [
                    '$$value', '$$this'
                  ]
                }
              }
            }
          }
        }, {
          '$project': {
            '_id': 0, 
            'user_id': '$_id.user_id', 
            'tenants': [
              {
                '$ifNull': [
                  '$_id.tid', 'global'
                ]
              }, '$cached_candos'
            ]
          }
        }, {
          '$group': {
            '_id': '$user_id', 
            'tenants_ary': {
              '$push': '$tenants'
            }
          }
        }, {
          '$project': {
            '_id': 1, 
            'tenant_candos_cached': {
              '$arrayToObject': '$tenants_ary'
            }
          }
        }
      ]
    end

    def self.get_tenant_access_group_ids
      collection.aggregate(
        aggregation_tenant_access_group_ids
      )
    end

    def self.aggregation_tenant_access_group_ids
      [
        {
          '$match': criteria.selector
        }, {
          '$match': {
            'tenant_id': {
              '$ne': nil
            }
          }
        }
      ] + [
        {
          '$group': {
            '_id': {
              'user_id': '$user_id',
              'tid': {
                '$convert': {
                  'input': '$tenant_id',
                  'to': 'string'
                }
              }
            },
            'group_ids': {
              '$push': {
                '$convert': {
                  'input': '$parent_id',
                  'to': 'string'
                }
              }
            }
          }
        }, {
          '$project': {
            '_id': 0,
            'user_id': '$_id.user_id',
            'tenant_groups': [
              '$_id.tid', '$group_ids'
            ]
          }
        }, {
          '$group': {
            '_id': '$user_id',
            'tenant_group_ary': {
              '$push': '$tenant_groups'
            }
          }
        }, {
          '$project': {
            '_id': 1,
            'tenant_access_group_ids': {
              '$arrayToObject': '$tenant_group_ary'
            }
          }
        }
      ]
    end

    # Determines all the group memberships for users grouped by 
    # stringified tenant_id as key and
    # stringified group_ids (array) as value
    # merges the resulting tenant_access_group_ids field into
    # each resulting user
    def self.merge_tenant_access_group_ids!
      collection.aggregate(
        aggregation_tenant_access_group_ids +
        [
          {
            '$merge' => {
              'into' => 'users',
              'on' => '_id',
              'whenMatched' => 'merge',
              'whenNotMatched' => 'discard'
            }
          }
        ]
      ).to_a
    end

    # determines roles and its candos for mappings
    # to allow fetching user_ids that have a specific cando
    # fills the fields
    #  - cached_role_ids
    #  - cached_role_names
    #  - cached_candos
    def self.aggregation_group_candos
      [
        {
          '$match': criteria.selector
        }
      ] + [
        {
          '$match': {
            '_type': 'Actors::Mapping'
          }
        }, {
          '$project': {
            'group_id': '$parent_id', 
            'path': 1, 
            'user_id': 1, 
            'tenant_id': 1
          }
        }, {
          '$lookup': {
            'from': 'actors', 
            'localField': 'group_id', 
            'foreignField': '_id', 
            'as': 'group', 
            'pipeline': [
              {
                '$project': {
                  'role_ids': 1
                }
              }
            ]
          }
        }, {
          '$addFields': {
            'role_ids': {
              '$first': '$group.role_ids'
            }
          }
        }, {
          '$lookup': {
            'from': 'roles', 
            'localField': 'role_ids', 
            'foreignField': '_id', 
            'as': 'roles', 
            'pipeline': [
              {
                '$project': {
                  'name': 1, 
                  'functionality_ids': 1
                }
              }
            ]
          }
        }, {
          '$addFields': {
            'role_name': '$roles.name', 
            'functionality_ids': {
              '$reduce': {
                'input': '$roles.functionality_ids', 
                'initialValue': [], 
                'in': {
                  '$setUnion': [
                    '$$value', '$$this'
                  ]
                }
              }
            }
          }
        }, {
          '$lookup': {
            'from': 'functionalities', 
            'localField': 'functionality_ids', 
            'foreignField': '_id', 
            'as': 'candos', 
            'pipeline': [
              {
                '$project': {
                  'cando': {
                    '$concat': [
                      '$app', '/', '$module', '.', '$ident'
                    ]
                  }
                }
              }
            ]
          }
        }, {
          '$project': {
            'cached_role_ids': '$role_ids', 
            'cached_role_names': '$role_name', 
            'cached_candos': '$candos.cando'
          }
        }
      ]
    end

    def self.merge_group_candos!
      collection.aggregate(
        aggregation_group_candos +
        [
          {
            '$merge' => {
              'into' => 'actors',
              'on' => '_id',
              'whenMatched' => 'merge',
              'whenNotMatched' => 'discard'
            }
          }
        ]
      ).to_a
    end

    def merge_group_candos!
      self.class.where(_id: id).merge_group_candos!
    end

  end

end
