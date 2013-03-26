# Copyright: Copyright (c) 2012 Opscode, Inc.
# License: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Pedant

  ################################################################################
  # URL Generation and Authorized HTTP Request Helpers
  ################################################################################
  module Request
    require 'rest_client'
    require 'mixlib/shellout'
    include Pedant::JSON

    # Grab the the version of Chef / Knife that's on the box in order
    # to properly set the X-Chef-Version header
    KNIFE_VERSION = begin
                      # Don't want Bundler to poison the shelling out :(
                      cmd = Mixlib::ShellOut.new("knife --version", :environment => {
                                                   'BUNDLE_GEMFILE' => nil,
                                                   'BUNDLE_BIN_PATH' => nil,
                                                   'GEM_PATH' => nil,
                                                   'GEM_HOME' => nil,
                                                   'RUBYOPT' => nil
                                                 })
                      cmd.run_command
                      cmd.stdout =~ /^Chef: (.*)$/
                      $1 || raise("Cannot determine Chef version from output of `knife --version`: #{cmd.stdout}")
                    end

    # Headers that are added to all requests
    def standard_headers
      {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        'User-Agent' => 'chef-pedant rspec tests',
        'X-Chef-Version' => KNIFE_VERSION,
        'X-Ops-Darklaunch' => x_darklaunch_header
      }
    end

    def x_darklaunch_header
      @_x_darklaunch_header ||= x_darklaunch_features.to_a.map { |k,v| "#{k}=#{v}" }.join(';')
    end

    X_DARKLAUNCH_ALL_ERLANG =
      { couchdb_checksums:    false,
        couchdb_clients:      false,
        couchdb_cookbooks:    false,
        couchdb_environments: false,
        couchdb_roles:        false,
        couchdb_data:         false  }

    X_DARKLAUNCH_ALL_RUBY =
      { couchdb_checksums:    true,
        couchdb_clients:      true,
        couchdb_cookbooks:    true,
        couchdb_environments: true,
        couchdb_roles:        true,
        couchdb_data:         true   }

    # If it is set to nil, then do not explicitly set darklaunch headers
    def x_darklaunch_features
      case Pedant::Config.couchdb
      when true  then X_DARKLAUNCH_ALL_RUBY
      when false then X_DARKLAUNCH_ALL_ERLANG
      else {}
      end
    end


    # Execute an authenticated request against a Chef Server
    #
    # `method` is an HTTP verb, as an uppercase symbol, e.g., :GET
    #
    # `url` is the complete URL for the request
    #
    # `requestor` is an instance of Pedant::Requestor, and represents
    # the user or client that the request will be signed as.  This
    # object actually generates the signing headers for the request.
    #
    # `opts` is a hash of options that modify the request in some way.
    # The currently recognized keys and their effects are as follows:
    #
    # :headers => any additional headers you wish to have applied to the
    # request.  A collection of standard headers are applied to all
    # requests, but any ones specified here will supercede those (see
    # the `standard_headers` shared context method).  Note that
    # authentication headers are applied last, and thus have priority
    # over any headers set in this hash.
    #
    # :payload => the body of the request.  This is required for all PUT
    # and POST requests.  It should be given in its final form (i.e., as
    # a String, not a Ruby hash or anything else)
    #
    # :timestamp => the time of request signing.  If not supplied, the
    # current time is used.  This allows you to validate proper behavior
    # with expired requests.
    #
    # :auth_headers => the authorization headers to use (if any).
    #
    #
    # Finally, a block can be supplied to this method.  This block will
    # receive a single argument, the HTTP response (as a
    # RestClient::Response object).  Testing methods should use this to
    # carry out any validation tests of the response.
    def authenticated_request(method, url, requestor, opts={}, &validator)
      user_headers = opts[:headers] || {}
      payload_raw = opts[:payload] || ""

      payload = if payload_raw.class == Hash
                  to_json(payload_raw)
                else
                  payload_raw
                end

      auth_headers = opts[:auth_headers] || requestor.signing_headers(method, url, payload)
      final_headers = standard_headers.merge(auth_headers).merge(user_headers)

      response_handler = lambda{|response, request, result| response}

      response = if [:PUT, :POST].include? method
                   RestClient.send method.downcase, url, payload, final_headers, &response_handler
                 else
                   RestClient.send method.downcase, url, final_headers, &response_handler
                 end
      if block_given?
        yield(response)
      else
        response
      end
    end

    # Accessory methods for making requests a bit easier

    def get(url, requestor, opts={}, &validator)
      authenticated_request :GET, url, requestor, opts, &validator
    end

    def put(url, requestor, opts={}, &validator)
      authenticated_request :PUT, url, requestor, opts, &validator
    end

    def post(url, requestor, opts={}, &validator)
      authenticated_request :POST, url, requestor, opts, &validator
    end

    def delete(url, requestor, opts={}, &validator)
      authenticated_request :DELETE, url, requestor, opts, &validator
    end

  end
end
