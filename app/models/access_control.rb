class AccessControl
  include ActiveModel::API

  attr_accessor :id, :name, :label, :group, :group_name, :description, :role_ids
  alias_attribute :_id, :id

  def initialize(params = {})
    params.each do |key, value|
      setter = "#{key}="
      send(setter, value) if respond_to?(setter.to_sym, false)
    end
  end

  def to_h
    {
      id:,
      name:,
      label:,
      group:,
      description:,
      role_ids:
    }
  end

  def self.for_tenant(tenant_id)
    return get_access_control(tenant_id)
  end

  def self.for_app(app_id)
    return get_access_control(app_id)
  end

  def self.aggregation_access_control(actor_id, locale: I18n.locale)
    locale = locale.to_s
    [
      {
        '$match': {
          'deleted': false, 
          '_type': 'Actors::Organization', 
          'parent_id': BSON::ObjectId(actor_id)
        }
      }, {
        '$project': {
          '_id': 1, 
          '_type': 1, 
          'path': 1, 
          'title': 1, 
          'parent_id': 1, 
          'parent_ids': 1
        }
      }, {
        '$lookup': {
          'from': 'actors', 
          'localField': '_id', 
          'foreignField': 'parent_ids', 
          'as': 'groups', 
          'pipeline': [
            {
              '$match': {
                '_type': 'Actors::Group',
                'deleted': false
              }
            }, {
              '$project': {
                '_id': 1, 
                'name': 1,
                '_type': 1, 
                'path': 1, 
                'title': 1, 
                'parent_id': 1, 
                'parent_ids': 1, 
                'role_ids': 1,
              }
            }
          ]
        }
      }, {
        '$unwind': {
          'path': '$groups'
        }
      }, {
        '$replaceRoot': {
          'newRoot': '$groups'
        }
      }, {
        '$lookup': {
          'from': 'actors', 
          'localField': 'parent_id', 
          'foreignField': '_id', 
          'as': 'parent', 
          'pipeline': [
            {
              '$match': {
                'deleted': false
              }
            }, {
              '$project': {
                'title': 1,
                'name': 1
              }
            }
          ]
        }
      }, {
        '$addFields': {
          'parent': {
            '$first': '$parent'
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
                'title': 1, 
                'description': 1
              }
            }
          ]
        }
      }, {
        '$project': {
          '_id': 0, 
          'id': {
            '$toString': '$_id'
          }, 
          'name': 1,
          'group_name': '$parent.name',
          'group': {
            '$getField': {
              'field': locale, 
              'input': '$parent.title'
            }
          }, 
          'label': {
            '$getField': {
              'field': locale, 
              'input': '$title'
            }
          }, 
          'role_ids': {
            '$setUnion': "$roles._id"
          },
          'description': {
            '$reduce': {
              'input': {
                '$setUnion': '$roles.description.' + locale
              }, 
              'initialValue': '', 
              'in': {
                '$concat': [
                  '$$value', {
                    '$cond': [
                      {
                        '$eq': [
                          '$$value', ''
                        ]
                      }, '', "\n"
                    ]
                  }, '$$this'
                ]
              }
            }
          }
        }
      }, {
        '$sort': {
          'group': 1, 
          'label': 1
        }
      }
    ]
  end

  def self.get_access_control(actor_id, locale: I18n.locale)
    Actor.collection.aggregate(aggregation_access_control(actor_id, locale:)).collect do |attrs|
      new **attrs
    end
  end

end
