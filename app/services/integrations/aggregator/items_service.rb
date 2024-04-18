# frozen_string_literal: true

module Integrations
  module Aggregator
    class ItemsService < BaseService
      LIMIT = 300
      MAX_SUBSEQUENT_REQUESTS = 10

      def action_path
        "v1/#{provider}/items"
      end

      def call
        @cursor = ''
        @items = []

        ActiveRecord::Base.transaction do
          MAX_SUBSEQUENT_REQUESTS.times do |i|
            response = http_client.get(headers:, params:)

            handle_items(response['records'])
            @cursor = response['next_cursor']

            break if cursor.blank?
          end
        end
        result.items = items

        result
      end

      private

      attr_reader :cursor, :items

      def headers
        {
          'Connection-Id' => integration.connection_id,
          'Authorization' => "Bearer #{secret_key}",
          'Provider-Config-Key' => provider,
        }
      end

      def handle_items(new_items)
        @items = items.concat(new_items)

        # TODO: Store items in DB
      end

      def params
        {
          limit: LIMIT,
          cursor:,
        }
      end
    end
  end
end
