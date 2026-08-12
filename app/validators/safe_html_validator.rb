# Defense-in-depth against stored HTML injection (see samedis-care-backend
# issue #2417 — Cognisys pentest, July 2026, and PR #4123/#4126/#276 there).
# Ported from that repo's identical validator: this backend independently
# feeds the same downstream chain (a Tenant's name here is echoed back to
# the samedis-care-backend Tenant#handle field via the /api/v1/user/tenant
# endpoint, completely unvalidated on that end until this check exists on
# this end too — verified empirically that Actor#get_name's to_slug
# conversion does NOT neutralize literal HTML tags, only incidentally
# strips quotes/slashes: "foo\"><s>x<h1>y</h1>".to_slug still contains a
# literal "<s>"/"<h1>").
#
# NOT purely parser-based, after review found the parser-only check has real
# bypasses (see PR #276 review by @SCjona, verified empirically before
# fixing, not just accepted):
#   - No tag at all: `NewTestFacility" autofocus onfocus=alert(1) x="` —
#     zero "<" means zero Element nodes, but this is a live attribute-
#     breakout payload wherever the stored value lands inside an existing
#     HTML attribute.
#   - Tags the HTML5 *fragment*-parsing algorithm discards: `<body
#     onload=...>`, `<html ...>`, and table-scoped tags outside a table
#     (`<td ...>`) produce no Element child when parsed as a context-less
#     fragment, but merge onto the real page's own body/html element (or
#     render as a live tag) once echoed into an actual document.
#   - EOF-truncated tags: `NewTestFacility<img src=x onerror=alert(1)` (no
#     closing ">") hits the tokenizer's eof-in-tag state, which discards the
#     pending tag token as a parse error — but a real browser's tokenizer,
#     given more text after it (the surrounding page markup), keeps
#     consuming as attributes until the next ">" and builds a live tag.
# All three verified to bypass a parser-only children.any?(&:element?)
# check, and all three are caught by the plain character-class check below.
#
# UNSAFE_CHARS deliberately excludes the single quote/apostrophe: legitimate
# tenant/organization names commonly contain one (O'Brien, L'Oréal, D'Angelo)
# and rejecting it would be a real, visible usability regression for exactly
# the kind of ordinary name this validator must not flag. Double-quote is
# included since it's the character the original pentest payload itself
# breaks out with, and has far lower legitimate-use likelihood in a name.
#
# The character-class check is a REJECTION filter, not a "sanitize with
# regex" — there is no tag grammar to get confused by, and for a tenant
# name/short_name/full_name, "<"/">"/'"' have no legitimate use at all. The
# parser check is kept alongside it for the cases the character class alone
# wouldn't cover — kept as a second, independent signal, not because either
# one is complete on its own.
require 'loofah'

class SafeHtmlValidator < ActiveModel::EachValidator
  UNSAFE_CHARS = /[<>"]/

  # Reusable outside the validation context — for neutralizing a value at a
  # cache/sync point where rejecting isn't an option (there's no request to
  # fail). Two branches, not one gsub-after-#text: Loofah's #text
  # unconditionally HTML-entity-escapes "&"/"<"/">"/quotes rather than
  # removing them (running gsub(UNSAFE_CHARS, '') on its OUTPUT is a no-op —
  # by then the characters are already multi-char entity sequences like
  # "&quot;", not the literal characters the regex matches). So: when a real
  # element is present, unwrap it via Loofah#text as before (safe, keeps
  # inner text, accepts the entity-escaping as a minor cosmetic trade-off);
  # when the only problem is the character-class check (no real tag to
  # unwrap — a no-tag attribute-breakout, or an EOF-truncated tag), skip
  # Loofah entirely and remove the characters directly, which is both
  # simpler and avoids visible entity-escaping garbage for no benefit.
  def self.strip_tags(value)
    return value if value.blank?

    if Loofah::HTML5::DocumentFragment.parse(value).children.any?(&:element?)
      Loofah::HTML5::DocumentFragment.parse(value).text
    elsif value.match?(UNSAFE_CHARS)
      value.gsub(UNSAFE_CHARS, '')
    else
      value
    end
  end

  def self.contains_html_tag?(value)
    return false if value.blank?
    return true if value.match?(UNSAFE_CHARS)

    Loofah::HTML5::DocumentFragment.parse(value).children.any?(&:element?)
  end

  def validate_each(record, attribute, value)
    return unless self.class.contains_html_tag?(value)

    record.errors.add(attribute, options[:message] || :contains_html_tags)
  end
end
