module OmniAuth
  module Strategies
    class Apple < OmniAuth::Strategies::OAuth2

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
        end.merge(nonce: new_nonce)
      end

      # fix for correct encoding of scope
      def request_phase
        redirect client.auth_code.authorize_url({:redirect_uri => callback_url}.merge(authorize_params)).gsub(/\+/, '%20')
      end

      # fix for invalid nonce error
      # from https://github.com/discourse/discourse-apple-auth/blob/486ce761aa44ba9b56056963b693644efc07a72f/lib/omniauth_apple.rb#L60
      def callback_phase
        if request.request_method.downcase.to_sym == :post
          url = callback_url.dup
          if (code = request.params['code']) && (state = request.params['state'])
            url += "?code=#{CGI::escape(code)}"
            url += "&state=#{CGI::escape(state)}"
            url += "&user=#{CGI::escape(request.params['user'])}" if request.params['user']
          end
          session.options[:drop] = true # Do not set a session cookie on this response
          return redirect url
        end
        super
      end

    end
  end
end