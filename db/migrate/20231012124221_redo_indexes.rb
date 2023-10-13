class RedoIndexes < Mongoid::Migration
  def self.up
    Doorkeeper::AccessToken.redo_indexes
  end
end
