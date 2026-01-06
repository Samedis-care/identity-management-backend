# this fixes a problem that suddenly (expecting some gem like JWT)
# has globally activated CRL checking which will break many https
# connections as no CRL list is actually present
# so this resets to do no CRL checking
# config/initializers/00_openssl_clear_crl.rb
require "openssl"

# Use the existing default store and clear any CRL-related flags
begin
  store = OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE
  store.flags = 0 if store.respond_to?(:flags=)
rescue => e
  warn "Could not clear DEFAULT_CERT_STORE flags: #{e.class}: #{e.message}"
end

# Ensure default params keep strict peer verification and this store
OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:verify_mode] = OpenSSL::SSL::VERIFY_PEER
OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:cert_store]  = OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE

# (Optional but robust) ignore *only* the “missing CRL” errors globally.
OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:verify_callback] = proc do |ok, ctx|
  ok || [
    OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL,
    OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL_ISSUER
  ].include?(ctx.error)
end
