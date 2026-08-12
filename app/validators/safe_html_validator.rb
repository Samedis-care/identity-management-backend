# Defense-in-depth against stored HTML injection (see samedis-care-backend
# issue #2417 — Cognisys pentest, July 2026, and PR #4123/#4126 there).
# Ported from that repo's identical validator: this backend independently
# feeds the same downstream chain (a Tenant's name here is echoed back to
# the samedis-care-backend Tenant#handle field via the /api/v1/user/tenant
# endpoint, completely unvalidated on that end until this check exists on
# this end too — verified empirically that Actor#get_name's to_slug
# conversion does NOT neutralize literal HTML tags, only incidentally
# strips quotes/slashes: "foo\"><s>x<h1>y</h1>".to_slug still contains a
# literal "<s>"/"<h1>").
#
# Deliberately NOT regex-based ("never sanitize HTML with regex" — a hand
# rolled tag pattern is trivially bypassed by malformed/unclosed tags that
# lenient renderers still interpret as markup). Uses a real HTML5 parser
# (Nokogiri::HTML5, via the Loofah gem already resolved transitively through
# rails-html-sanitizer/actionview) and checks for Element nodes rather than
# comparing decoded text, which avoids false positives on ordinary text
# containing bare "&" (e.g. "Müller & Sohn GmbH") — Loofah's own #text
# re-escapes "&" for safe redisplay, which would otherwise flag any
# ordinary ampersand as "contains HTML".
require 'loofah'

class SafeHtmlValidator < ActiveModel::EachValidator
  # Reusable outside the validation context — for neutralizing a value at a
  # cache/sync point where rejecting isn't an option (there's no request to
  # fail). Strips any HTML element, keeps the inner text, and only invokes
  # Loofah's own text-extraction (which unconditionally re-escapes
  # "&"/"<"/">"/quotes) when a tag is actually present — otherwise ordinary
  # text passes through completely untouched.
  def self.strip_tags(value)
    return value unless contains_html_tag?(value)

    Loofah::HTML5::DocumentFragment.parse(value).text
  end

  def self.contains_html_tag?(value)
    return false if value.blank?

    Loofah::HTML5::DocumentFragment.parse(value).children.any?(&:element?)
  end

  def validate_each(record, attribute, value)
    return unless self.class.contains_html_tag?(value)

    record.errors.add(attribute, options[:message] || :contains_html_tags)
  end
end
