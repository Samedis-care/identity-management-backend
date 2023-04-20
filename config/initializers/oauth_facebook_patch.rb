module OmniAuth
  module Strategies
    class Facebook < OmniAuth::Strategies::OAuth2

      option :authorize_options, [:state, :scope, :display, :auth_type]

      # Monkey Patch to support state query param
      # for the callback URL
      def authorize_params
        super.tap do |params|
          %w[display scope auth_type state].each do |v|
            if request.params[v]
              params[v.to_sym] = request.params[v]
            end
          end
          params[:state] ||= DEFAULT_SCOPE
        end
      end

    end
  end
end