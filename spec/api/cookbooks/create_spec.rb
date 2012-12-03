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
#

require 'pedant/rspec/cookbook_util'
require 'pedant/rspec/validations'

describe "Cookbooks API endpoint", :cookbooks do
  include Pedant::RSpec::CookbookUtil

  def self.ruby?
    Pedant::Config.ruby_cookbook_endpoint?
  end

  context "PUT /cookbooks/<name>/<version> [create]" do
    include Pedant::RSpec::Validations::Create
    let(:request_method){:PUT}
    let(:request_url){api_url("/cookbooks/#{cookbook_name}/#{cookbook_version}")}
    shared(:requestor){admin_user}


    # Start using the new validation macros
    context "when validating", :pending => ruby? do
      
      let(:cookbook_name) { "cookbook_name" }
      let(:cookbook_version) { "1.2.3" }

      let(:resource_url){api_url("/cookbooks/#{cookbook_name}/#{cookbook_version}")}
      let(:default_resource_attributes){ new_cookbook(cookbook_name, cookbook_version)}
      let(:persisted_resource_response){ get(resource_url, requestor) }
      
      after(:each){ delete_cookbook(requestor, cookbook_name, cookbook_version)}

      context "the 'json_class' field" do
        let(:validate_attribute){"json_class"}
        accepts_valid_value "Chef::CookbookVersion"
        rejects_invalid_value "Chef::Node"
      end

      rejects_invalid_keys

    end

    context "creating broken cookbooks to test validation and defaults" do
      let(:cookbook_name) { "cookbook_name" }
      let(:cookbook_version) { "1.2.3" }

      malformed_constraint = "s395dss@#"

      context "basic tests" do
        after(:each) do
          delete_cookbook(admin_user, cookbook_name, cookbook_version)
        end

        if (ruby?)
          should_fail_to_create('json_class', :delete, 400, "You didn't pass me a valid object!")
          create_should_crash_server('json_class', 'Chef::Role')
          should_fail_to_create('metadata', {}, 400,
                                "You said the cookbook was version 0.0.0, " +
                                 "but the URL says it should be 1.2.3.")
        else
          should_create('json_class', :delete, true, 'Chef::CookbookVersion')
          should_fail_to_create('json_class', 'Chef::Role', 400, "Field 'json_class' invalid")
          should_fail_to_create('metadata', {}, 400, "Field 'metadata.version' missing")
        end
      end # context basic tests

      context "checking segments" do
        %w{resources providers recipes definitions libraries attributes
           files templates root_files}.each do |segment|

          if (ruby?)
            create_should_crash_server(segment, "foo")
            should_fail_to_create(segment, [ {} ], 400,
                                  "Manifest has checksum  (path ) but " +
                                   "it hasn't yet been uploaded")
          else
            should_fail_to_create(segment, "foo", 400,
                                  "Field '#{segment}' invalid")
            should_fail_to_create(segment, [ {} ], 400,
                                  "Invalid element in array value of '#{segment}'.")
          end
        end
      end # context checking segments

      context "checking metadata sections" do
        %w{platforms dependencies recommendations suggestions conflicting
           providing replacing}.each do |section|

          if (ruby?)
            # Some of these work, some of these crash, none of these are worth the
            # trouble of testing separately -- in all cases, behavior is undesirable
          else
            should_fail_to_create_metadata(section, "foo", 400, "Field 'metadata.#{section}' invalid")
            should_fail_to_create_metadata(section, {"foo" => malformed_constraint},
                                           400, "Invalid value '#{malformed_constraint}' for metadata.#{section}")
          end
        end
      end # context checking metadata sections

      context 'with invalid version in url' do
        let(:expected_response) { invalid_cookbook_version_response }
        let(:url) { named_cookbook_url }
        let(:payload) { {} }
        let(:cookbook_version) { 'abc' }

        it "should respond with an error" do
          put(url, admin_user, :payload => payload) do |response|
            response.should look_like expected_response
          end
        end # it invalid version in URL is a 400
      end # with invalid version in url

      it "invalid cookbook name in URL is a 400" do
        payload = {}
        put(api_url("/cookbooks/first@second/1.2.3"), admin_user,
            :payload => payload) do |response|
          error = ruby? ? "You didn't pass me a valid object!" :
            "Invalid cookbook name 'first@second' using regex: 'Malformed cookbook name. Must only contain A-Z, a-z, 0-9, _ or -'."
          response.should look_like({
                                      :status => 400,
                                      :body => {
                                        "error" => [error]
                                      }
                                    })
        end
      end # it invalid cookbook name in URL is a 400

      it "mismatched metadata.cookbook_version is a 400" do
        payload = new_cookbook(cookbook_name, "0.0.1")
        put(api_url("/cookbooks/#{cookbook_name}/#{cookbook_version}"), admin_user,
            :payload => payload) do |response|
          error = ruby? ? "You said the cookbook was version 0.0.1, " +
                           "but the URL says it should be 1.2.3." :
            "Field 'name' invalid"
          response.should look_like({
                                      :status => 400,
                                      :body => {
                                        "error" => [error]
                                      }
                                    })
        end
      end # it mismatched metadata.cookbook_version is a 400

      it "mismatched cookbook_name is a 400" do
        payload = new_cookbook("foobar", cookbook_version)
        put(api_url("/cookbooks/#{cookbook_name}/#{cookbook_version}"), admin_user,
            :payload => payload) do |response|
          error = ruby? ? "You said the cookbook was named foobar, " +
                           "but the URL says it should be cookbook_name." :
            "Field 'name' invalid"
          response.should look_like({
                                      :status => 400,
                                      :body => {
                                        "error" => [error]
                                      }
                                    })
        end
      end # it mismatched cookbook_name is a 400

      context "sandbox checks" do
        after(:each) do
          delete_cookbook(admin_user, cookbook_name, cookbook_version)
        end
        it "specifying file not in sandbox is a 400" do
          payload = new_cookbook(cookbook_name, cookbook_version)
          payload["recipes"] = [
                                {
                                  "name" => "default.rb",
                                  "path" => "recipes/default.rb",
                                  "checksum" => "8288b67da0793b5abec709d6226e6b73",
                                  "specificity" => "default"
                                }
                               ]
          put(api_url("/cookbooks/#{cookbook_name}/#{cookbook_version}"),
              admin_user, :payload => payload) do |response|
            error = if ruby?
                       "Manifest has checksum 8288b67da0793b5abec709d6226e6b73 " +
                          "(path recipes/default.rb) but it hasn't yet been uploaded"
                    else
                      "Manifest has a checksum that hasn't been uploaded."
                    end
            response.should look_like({
                                        :status => 400,
                                        :body => {
                                          "error" => [error]
                                        }
                                      })
          end
        end # it specifying file not in sandbox is a 400
      end # context sandbox checks
    end # context creating broken cookbooks to test validation and defaults

    context "creating good cookbooks to test defaults" do
      let(:cookbook_name) { "cookbook_name" }
      let(:cookbook_version) { "1.2.3" }

      let(:description) { "my cookbook" }
      let(:long_description) { "this is a great cookbook" }
      let(:maintainer) { "This is my name" }
      let(:maintainer_email) { "cookbook_author@example.com" }
      let(:license) { "MPL" }

      let (:opts) {
        {
          :description => description,
          :long_description => long_description,
          :maintainer => maintainer,
          :maintainer_email => maintainer_email,
          :license => license
        }
      }

      after :each do
        delete_cookbook(admin_user, cookbook_name, cookbook_version)
      end

      if erlang?
        respects_maximum_payload_size
      end

      it "allows creation of a minimal cookbook with no data" do
        payload = minimal_cookbook(cookbook_name, cookbook_version)
        put(api_url("/cookbooks/#{cookbook_name}/#{cookbook_version}"),
            admin_user,
            :payload => payload) do |response|
          response.
            should look_like({
                               :status => ruby? ? 200 : 201,
                               :body => minimal_response(cookbook_name, cookbook_version)
                             })
        end
      end # it allows creation of a minimal cookbook with no data

      it "allows override of defaults" do
        payload = new_cookbook(cookbook_name, cookbook_version, opts)
        put(api_url("/cookbooks/#{cookbook_name}/#{cookbook_version}"),
            admin_user, :payload => payload) do |response|
          response.
            should look_like({
                               :status => ruby? ? 200 : 201,
                               :body => full_cookbook(cookbook_name, cookbook_version,
                                                      opts)
                             })
        end
      end # it allows override of defaults
    end # context creating good gookbooks to test defaults
  end # context PUT /cookbooks/<name>/<version> [create]

  context "PUT multiple cookbooks" do
    let(:cookbook_name) { "multiple_versions" }
    let(:cookbook_version1) { "1.2.3" }
    let(:cookbook_version2) { "1.3.0" }

    after :all do
      [cookbook_version1, cookbook_version2].each do |v|
        delete(api_url("/cookbooks/#{cookbook_name}/#{v}"), admin_user)
      end
    end

    it "allows us to create 2 versions of the same cookbook" do
      payload = new_cookbook(cookbook_name, cookbook_version1, {})
      put(api_url("/cookbooks/#{cookbook_name}/#{cookbook_version1}"),
        admin_user,
        :payload => payload) do |response|
        response.should look_like({
            :status => if ruby? then 200 else 201 end,
            :body => payload
          })
      end

      payload2 = new_cookbook(cookbook_name, cookbook_version2, {})
      put(api_url("/cookbooks/#{cookbook_name}/#{cookbook_version2}"),
        admin_user,
        :payload => payload2) do |response|
        response.should look_like({
            :status => if ruby? then 200 else 201 end,
            :body => payload2
          })
      end

      get(api_url("/cookbooks/#{cookbook_name}/#{cookbook_version1}"),
        admin_user) do |response|
        response.should look_like({
                                   :status => 200,
                                   :body_exact => payload
                                  })
      end

      get(api_url("/cookbooks/#{cookbook_name}/#{cookbook_version2}"),
        admin_user) do |response|
        response.should look_like({
                                   :status => 200,
                                   :body_exact => payload2
                                  })
      end
    end # it allows us to create 2 versions of the same cookbook
  end # context PUT multiple cookbooks
end # describe Cookbooks API endpoint