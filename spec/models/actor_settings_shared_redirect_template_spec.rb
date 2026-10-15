require 'rails_helper'

# Regression cover for the shared-mutation bug in Actor#settings (app/models/actor.rb):
# `Actor.default_settings` memoizes the parsed per_app_settings.yml in a class variable
# and returns it on every call. `deep_symbolize_keys` rebuilds the Hash structure each
# time but does NOT duplicate leaf values, so the `authenticated` redirect template
# string handed back is the SAME object across unrelated Apps and requests. Actor#settings
# used to call `.gsub!` (destructive) on that shared string whenever an App's
# `uses_bearer_token` was not `true`, permanently rewriting the process-wide cached
# default from a `#`-fragment form to a `?`-query form -- corrupting it for every other
# App on that worker that falls back to the same default, including ones with
# `uses_bearer_token: true` that need to keep the fragment form (their SPA reads the
# OAuth token from `location.hash`, not the query string).
#
# Discovered while investigating a customer-reported SSO login break for a
# CustomAuthProvider tenant on the `samedis-care` App (uses_bearer_token: true, no
# settings.redirects override) -- no code or data changed for that App; the corruption
# came from an unrelated App with uses_bearer_token: false sharing the same worker.
RSpec.describe Actor, '#settings' do
  let(:sfx) { SecureRandom.hex(4) }
  let!(:bearer_app) { Actors::App.create!(name: "bearer-app-#{sfx}", config: { uses_bearer_token: true }) }
  let!(:non_bearer_app) { Actors::App.create!(name: "non-bearer-app-#{sfx}", config: { uses_bearer_token: false }) }

  # Actor.default_settings (app/models/actor.rb) -- the method Actor#settings actually
  # calls via self.class.default_settings -- memoizes the parsed YAML in a class
  # variable owned by Actor itself (shared by every Actor subclass, Actors::App
  # included). Reset it so this spec observes a clean load regardless of what earlier
  # examples already triggered.
  around do |example|
    if Actor.class_variables(false).include?(:@@default_settings)
      Actor.send(:remove_class_variable, :@@default_settings)
    end
    example.run
    if Actor.class_variables(false).include?(:@@default_settings)
      Actor.send(:remove_class_variable, :@@default_settings)
    end
  end

  after do
    bearer_app.delete
    non_bearer_app.delete
  end

  it 'does not corrupt the default authenticated template for a bearer-token App that reads it afterwards' do
    # Establishes the baseline: an app with uses_bearer_token: true keeps the
    # '#'-fragment form when it is the first (and only) app to resolve #settings.
    expect(bearer_app.settings[:redirects][:authenticated]).to include('/authenticated#')

    # A non-bearer-token app on the same process falls back to the same default
    # template and rewrites its own copy to '?' -- this must not touch the shared cache.
    expect(non_bearer_app.settings[:redirects][:authenticated]).to include('/authenticated?')

    # The bug: re-resolving the bearer-token app's settings (simulating a second
    # request on the same worker, with its own unmemoized Actor instance) used to see
    # the '?' form leaked from non_bearer_app, because both read the same cached
    # string object out of Actors::App.default_settings.
    fresh_bearer_app = Actors::App.find(bearer_app.id)
    expect(fresh_bearer_app.settings[:redirects][:authenticated]).to include('/authenticated#')
    expect(fresh_bearer_app.settings[:redirects][:authenticated]).not_to include('/authenticated?')
  end

  it 'does not mutate the shared default_settings cache at all' do
    non_bearer_app.settings

    # Actor.default_settings (app/models/actor.rb) returns the raw, string-keyed parsed YAML,
    # cached in a class variable shared process-wide across all Actor subclasses.
    raw_default = Actor.default_settings.dig('default_redirects', 'authenticated')
    expect(raw_default).to include('/authenticated#')
    expect(raw_default).not_to include('/authenticated?')
  end

  # Found in bot review on PR #294 (round 1): actor_settings.redirects is a free-form
  # Hash, operator-set (console/seeds only -- no controller permits actor_settings).
  # Overriding one key (e.g. `login`) without `authenticated`
  # leaves `_settings[:redirects][:authenticated]` nil -- the `||=` on the line above
  # only fills in the whole default hash when the key is missing entirely, not when
  # it's partially present. Pre-existing on both sides of this PR (old code raised the
  # identical NoMethodError on `nil.gsub!`) -- covered because the line is being
  # touched anyway.
  it 'does not raise when actor_settings.redirects overrides one key but omits authenticated' do
    partial_override_app = Actors::App.create!(
      name: "partial-redirects-app-#{sfx}",
      config: { uses_bearer_token: false },
      actor_settings: { 'redirects' => { 'login' => 'https://example.test/login' } }
    )

    expect { partial_override_app.settings }.not_to raise_error
    expect(partial_override_app.settings[:redirects][:authenticated]).to be_nil
  ensure
    partial_override_app&.delete
  end

  # Samedis-care/samedis-care-issues#2859: #294 stopped the one mutation, but every leaf of the cache was
  # still a shared, unfrozen String; any future in-place change would reintroduce the bug class.
  describe 'the cached default settings' do
    def each_object(value, &block)
      block.call(value)
      case value
      when Hash
        value.each do |key, leaf|
          each_object(key, &block)
          each_object(leaf, &block)
        end
      when Array then value.each { |leaf| each_object(leaf, &block) }
      end
    end

    it 'are frozen all the way down, keys and leaves' do
      unfrozen = []
      each_object(Actor.default_settings) { |object| unfrozen << object unless object.frozen? || object.nil? || object == false || object == true }

      expect(unfrozen).to be_empty
    end

    it 'refuse an in-place change of a leaf instead of rewriting the default for every app' do
      expect { Actor.default_settings.dig('default_redirects', 'authenticated').gsub!('#', '?') }.to raise_error(FrozenError)
      expect { Actor.default_settings.dig('default_redirects', 'login') << 'x' }.to raise_error(FrozenError)
      expect { Actor.default_settings['default_redirects']['login'] = 'x' }.to raise_error(FrozenError)
    end

    it 'keep the helper that builds them out of the public class API' do
      expect(Actor).not_to respond_to(:deep_freeze_settings)
      expect(Actors::Tenant).not_to respond_to(:deep_freeze_settings)
    end

    it 'are still memoized: the same object on every call' do
      expect(Actor.default_settings).to equal(Actor.default_settings)
    end

    it 'still serve Actor#settings, whose own Hash stays writable for the non-destructive rewrite' do
      settings = non_bearer_app.settings

      expect(settings[:redirects]).not_to be_frozen
      expect(settings[:redirects][:authenticated]).to include('/authenticated?')
    end
  end

  it 'no longer carries the dead second copy of the default settings on Actors::App::Config' do
    expect(Actors::App::Config).not_to respond_to(:default_settings)
    expect(Actors::App::Config.method_defined?(:redirects)).to be(false)
  end
end
