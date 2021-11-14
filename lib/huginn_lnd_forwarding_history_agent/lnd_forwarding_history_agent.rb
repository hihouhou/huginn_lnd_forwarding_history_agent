module Agents
  class LndForwardingHistoryAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The Lnd Forwarding History Agent fetches forward history event and creates event.

      `debug` is used to verbose mode.

      `url` for the lnd url like https://127.0.0.1:8080

      `num_max_events` for the max result wanted

      `start_time` is used for fetching since X days ago

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:
        {
          "timestamp": "XXXXXXXXXX",
          "chan_id_in": "XXXXXXXXXXXXXXXXXX",
          "chan_id_out": "XXXXXXXXXXXXXXXXXXXX
          "amt_in": "XXXX",
          "amt_out": "XXXX",
          "fee": "1",
          "fee_msat": "1001",
          "amt_in_msat": "XXXXXXX",
          "amt_out_msat": "XXXXXXX",
          "timestamp_ns": "XXXXXXXXXXXXXXXXXXX"
        }
    MD

    def default_options
      {
        'url' => '',
#        'num_max_events' => '10',
        'start_time' => '1',
        'debug' => 'false',
        'changes_only' => 'true',
        'expected_receive_period_in_days' => '2',
        'macaroon' => ''
      }
    end

    form_configurable :url, type: :string
#    form_configurable :num_max_events, type: :string
    form_configurable :start_time, type: :string
    form_configurable :changes_only, type: :boolean
    form_configurable :macaroon, type: :string
    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :debug, type: :boolean

    def validate_options
      unless options['url'].present?
        errors.add(:base, "url is a required field")
      end
#
#      unless options['num_max_events'].present?
#        errors.add(:base, "num_max_events is a required field")
#      end

      unless options['start_time'].present?
        errors.add(:base, "start_time is a required field")
      end

      if options.has_key?('changes_only') && boolify(options['changes_only']).nil?
        errors.add(:base, "if provided, changes_only must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['macaroon'].present?
        errors.add(:base, "macaroon is a required field")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def check
      fetch
    end

    private

    def fetch
      timestamp_wanted = Time.now.to_i - ( 86400 * interpolated['start_time'].to_i)
      uri = URI.parse("#{interpolated['url']}/v1/switch")
      request = Net::HTTP::Post.new(uri)
      request["Grpc-Metadata-Macaroon"] = "#{interpolated['macaroon']}"
#      request.body = "{ \"num_max_events\": #{interpolated['num_max_events']}}"
      request.body = "{ \"start_time\": \"#{timestamp_wanted}\"}"
      
      req_options = {
        use_ssl: uri.scheme == "https",
        verify_mode: OpenSSL::SSL::VERIFY_NONE,
      }
      
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log "request  status : #{response.code}"

      if interpolated['debug'] == 'true'
        log "response.body"
        log response.body
      end

      payload = JSON.parse(response.body)

      if interpolated['debug'] == 'true'
        log "payload"
        log payload
      end
      if interpolated['changes_only'] == 'true'
        if payload.to_s != memory['last_status']
          if "#{memory['last_status']}" == ''
             payload["forwarding_events"].each do |event|
               create_event payload: event
             end
          else
            last_status = memory['last_status'].gsub("=>", ": ")
            last_status = JSON.parse(last_status)
            payload["forwarding_events"].each do |event|
              found = false
              if interpolated['debug'] == 'true'
                log "found is #{found}!"
                log event
              end
              last_status["forwarding_events"].each do |eventbis|
                if event == eventbis
                  found = true
                end
                if interpolated['debug'] == 'true'
                  log "found is #{found}!"
                end
              end
              if found == false
                if interpolated['debug'] == 'true'
                  log "found is #{found}! so event created"
                  log event
                end
                create_event payload: event
              end
            end
          end
          memory['last_status'] = payload.to_s
        end
      else
        create_event payload: payload
        if payload.to_s != memory['last_status']
          memory['last_status'] = payload.to_s
        end
      end
    end
  end
end
