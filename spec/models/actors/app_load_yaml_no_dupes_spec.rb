require 'rails_helper'

# Regression coverage for samedis-care-issues#2657 / #2659. Psych allows
# duplicate mapping keys and silently keeps the last one, so a duplicate
# cando/role locale key was invisible: JSON::Validator.validate! runs
# against the already-parsed Hash, where the earlier declaration has
# already been discarded, and a plain YAML.load succeeds as if nothing
# were wrong. Actors::App.load_yaml_no_dupes exists to catch that before
# it happens, by walking the Psych parse tree instead of the loaded value.
RSpec.describe Actors::App do
  describe '.load_yaml_no_dupes' do
    context 'when a mapping key is genuinely repeated' do
      let(:top_level_duplicate_yaml) do
        <<~YAML
          en:
            samedis-care/catalogs.mdm-admin:
              title: first
              description: first
            samedis-care/catalogs.mdm-user:
              title: unrelated
              description: unrelated
            samedis-care/catalogs.mdm-admin:
              title: second
              description: second
        YAML
      end

      # config/locales/candos/en.yml lines 51-53 and 60-62 on the
      # identity-management-samedis-app-config default branch, checked
      # 2026-08-28 (fixed in that repo's PR #17).
      let(:issue_2657_yaml) do
        <<~YAML
          en:
            samedis-care/catalogs.harmonization-import:
              title: Device Import
              description: Required to be able to execute device data imports
            samedis-care/catalogs.mdm-admin:
              title: Global Samedis Master Data Management Admin
              description: Required to view and edit all catalog data
            samedis-care/catalogs.mdm-user:
              title: Manufacturer or enterprise catalog master data management
              description: Required to to view and edit own master data management data
            samedis-care/catalogs.reader:
              title: Allows read access to catalogs
              description: Required to be able to access catalogs
            samedis-care/catalogs.mdm-admin:
              title: Global Samedis Master Data Management Admin
              description: Required to view and edit all catalog data
        YAML
      end

      let(:sequence_entry_duplicate_yaml) do
        <<~YAML
          - cando: samedis-care/catalogs.reader
            title: first title
            description: first description
            title: second title
        YAML
      end

      let(:two_independent_duplicates_yaml) do
        <<~YAML
          en:
            a:
              title: 1
            a:
              title: 2
            b:
              title: 1
            b:
              title: 2
        YAML
      end

      it 'raises on a duplicate key inside a top-level mapping' do
        expect { described_class.load_yaml_no_dupes(top_level_duplicate_yaml) }
          .to raise_error(%r{samedis-care/catalogs\.mdm-admin.*line 2.*line 8}m)
      end

      it 'reproduces the exact duplicate that shipped in #2657' do
        expect { described_class.load_yaml_no_dupes(issue_2657_yaml) }
          .to raise_error(RuntimeError, %r{samedis-care/catalogs\.mdm-admin})
      end

      it 'raises on a duplicate key nested inside a single sequence entry, the shape roles.yml uses' do
        expect { described_class.load_yaml_no_dupes(sequence_entry_duplicate_yaml) }
          .to raise_error(/'title'/)
      end

      it 'reports every duplicate found, not just the first' do
        expect { described_class.load_yaml_no_dupes(two_independent_duplicates_yaml) }
          .to raise_error(/'a'.*'b'/m)
      end
    end

    context 'when a key merely looks repeated but is not' do
      # roles.yml is a top-level sequence of independent mappings. Two roles
      # with the same `name:` value are two separate mappings, each
      # containing `name` exactly once -- not a repeated key within one
      # mapping, so this is a different (out of scope) kind of problem, not
      # the last-wins hazard this guard exists to catch.
      let(:same_value_different_mappings_yaml) do
        <<~YAML
          - name: some-role
            title: A role
            candos: [samedis-care/catalogs.reader]
          - name: some-role
            title: A role, redeclared
            candos: [samedis-care/catalogs.writer]
        YAML
      end

      let(:distinct_mappings_reusing_a_key_name_yaml) do
        <<~YAML
          - cando: samedis-care/catalogs.reader
            title: Allows read access to catalogs
          - cando: samedis-care/catalogs.writer
            title: Allows write access to catalogs
        YAML
      end

      let(:clean_yaml) do
        <<~YAML
          en:
            samedis-care/catalogs.reader:
              title: Allows read access to catalogs
              description: Required to be able to access catalogs
        YAML
      end

      it 'does not flag two sequence entries that happen to share a field value' do
        expect { described_class.load_yaml_no_dupes(same_value_different_mappings_yaml) }.not_to raise_error
      end

      it 'does not flag the same key name reused across independent mappings' do
        expect { described_class.load_yaml_no_dupes(distinct_mappings_reusing_a_key_name_yaml) }.not_to raise_error
      end

      it 'returns exactly what YAML.load would return for input with no duplicates' do
        expect(described_class.load_yaml_no_dupes(clean_yaml)).to eq(YAML.load(clean_yaml))
      end
    end

    context 'with a non-scalar (explicit complex) mapping key' do
      # YAML allows `? ... \n: ...` explicit keys, whose node has no single
      # #value to compare or report. This used to crash the walker with a
      # NoMethodError instead of falling through to the schema check, which
      # rejects it on its own terms with a usable message.
      let(:complex_key_yaml) { "? [a, b]\n: v\n" }

      it 'does not raise from inside the duplicate-key walk itself' do
        expect { described_class.load_yaml_no_dupes(complex_key_yaml) }.not_to raise_error
      end

      it 'still returns the value a plain YAML.load would' do
        expect(described_class.load_yaml_no_dupes(complex_key_yaml)).to eq(YAML.load(complex_key_yaml))
      end
    end

    context 'with a path' do
      let(:duplicate_yaml) { "a:\n  x: 1\n  x: 2\n" }

      it 'names the file in the raised message' do
        expect { described_class.load_yaml_no_dupes(duplicate_yaml, path: 'config/seeds/candos.yml') }
          .to raise_error(%r{\Aconfig/seeds/candos\.yml: })
      end

      it 'omits the file prefix when no path is given, unchanged from before' do
        expect { described_class.load_yaml_no_dupes(duplicate_yaml) }
          .to raise_error(/\ADuplicate YAML/)
      end
    end
  end

  # Confirms the guard is actually wired into the import paths that matter --
  # both the file-based seeding path (seed_candos!/seed_roles!/
  # seed_cando_locales!/seed_role_locales!) and the AppAdminController upload
  # path -- rather than merely existing as an unused class method.
  describe 'setters route through the duplicate-key check' do
    let(:app) { described_class.new(name: 'spec-app') }

    let(:duplicate_locale_yaml) do
      <<~YAML
        en:
          spec-app/foo.reader:
            title: one
            description: one
          spec-app/foo.reader:
            title: two
            description: two
      YAML
    end

    let(:duplicate_seed_candos_yaml) do
      <<~YAML
        - cando: spec-app/foo.reader
          title: one
          description: one
          title: two
      YAML
    end

    let(:duplicate_seed_roles_yaml) do
      <<~YAML
        - name: dup-role
          title: A
          candos: []
          title: B
      YAML
    end

    let(:duplicate_role_locale_yaml) do
      <<~YAML
        en:
          dup-role:
            title: one
          dup-role:
            title: two
      YAML
    end

    it 'import_candos= raises on a duplicate key rather than silently importing the last value' do
      expect { app.import_candos = duplicate_seed_candos_yaml }.to raise_error(/'title'/)
    end

    it 'locale_import_candos= raises on a duplicate cando key' do
      expect { app.locale_import_candos = duplicate_locale_yaml }.to raise_error(%r{spec-app/foo\.reader})
    end

    it 'import_roles= raises on a duplicate key inside a role entry' do
      expect { app.import_roles = duplicate_seed_roles_yaml }.to raise_error(/'title'/)
    end

    it 'locale_import_roles= raises on a duplicate key' do
      expect { app.locale_import_roles = duplicate_role_locale_yaml }.to raise_error(/dup-role/)
    end
  end
end
