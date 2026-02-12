class AccountActivity < ApplicationDocument
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search

  field :user_id, type: BSON::ObjectId
  field :token_id, type: String
  field :ip, type: String
  field :app, type: String
  field :navigator, type: String
  field :location, type: String
  field :device, type: String

  QUICKFILTER_COLUMNS = [:app, :navigator]
  search_in *QUICKFILTER_COLUMNS

  has_one :user, inverse_of: :account_activities, class_name: User
  has_one :token, class_name: Doorkeeper::AccessToken

  index user_id: 1
  index token_id: 1

end
