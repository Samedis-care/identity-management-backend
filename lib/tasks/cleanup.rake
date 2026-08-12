namespace :cleanup do
  desc <<~DESC
    Neutralize pre-existing HTML tag syntax in Actors::Tenant name/short_name/
    full_name, ahead of the SafeHtmlValidator added for samedis-care-backend
    issue #2417.

    That validator is retroactive: a Tenant already containing a literal HTML
    tag (e.g. the pentest's own "NewTestFacility"><s>sss<h1>TEST</h1>" test
    artifact) would fail validation on its next save, even for an unrelated
    field change -- blocking normal use of the record until fixed. This
    one-off task finds and neutralizes those records first.

    Uses SafeHtmlValidator.strip_tags -- keeps a tag's inner text, drops the
    tag itself; leaves any record with no actual tag completely untouched (a
    MongoDB regex pre-filter on "<"/">" is just a cheap first pass, not the
    final decision -- SafeHtmlValidator.contains_html_tag? is the real check).

    Idempotent -- safe to re-run (only matches docs that still fail the check).

    Options:
      DRY_RUN=true   (default) -- report what would change without touching the DB
      DRY_RUN=false  -- actually update the records

    Usage:
      bundle exec rake cleanup:strip_html_injection              # dry run
      bundle exec rake cleanup:strip_html_injection DRY_RUN=false
  DESC
  task strip_html_injection: :environment do
    dry_run = ENV.fetch('DRY_RUN', 'true') != 'false'

    puts '=' * 60
    puts "STRIP PRE-EXISTING HTML INJECTION#{dry_run ? ' — DRY RUN' : ''}"
    puts '=' * 60

    tag_regex = /[<>]/
    fixes = []

    Actors::Tenant.any_of({ name: tag_regex }, { short_name: tag_regex }, { full_name: tag_regex }).each do |tenant|
      %i[name short_name full_name].each do |field|
        original = tenant[field]
        next unless SafeHtmlValidator.contains_html_tag?(original)

        fixes << { record: tenant, field:, original:, cleaned: SafeHtmlValidator.strip_tags(original) }
      end
    end

    if fixes.empty?
      puts 'Nothing to do — no pre-existing HTML injection found.'
      next
    end

    puts "Found #{fixes.size} field(s) to neutralize:\n\n"
    fixes.each do |fix|
      puts "  #{fix[:record].class} #{fix[:record].id} ##{fix[:field]}:"
      puts "    before: #{fix[:original].inspect}"
      puts "    after:  #{fix[:cleaned].inspect}"
    end

    if dry_run
      puts "\nDry run — no changes made. Re-run with DRY_RUN=false to apply."
      next
    end

    fixes.each { |fix| fix[:record].set(fix[:field] => fix[:cleaned]) }
    puts "\nNeutralized #{fixes.size} field(s)."
  end
end
