# Class-level paging for JsonApiController (`Model.paginate(per_page:, page:, padding:)`), shared by
# ApplicationDocument and the Doorkeeper::AccessToken compatibility shim in
# IdentityManagementExtension. The shim used to be a no-op, so the account-logins index ignored
# page[limit] entirely and no fix to the paging here reached it (Samedis-care/samedis-care-issues#3298).
# Extend it into a class that has a Mongoid `criteria` and Kaminari's `page`.
module Paginating
  def paginate(opts = {})
    # page[limit]=0 is how a client asks for the count only (the index response's total does not
    # depend on paging). Without this it reached Kaminari's per(0) -> Mongo limit(0), which Mongo
    # reads as "no limit": every record, past PAGE_LIMIT_MAX (Samedis-care/samedis-care-issues#3296).
    # Same as samedis-care-backend. Only when a limit was given: nil/absent still means the default.
    return none if opts[:per_page].present? && opts[:per_page].to_i.zero?

    p = criteria
    p = p.page(opts[:page].to_i)
    p = p.per(opts[:per_page].to_i) if opts[:per_page].present?
    p = p.padding(opts[:padding].to_i) if opts[:padding].present? # dynamic page offset (skip = page*per_page+padding)
    p
  end
end
