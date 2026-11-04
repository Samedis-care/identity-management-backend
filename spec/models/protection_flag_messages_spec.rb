require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#3627. A refused delete of a predefined or
# write-protected record answered "System protection flag set" in every locale: a hard-coded message
# behind the attribute name. Clients show it to the user (e.g. the access profiles' delete error in
# samedis.care), so it has to be a sentence in the request's locale.
RSpec.describe 'protection flag messages' do # rubocop:disable RSpec/DescribeClass -- covers Actor, Role and User alike
  expected = {
    en: ['Predefined records cannot be deleted.',
         'Write-protected records cannot be changed.'],
    de: ['Vordefinierte Datensätze können nicht gelöscht werden.',
         'Schreibgeschützte Datensätze können nicht geändert werden.'],
    fr: ['Les enregistrements prédéfinis ne peuvent pas être supprimés.',
         'Les enregistrements protégés en écriture ne peuvent pas être modifiés.'],
    nl: ['Vooraf gedefinieerde records kunnen niet worden verwijderd.',
         'Schrijfbeveiligde records kunnen niet worden gewijzigd.'],
    ru: ['Предопределённые записи нельзя удалить.',
         'Записи, защищённые от изменений, нельзя изменить.']
  }

  [Actors::Group, Role, User].each do |klass|
    expected.each do |locale, (system_message, write_protected_message)|
      it "renders #{klass}'s refusals as a #{locale} sentence without the attribute name" do
        record = klass.new
        record.errors.add :system, :protected
        record.errors.add :write_protected, :protected

        messages = I18n.with_locale(locale) { record.errors.full_messages }

        expect(messages).to eq([system_message, write_protected_message])
      end
    end
  end

  context 'when a predefined group is soft-deleted' do
    let(:sfx) { SecureRandom.hex(4) }
    let!(:tenant) { Actors::Tenant.create!(name: "protection-flag-#{sfx}") }
    let!(:organization) { Actors::Organization.create!(name: "org#{sfx}", parent: tenant) }
    let!(:tenant_profiles) { Actors::Ou.create!(name: 'tenant_profiles', parent: organization) }
    let!(:group) { Actors::Group.create!(name: "system-#{sfx}", parent: tenant_profiles, system: true) }

    after do
      Actor.where(:parent_ids.in => [tenant.id]).delete_all
      tenant.delete
    end

    def refusal_in(locale)
      group.deleted = true
      I18n.with_locale(locale) do
        group.save(validate: false)
        group.errors.to_a
      end
    end

    it 'refuses with the message of the current locale' do
      expect(refusal_in(:de)).to eq(['Vordefinierte Datensätze können nicht gelöscht werden.'])
    end
  end
end
