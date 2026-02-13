module Oauth
  class InvalidGrantWithReason < StandardError
    attr_reader :reason, :meta

    def initialize(reason, meta: {})
      @reason = reason.to_sym
      @meta = meta
      super(reason.to_s)
    end
  end
end
