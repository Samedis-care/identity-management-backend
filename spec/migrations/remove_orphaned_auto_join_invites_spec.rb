require 'rails_helper'
require 'tmpdir'
require Rails.root.join('db/migrate_manual/20261014140000_remove_orphaned_auto_join_invites')

# Cover for the manual cleanup migration of Samedis-care/samedis-care-issues#3059. Everything
# is scoped to its own tenant via TENANT_ID so leftovers from other specs cannot matter, and
# the rows are written through the raw collection to control every field.
RSpec.describe RemoveOrphanedAutoJoinInvites do
  let(:sfx) { SecureRandom.hex(4) }
  # Invite#tenant_id is the foreign key of belongs_to :tenant, i.e. an ObjectId in real documents
  let(:tenant_oid) { BSON::ObjectId.new }
  let(:tenant_id) { tenant_oid.to_s }
  let(:export_at) { 1.day.ago.utc.change(usec: 0) }
  let(:tmp_dir) { Dir.mktmpdir('auto-join-spec') }
  let(:backup_path) { File.join(tmp_dir, 'removed.jsonl') }
  let(:keep_path) { File.join(tmp_dir, 'keep.txt') }
  let(:kept_token) { "kept-#{sfx}" }
  let(:output_io) { StringIO.new }

  after do
    Invite.collection.delete_many('tenant_id' => tenant_oid)
    FileUtils.remove_entry(tmp_dir)
  end

  def insert(token, **attrs)
    row = { '_id' => BSON::ObjectId.new, 'app' => 'samedis-care', 'tenant_id' => tenant_oid, 'invitable_type' => 'tenant',
            'invitable_id' => tenant_id, 'auto_accept' => true, 'done' => false, 'email' => "#{token}@auto-join.test",
            'token' => token, 'valid_until' => 6.months.from_now.utc, 'created_at' => 2.days.ago.utc }
    Invite.collection.insert_one(row.merge(attrs.transform_keys(&:to_s)))
    row['_id']
  end

  def exists?(id)
    Invite.collection.find('_id' => id).any?
  end

  def run(env = {})
    File.write(keep_path, "# SC export\n#{kept_token}\n\n") unless File.exist?(keep_path)
    base = { 'KEEP_FILE' => keep_path, 'EXPORT_AT' => export_at.iso8601, 'TENANT_ID' => tenant_id }
    stub_const('ENV', ENV.to_hash.merge(base.merge(env.transform_keys(&:to_s))))
    $stdout = output_io
    begin
      described_class.up
    ensure
      $stdout = STDOUT
    end
    output_io.string
  end

  let!(:orphan) { insert("orphan-#{sfx}") }
  let!(:kept) { insert(kept_token) }

  describe 'the dry run (no APPLY)' do
    it 'deletes nothing and raises so the version is not recorded as applied' do
      expect { run }.to raise_error(described_class::DryRunFinished)

      expect(exists?(orphan)).to be(true)
    end

    it 'reports what it would delete without printing a token' do
      expect { run }.to raise_error(described_class::DryRunFinished)

      expect(output_io.string).to include('dry run: would delete 1 invite(s)')
      expect(output_io.string).not_to include("orphan-#{sfx}")
      expect(output_io.string).not_to include(kept_token)
    end
  end

  describe 'the report' do
    it 'buckets the candidates by requested lifetime, so invites that do not look like SC\'s are visible' do
      insert("year-#{sfx}", created_at: 2.days.ago.utc, valid_until: (365.days.from_now - 2.days).utc)
      insert("default-#{sfx}", created_at: 2.days.ago.utc, valid_until: 28.days.from_now.utc)
      insert("odd-#{sfx}", created_at: 2.days.ago.utc, valid_until: 100.days.from_now.utc)
      expect { run }.to raise_error(described_class::DryRunFinished)

      expect(output_io.string).to include('about a year (SC staff auto-join pattern)', 'about 30 days (IM default)', 'other')
    end

    it 'lists the tenant with its candidate count' do
      expect { run }.to raise_error(described_class::DryRunFinished)

      expect(output_io.string).to match(/tenant=#{tenant_id}\s+candidates=\s*1 deleted=\s*0/)
    end
  end

  describe 'APPLY' do
    let(:apply) { { 'APPLY' => 'true', 'BACKUP_FILE' => backup_path } }

    it 'deletes the orphan and keeps the invite SC still references' do
      run(apply)

      expect(exists?(orphan)).to be(false)
      expect(exists?(kept)).to be(true)
    end

    it 'does not print any token' do
      output = run(apply)

      expect(output).not_to include("orphan-#{sfx}")
      expect(output).not_to include(kept_token)
      expect(output).to include('deleted 1 invite(s)')
    end

    it 'writes the deleted invite to the backup file before deleting, mode 0600, and nothing else' do
      run(apply)

      lines = File.readlines(backup_path).map { |line| BSON::ExtJSON.parse(line, mode: :bson) }
      expect(lines.map { |doc| doc['token'] }).to eq(["orphan-#{sfx}"])
      expect(File.stat(backup_path).mode & 0o777).to eq(0o600)
    end

    it 'writes a backup that restores a working invite (ObjectIds and Times survive)' do
      run(apply)
      expect(exists?(orphan)).to be(false)

      Invite.collection.insert_many(File.foreach(backup_path).map { |line| BSON::ExtJSON.parse(line, mode: :bson) }, ordered: false)

      restored = Invite.valid.where(_id: orphan).first
      expect(restored).not_to be_nil
      expect(restored.token).to eq("orphan-#{sfx}")
      expect(Invite.collection.find('_id' => orphan).first['tenant_id']).to be_a(BSON::ObjectId)
      expect(Invite.where(tenant_id: tenant_oid, token: "orphan-#{sfx}").count).to eq(1)
    end

    it 'only deletes what matches every condition' do
      untouched = {
        accepted: insert("accepted-#{sfx}", done: true),
        other_app: insert("other-app-#{sfx}", app: 'other-app'),
        other_type: insert("other-type-#{sfx}", invitable_type: 'app'),
        manual_invite: insert("manual-#{sfx}", auto_accept: false),
        expired: insert("expired-#{sfx}", valid_until: 1.day.ago.utc),
        after_export: insert("after-export-#{sfx}", created_at: 1.hour.ago.utc)
      }
      run(apply)

      expect(untouched.values.map { |id| exists?(id) }).to all(be(true))
    end

    it 'treats an old document without the done field as open' do
      id = BSON::ObjectId.new
      Invite.collection.insert_one('_id' => id, 'app' => 'samedis-care', 'tenant_id' => tenant_oid, 'invitable_type' => 'tenant',
                                   'auto_accept' => true, 'token' => "legacy-#{sfx}", 'valid_until' => 6.months.from_now.utc,
                                   'created_at' => 2.days.ago.utc)
      run(apply)

      expect(exists?(id)).to be(false)
    end

    it 'can be restored again after a partial restore, because ordered: false skips what is still there' do
      second = insert("orphan2-#{sfx}")
      run(apply)
      docs = File.foreach(backup_path).map { |line| BSON::ExtJSON.parse(line, mode: :bson) }
      Invite.collection.insert_many([docs.find { |doc| doc['_id'] == orphan }])

      expect { Invite.collection.insert_many(docs, ordered: false) }.to raise_error(Mongo::Error::BulkWriteError)
      expect(exists?(second)).to be(true)
    end

    it 'honours LIMIT' do
      third = insert("orphan3-#{sfx}")
      run(apply.merge('LIMIT' => '1'))

      survivors = [orphan, third].count { |id| exists?(id) }
      expect(survivors).to eq(1)
    end

    it 'is idempotent: a second run finds nothing more to delete' do
      run(apply)
      second_backup = File.join(tmp_dir, 'second.jsonl')

      expect(run(apply.merge('BACKUP_FILE' => second_backup))).to include('deleted 0 invite(s)')
      expect(File.read(second_backup)).to eq('')
      expect(exists?(kept)).to be(true)
    end

    it 'honours APP' do
      other = insert("other-app2-#{sfx}", app: 'other-app')
      run(apply.merge('APP' => 'other-app'))

      expect(exists?(other)).to be(false)
      expect(exists?(orphan)).to be(true)
    end
  end

  describe 'refusing to run' do
    it 'without KEEP_FILE' do
      stub_const('ENV', ENV.to_hash.merge('EXPORT_AT' => export_at.iso8601))
      expect { described_class.up }.to raise_error(ArgumentError, /KEEP_FILE is required/)
    end

    it 'without EXPORT_AT' do
      stub_const('ENV', ENV.to_hash.merge('KEEP_FILE' => keep_path))
      expect { described_class.up }.to raise_error(ArgumentError, /EXPORT_AT is required/)
    end

    it 'with an EXPORT_AT that is not ISO 8601' do
      stub_const('ENV', ENV.to_hash.merge('KEEP_FILE' => keep_path, 'EXPORT_AT' => 'yesterdayZ'))
      expect { described_class.up }.to raise_error(ArgumentError, /ISO 8601/)
    end

    it 'with a word instead of a time' do
      stub_const('ENV', ENV.to_hash.merge('KEEP_FILE' => keep_path, 'EXPORT_AT' => 'yesterday'))
      expect { described_class.up }.to raise_error(ArgumentError, /explicit offset/)
    end

    it 'with an EXPORT_AT without an offset, which would be read in the operator\'s local zone' do
      stub_const('ENV', ENV.to_hash.merge('KEEP_FILE' => keep_path, 'EXPORT_AT' => '2026-10-14T10:13:40'))

      expect { described_class.up }.to raise_error(ArgumentError, /explicit offset/)
    end

    it 'with an EXPORT_AT in the future' do
      stub_const('ENV', ENV.to_hash.merge('KEEP_FILE' => keep_path, 'EXPORT_AT' => 1.hour.from_now.utc.iso8601))

      expect { described_class.up }.to raise_error(ArgumentError, /in the future/)
    end

    it 'accepts an explicit offset other than Z' do
      File.write(keep_path, "#{kept_token}\n")
      stub_const('ENV', ENV.to_hash.merge('KEEP_FILE' => keep_path, 'TENANT_ID' => tenant_id,
                                          'EXPORT_AT' => export_at.in_time_zone('Europe/Berlin').iso8601))
      $stdout = output_io

      expect { described_class.up }.to raise_error(described_class::DryRunFinished)
    ensure
      $stdout = STDOUT
    end

    it 'with an empty keep list, which would delete every live invite' do
      File.write(keep_path, "# nothing\n\n")

      expect { run('APPLY' => 'true', 'BACKUP_FILE' => backup_path) }.to raise_error(ArgumentError, /refusing to run/)
      expect(exists?(orphan)).to be(true)
    end

    it 'with APPLY but no BACKUP_FILE' do
      expect { run('APPLY' => 'true') }.to raise_error(ArgumentError, /BACKUP_FILE is required/)
      expect(exists?(orphan)).to be(true)
    end

    it 'when the BACKUP_FILE already exists' do
      File.write(backup_path, 'previous run')

      expect { run('APPLY' => 'true', 'BACKUP_FILE' => backup_path) }.to raise_error(ArgumentError, /already exists/)
      expect(exists?(orphan)).to be(true)
    end

    it 'when MIN_KEEP is not a number, which to_i would turn into 0 and switch the guard off' do
      expect { run('MIN_KEEP' => 'abc') }.to raise_error(ArgumentError, /invalid value for Integer/)
      expect(exists?(orphan)).to be(true)
    end

    it 'when MIN_KEEP is not met' do
      expect { run('MIN_KEEP' => '5', 'APPLY' => 'true', 'BACKUP_FILE' => backup_path) }.to raise_error(ArgumentError, /MIN_KEEP=5/)
    end
  end

  it 'cannot be reverted' do
    expect { described_class.down }.to raise_error(Mongoid::IrreversibleMigration)
  end
end
