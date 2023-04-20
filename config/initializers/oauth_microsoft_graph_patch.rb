module OmniAuth
  module Strategies
    class MicrosoftGraph < OmniAuth::Strategies::OAuth2

      option :authorize_options, %i[state display score auth_type scope prompt login_hint domain_hint response_mode]

      # Monkey Patch to support state query param
      # for the callback URL
      def authorize_params
        super.tap do |params|
          %w[display score auth_type state].each do |v|
            if request.params[v]
              params[v.to_sym] = request.params[v]
            end
          end
        end
      end

    end
  end
end