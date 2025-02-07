class ChangeCachedUsernameFormat < Mongoid::Migration
  # changes short_name / full_name cached on user mappings to a sortable
  # format with lastname in front
  def self.up
    _aggregation = [
      {
        '$match' => {
          '_type' => 'Actors::Mapping',
          'user_id' => {
            '$ne' => nil
          }
        }
      }, {
        '$lookup' => {
          'from' => 'users',
          'localField' => 'user_id',
          'foreignField' => '_id',
          'as' => 'user'
        }
      }, {
        '$addFields' => {
          'user' => {
            '$first' => '$user'
          }
        }
      }, {
        '$addFields' => {
          'friendlyname' => {
            '$concat' => [
              '$user.last_name', ', ', '$user.first_name'
            ]
          }
        }
      }, {
        '$project' => {
          'friendlyname' => 1
        }
      }, {
        '$merge' => {
          'into' => 'actors',
          'on' => '_id',
          'whenMatched' => 'merge',
          'whenNotMatched' => 'discard'
        }
      }
    ]
    Actor.collection.aggregate(_aggregation).to_a
  end
end
