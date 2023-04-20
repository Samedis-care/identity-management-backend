module WithBlame
  extend ActiveSupport::Concern
  include WithBlameNoIndex

  included do
    index({ created_by: 1 }, sparse: true)
    index({ created_by_user: 1 }, sparse: true)
    index({ updated_by: 1 }, sparse: true)
    index({ updated_by_user: 1 }, sparse: true)
  end

end
