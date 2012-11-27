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

module RSpec
  module Matchers

    # Determines if a given [key, value] array matches a map.
    # Processing is different depending on the class of the value.
    # Used in the `look_like` matcher; see documentation of that for
    # more.
    def have_entry(expected)
      PedanticMapEntryEquals.new(expected)
    end

    class PedanticMapEntryEquals
      def initialize(expectation)
        @expectation = expectation
      end

      def matches?(target)
        @target = target

        @k = @expectation[0]
        @v = @expectation[1]

        @actual = @target[@k]

        if @v.class == Regexp
          @actual =~ @v
        elsif @v.class == Array
          # We don't really care about the order, just the contents
          begin
            @actual.sort == @v.sort
          rescue
            # If the items cannot be sorted (e.g. Hashes), look for
            # them one by one.  This requires you to specify the EXACT
            # item!
            #
            # So far, this appears to be mainly of use for verifying
            # search results.
            #
            # NOTE: If the items are Hashes, they must be exact matches!
            #
            # TODO: If we start testing against very large search
            # results, this should be revisited, as this becomes very
            # inefficient.

            # might have recieved back nil as the result
            # need to cut short the rest of the logic to provide a
            # better message
            if @actual.nil?
              return false
            end

            size_is_same = (@actual.size == @v.size)
            all_items_included = @v.all? { |item| @actual.include?(item) }
            size_is_same && all_items_included
          end
        elsif @v.class == Hash
          @v.reduce(true){|val, kv|
            val && PedanticMapEntryEquals.new(kv).matches?(@actual)
          }
        else
          @actual == @v
        end
      end

      def description
        "respond with exact keys"
      end

      def failure_message_for_should
        "'#{@k}' should match '#{@v}', but we got '#{@actual}' instead."
      end
    end
  end
end


RSpec::Matchers.define :have_status_code do |code|
  match do |response|
    if code.respond_to?(:any?)
      code.any?{|c| response.code == c }
    else
      response.code == code
    end
  end

  codes = Pedant::RSpec::HTTP::STATUS_CODES

  description do
    "respond with #{code} #{codes[code]}"
  end

  failure_message_for_should do |response|
    "Response should have HTTP status code #{code} ('#{codes[code]}'), but it was actually #{response.code} ('#{codes[response.code]}')"
  end
end

RSpec::Matchers.define :have_error_message do |message|
  match do |response|
    parse(response)["error"] == message
  end

  description do
    "respond with error message '#{message}'"
  end
end

RSpec::Matchers.define :have_error do |code, message|
  match do |response|
    response.code == code && parse(response) == { "error" => [message] }
  end

  codes = Pedant::RSpec::HTTP::STATUS_CODES

  description do
    "respond with #{code} #{codes[code]} and an error message of '#{message}'"
  end

  failure_message_for_should do |response|
    <<-EOM
1) HTTP status code should have been #{code} ('#{codes[code]}'); it was #{response.code}.

2) The response should have contained the error message

       #{message}

   Instead, the entire response body was

       #{response}

EOM
  end
end

# Test various aspects of an HTTP response.  The response will be
# compared to an "expected response spec", which is a hash that
# describes the various tests that should be run.  Currently a
# response spec can have the following keys (all are optional):
#
# :status => Value is the integer HTTP status code the response should
#     have
#
# :body => A map of string keys to expected values that a JSON-encoded
#     body should have.  Only the keys specified are matched; the test
#     makes no assumptions about keys that are not listed.  A value
#     can be a string or number literal, or a regular expression (which
#     the expected value should match).
#
# :body_exact => same as :body, but all keys are expected to be
#     present.  That is, if there are keys in the body that you do not
#     specify in your test, the test will fail.
#
# :body_raw => does no JSON parsing of the body, and instead does a
#     raw string match
#
# :headers => a map of header names and expected values.  Only tests
#     the specified headers, and makes no assumptions about
#     unspecified headers.

RSpec::Matchers.define :look_like do |expected_response_spec|
  include ::Pedant::JSON

  match do |response|
    begin
      last_matcher, last_should = RSpec::Matchers.last_matcher, RSpec::Matchers.last_should
      things_to_check = expected_response_spec.keys
      json_tests = [:body, :body_exact]

      # Test the HTTP Status Code, if given
      if expected_response_spec[:status]
        response.should have_status_code expected_response_spec[:status]
      end

      # If you want to check the raw, unprocessed body for some
      # reason.  Mainly useful for asserting a response has a
      # completely empty body.
      if expected_response_spec[:body_raw]
        response.should eq expected_response_spec[:body_raw]
      end

      # Test the headers
      if expected_response_spec[:headers]
        headers = expected_response_spec[:headers]
        actual_headers = response.raw_headers
        headers.each do |header, value|
          actual_headers[header].should eq value
        end
      end

      if not (things_to_check & json_tests).empty? # '&' = intersection
        # Only parse the body as JSON if we're going to test it as
        # JSON.  While all the "normal" calls to the API should return
        # non-empty JSON bodies, some calls may not (such as trying to
        # use a non-allowed HTTP method and getting a 405 response
        # back with an empty body).  In cases like that, trying to
        # parse an empty body will result in an error.
        parsed_json = parse(response)

        expected_body_spec = expected_response_spec[:body] || expected_response_spec[:body_exact]
        expected_body_spec.class.should == Hash

        # :body_exact implies that there should be no keys that are
        # untested, i.e., you test everything that's there
        if expected_response_spec[:body_exact]
          parsed_json.keys.sort.should == expected_body_spec.keys.sort
        end

        expected_body_spec.each do |kv|
          parsed_json.should have_entry kv
        end
      end

      # if we get down here without throwing an exception, we pass!
      # Reset last matchers and should to this one
      RSpec::Matchers.last_matcher, RSpec::Matchers.last_should = last_matcher, last_should
      true
    rescue RSpec::Expectations::ExpectationNotMetError => e
      @error_message = e.message
      # fail the overall matcher
      false
    end
  end

  description do
    code = expected_response_spec[:status]
    "respond with #{code} #{Pedant::RSpec::HTTP::STATUS_CODES[code]}"
  end

  failure_message_for_should do |response|
    @error_message
  end
end


# Knife Matchers

# 'outcome_spec' is a hash with any of the keys :status, :stdout, or
# :stderr.  The value of :status, if given, should be the integer exit
# status of the executed command.  :stdout and :stderr, if given, are
# regular expressions that should match the respective stream's
# output.

RSpec::Matchers.define :have_outcome do |outcome_spec|
  match do |executed_shellout_command|
    valid_keys =  [:status, :stdout, :stderr]
    if outcome_spec.keys & valid_keys == []
      throw "You did not specify values for any of #{valid_keys}!"
    end

    status = outcome_spec[:status] ? (executed_shellout_command.exitstatus == outcome_spec[:status]) : true
    stdout = outcome_spec[:stdout] ? (executed_shellout_command.stdout =~ outcome_spec[:stdout]) : true
    stderr = outcome_spec[:stderr] ? (executed_shellout_command.stderr =~ outcome_spec[:stderr]) : true
    status && stdout && stderr
  end

  # Could just spit out `executed_shellout_command.inspect`, but I
  # find the formatting suboptimal for testing error messages.
  failure_message_for_should do |executed_shellout_command|
    "Executed command should have matched the outcome spec #{outcome_spec.inspect}, but it didn't!\n
\tFailed Command: #{executed_shellout_command.command}\n
\tCommand Setting: #{Pedant::Knife.command_setting(executed_shellout_command).inspect}\n
\tExit Status: #{executed_shellout_command.exitstatus}\n
\tStandard Output:\n
#{executed_shellout_command.stdout}\n
\tStandard Error:\n
#{executed_shellout_command.stderr}"
  end

end
