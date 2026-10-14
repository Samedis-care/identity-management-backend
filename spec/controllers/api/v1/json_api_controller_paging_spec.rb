require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#2994: page[number] and
# page[padding] were read with .to_i.abs and no ceiling, so a value beyond int64 became a
# Bignum, the skip derived from it overflowed what BSON can serialize and the find command
# raised RangeError -- HTTP 500 for what is merely a nonsensical page number.
#
# Follows the in-repo convention for controller specs (see
# spec/controllers/api/v1/user/account_logins_controller_spec.rb): instantiate a concrete
# controller and drive the real private readers.
RSpec.describe Api::V1::JsonApiController, 'paging params' do
  subject(:controller_instance) { Api::V1::EmailBlacklistController.new }

  let(:beyond_int64) { (10**20).to_s }
  let(:params) { {} }

  before do
    without_partial_double_verification do
      allow(controller_instance).to receive(:params_json_api).and_return(params.with_indifferent_access)
    end
  end

  def page_number
    controller_instance.send(:page_number)
  end

  def page_padding
    controller_instance.send(:page_padding)
  end

  describe '#page_number' do
    context 'with a value beyond int64' do
      let(:params) { { page: { number: beyond_int64 } } }

      it 'is clamped to PAGE_NUMBER_MAX' do
        expect(page_number).to eq(described_class::PAGE_NUMBER_MAX)
      end

      it 'can be paginated without raising' do
        expect { Actor.paginate(per_page: 25, page: page_number).to_a }.not_to raise_error
      end
    end

    context 'with the legacy bare page param' do
      let(:params) { { page: beyond_int64 } }

      it 'is clamped as well' do
        expect(page_number).to eq(described_class::PAGE_NUMBER_MAX)
      end
    end

    context 'with a large but representable value' do
      let(:params) { { page: { number: '1000000' } } }

      it 'is kept' do
        expect(page_number).to eq(1_000_000)
      end
    end

    context 'with zero' do
      let(:params) { { page: { number: '0' } } }

      it 'still floors at 1' do
        expect(page_number).to eq(1)
      end
    end

    context 'with non-numeric input' do
      let(:params) { { page: { number: 'abc' } } }

      it 'falls back to 1' do
        expect(page_number).to eq(1)
      end
    end
  end

  describe '#page_padding' do
    context 'with a value beyond int64' do
      let(:params) { { page: { padding: beyond_int64 } } }

      it 'is clamped to PAGE_PADDING_MAX' do
        expect(page_padding).to eq(described_class::PAGE_PADDING_MAX)
      end

      it 'can be paginated without raising' do
        expect { Actor.paginate(per_page: 25, page: 1, padding: page_padding).to_a }.not_to raise_error
      end
    end

    context 'with a representable value' do
      let(:params) { { page: { padding: '10' } } }

      it 'is kept' do
        expect(page_padding).to eq(10)
      end
    end

    context 'with non-numeric input' do
      let(:params) { { page: { padding: 'abc' } } }

      it 'defaults to 0' do
        expect(page_padding).to eq(0)
      end
    end
  end

  it 'keeps the largest skip any controller can request far below int64' do
    largest_limit = described_class.descendants.filter_map { |c| c.const_get(:PAGE_LIMIT_MAX) if c.name }.max
    skip = (described_class::PAGE_NUMBER_MAX - 1) * largest_limit + described_class::PAGE_PADDING_MAX

    expect(skip).to be < 2**62
  end
end
