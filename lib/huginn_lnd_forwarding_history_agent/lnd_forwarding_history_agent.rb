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

      `resolve_nodename` for the max result wanted

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
        'resolve_nodename' => 'false',
        'start_time' => '1',
        'debug' => 'false',
        'changes_only' => 'true',
        'expected_receive_period_in_days' => '2',
        'macaroon' => ''
      }
    end

    form_configurable :url, type: :string
    form_configurable :resolve_nodename, type: :boolean
    form_configurable :start_time, type: :string
    form_configurable :changes_only, type: :boolean
    form_configurable :macaroon, type: :string
    form_configurable :expected_receive_period_in_days, type: :string
    form_configurable :debug, type: :boolean

    def validate_options
      unless options['url'].present?
        errors.add(:base, "url is a required field")
      end

      unless options['start_time'].present?
        errors.add(:base, "start_time is a required field")
      end

      if options.has_key?('changes_only') && boolify(options['changes_only']).nil?
        errors.add(:base, "if provided, changes_only must be true or false")
      end

      if options.has_key?('resolve_nodename') && boolify(options['resolve_nodename']).nil?
        errors.add(:base, "if provided, resolve_nodename must be true or false")
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
      parsed = JSON.parse(response.body)

      if interpolated['debug'] == 'true'
        log "payload"
        log payload
      end

      if interpolated['resolve_nodename'] == 'true'
        log "fetching channels"
        channels = get_channels
      end
      if interpolated['changes_only'] == 'true'
        if payload.to_s != memory['last_status']
          if "#{memory['last_status']}" == ''
            parsed["forwarding_events"].each do |event|
              create_event payload: event
            end
          else
            last_status = memory['last_status'].gsub("=>", ": ")
            last_status = JSON.parse(last_status)
            parsed["forwarding_events"].each do |event|
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
                if interpolated['resolve_nodename'] == 'true'
                  channels['channels'].each do |channel|
                    if channel['chan_id'] == event['chan_id_in']
                      log "channel id found"
                      event['chan_id_in'] = get_alias(channel['remote_pubkey'])
                    end
                    if channel['chan_id'] == event['chan_id_out']
                      log "channel id found"
                      event['chan_id_out'] = get_alias(channel['remote_pubkey'])
                    end
                  end
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

    def get_channels
      uri = URI.parse("#{interpolated['url']}/v1/channels")
      request = Net::HTTP::Get.new(uri)
      request["Grpc-Metadata-Macaroon"] = "#{interpolated['macaroon']}"
      request.body = "{ \"active_only\": \"true\"}"

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
      return payload
    end

    def get_alias(nodeid)
      uri = URI.parse("https://1ml.com/node/#{nodeid}/json")
      request = Net::HTTP::Get.new(uri)
      request["Authority"] = "1ml.com"
      request["Cache-Control"] = "max-age=0"
      request["Upgrade-Insecure-Requests"] = "1"
      request["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36"
      request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9"
      request["Sec-Gpc"] = "1"
      request["Sec-Fetch-Site"] = "same-origin"
      request["Sec-Fetch-Mode"] = "navigate"
      request["Sec-Fetch-User"] = "?1"
      request["Sec-Fetch-Dest"] = "document"
      request["Referer"] = "https://1ml.com/node/#{nodeid}"
      request["Accept-Language"] = "fr,en-US;q=0.9,en;q=0.8"

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
      return payload['alias']
    end
  end
end
