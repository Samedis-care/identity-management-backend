require 'rails_helper'

RSpec.describe Functionality, type: :model do
  let(:app_name) { 'test_app' }
  let(:app) { Actors::App.create(name: app_name) }
  let(:cando_reader) { "#{app_name}/cando.reader" }
  let(:cando_writer) { "#{app_name}/cando.writer" }

  describe "validations" do
    it "required fields title and description autofilled from cando" do
      app.present?
      functionality = Functionality.new(description: "test", cando: cando_reader)
      expect(functionality).to be_valid
      expect(functionality.errors[:title]).not_to include("can't be blank")
      expect(functionality.errors[:description]).not_to include("can't be blank")
    end

    it "requires a module" do
      functionality = Functionality.new(title: "test", description: "test", ident: "test", app: app_name)
      expect(functionality).not_to be_valid
      expect(functionality.errors[:module]).to include("can't be blank")
    end

    it "requires an ident" do
      functionality = Functionality.new(title: "test", description: "test", module: "test", app: app_name)
      expect(functionality).not_to be_valid
      expect(functionality.errors[:ident]).to include("can't be blank")
    end

    it "requires an actors_app" do
      functionality = Functionality.new(title: "test", description: "test", module: "test", ident: "test")
      expect(functionality).not_to be_valid
      expect(functionality.errors[:actors_app]).to include("can't be blank")
    end

    it "requires a unique ident within app and module" do
      app.present?
      functionality1 = Functionality.create(title: "test", description: "test", module: "test", ident: "test", app: app_name)
      functionality2 = Functionality.new(title: "test", description: "test", module: "test", ident: "test", app: app_name)
      expect(functionality2).not_to be_valid
      expect(functionality2.errors[:ident]).to all(be_a(String))
    end
  end
end