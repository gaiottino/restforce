require 'restforce/concerns/verbs'

module Restforce
  module Concerns
    module BatchAPI
      extend Restforce::Concerns::Verbs

      define_verbs :post

      def batch(halt_on_error: false, &block)
        subrequests = Subrequests.new(options)
        yield(subrequests)
        subrequests.requests.each_slice(25).map do |requests|
          properties = {
            batchRequests: requests,
            haltOnError: halt_on_error
          }

          started_at = Time.now.to_i
          json = properties.to_json
          Rails.logger.info "$$$ Payload '#{json}'" if defined?(Rails)
          response = post('/services/apexrest/composite/batch', json)
          ended_at = Time.now.to_i
          Rails.logger.info "$$$ Restforce (#{ended_at - started_at}s) batch #{requests.length} requests" if defined?(Rails)

          body = response.body
          results = body['results']
          if halt_on_error && body['hasErrors']
            last_error_index = results.rindex { |result| result['statusCode'] != 412 }
            last_error = results[last_error_index]
            last_error_result = last_error['result'][0]
            raise BatchAPIError, "#{last_error_result['errorCode']} #{last_error_result['message']}"
          end
          results.map(&:compact)
        end.flatten
      end

      def batch!(&block)
        batch(halt_on_error: true, &block)
      end

      class Subrequests
        def initialize(options)
          @options = options
          @requests = []
        end
        attr_reader :options, :requests

        def create(sobject, attrs)
          requests << { method: 'POST', url: batch_api_path(sobject), richInput: attrs }
        end

        def update(sobject, attrs)
          id = attrs.fetch(attrs.keys.find { |k, v| k.to_s.downcase == 'id' }, nil)
          raise ArgumentError, 'Id field missing from attrs.' unless id
          attrs_without_id = attrs.reject { |k, v| k.to_s.downcase == "id" }
          requests << { method: 'PATCH', url: batch_api_path("#{sobject}/#{id}"), richInput: attrs_without_id }
        end

        def destroy(sobject, id)
          requests << { method: 'DELETE', url: batch_api_path("#{sobject}/#{id}") }
        end

      private

        def batch_api_path(path)
          "v#{options[:api_version]}/sobjects/#{path}"
        end
      end
    end
  end
end
