require 'rails_helper'

RSpec.describe Role, type: :model do
  let(:app_name) { 'test_app' }
  let(:app) { Actors::App.create(name: app_name) }
  let(:role_name) { 'test_role' }
  let(:role_name2) { 'test_role2' }
  let(:cando_reader) { "#{app_name}/cando.reader" }
  let(:cando_writer) { "#{app_name}/cando.writer" }

  describe 'validations' do
    it 'requires a name' do
      role = Role.new(actors_app: app)
      expect(role.valid?).to be_falsey
      expect(role.errors[:name]).to include("can't be blank")
    end

    it 'requires a unique name' do
      Role.create(name: 'test_role', app: app_name)
      role = Role.new(name: 'test_role', app: app_name)
      expect(role.valid?).to be_falsey
      expect(role.errors[:name]).to include('is already taken')
    end
  end

  describe 'associations' do
    it 'belongs to an app' do
      role = Role.new(name: role_name)
      expect(role.actors_app).to be_nil
      role.app = app_name
      expect(role.app).to eq(app_name)
    end

    it 'has and belongs to many functionalities' do
      functionality1 = Functionality.create(cando: cando_reader)
      functionality2 = Functionality.create(cando: cando_writer)
      role = Role.create(name: role_name, app: app_name, functionalities: [functionality1, functionality2])
      expect(role.functionalities).to include(functionality1, functionality2)
    end
  end

  describe 'callbacks' do
    it 'sets the title and description before validation' do
      role = Role.new(name: role_name, app: app_name)
      role.valid?
      expect(role.title).to eq(role_name)
      expect(role.description).to eq(role_name)
    end

    it 'prevents write-protected roles from being saved' do
      role = Role.create(name: role_name2, app: app_name, write_protected: true)
      role.description += "CHANGED"
      expect(role.save).to be_falsey
      expect(role.errors[:write_protected]).to include('protection flag set')
    end

    it 'prevents system-protected roles from being destroyed' do
      role = Role.create(name: 'test_role', actors_app: app, system: true)
      expect { role.destroy }.not_to change(Role, :count)
      expect(role.errors[:system]).to include('protection flag set')
    end
  end

  describe 'methods' do
    it 'returns the list of candos' do
      functionality1 = Functionality.create(cando: cando_reader)
      functionality2 = Functionality.create(cando: cando_writer)
      role = Role.create(name: 'test_role', actors_app: app, functionalities: [functionality1, functionality2])
      expect(role.candos).to eq([cando_reader, cando_writer])
    end

    it 'returns the seed dump hash' do
      role = Role.create(name: role_name, app: app_name, title: 'Test Role', description: 'This is a test role')
      expect(role.seed_dump).to eq({
        'app' => app_name,
        'name' => role_name,
        'title' => 'Test Role',
        'description' => 'This is a test role',
        'candos' => []
      })
    end

    it 'returns the locale dump hash' do
      I18n.with_locale(:de) do
        role = Role.create(name: role_name, app: app_name, title: 'Test-Rolle', description: 'Dies ist eine Test-Rolle')
        expect(role.locale_dump).to eq({
          'de' => {
            'test_role' => {
              'title' => 'Test-Rolle',
              'description' => 'Dies ist eine Test-Rolle'
            }
          }
        })
      end
    end
  end
end