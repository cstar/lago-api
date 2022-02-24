# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::RegisterUser, type: :graphql do
  let(:mutation) do
    <<~GQL
      mutation($input: RegisterUserInput!) {
        registerUser(input: $input) {
          user {
            id
            email
          }
          organization {
            id
            name
          }
          membership {
            id
          }
        }
      }
    GQL
  end

  it 'returns user, organization and membership' do
    result = execute_graphql(
      query: mutation,
      variables: {
        input: {
          email: 'foo@bar.com',
          password: 'ILoveLago',
          organizationName: 'FooBar'
        }
      }
    )

    aggregate_failures do
      expect(result['data']['registerUser']['membership']['id']).to be_present
      expect(result['data']['registerUser']['user']['email']).to eq('foo@bar.com')
      expect(result['data']['registerUser']['organization']['name']).to eq('FooBar')
    end
  end

  context 'with already existing user' do
    it 'returns an error' do
      user = create(:user)

      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            email: user.email,
            password: 'ILoveLago',
            organizationName: 'FooBar'
          }
        }
      )

      aggregate_failures do
        expect_graphql_error(
          result: result,
          message: :user_already_exists
        )
      end
    end
  end
end
