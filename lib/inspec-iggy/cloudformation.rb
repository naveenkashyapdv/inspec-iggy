#
# Author:: Matt Ray (<matt@chef.io>)
#
# Copyright:: 2018, Chef Software, Inc <legal@chef.io>
#

require 'inspec/objects/control'
require 'inspec/objects/ruby_helper'
require 'inspec/objects/describe'

require 'inspec-iggy/inspec_helper'

module Iggy
  class CloudFormation
    def self.parse_generate(file) # rubocop:disable all
      Inspec::Log.debug "CloudFormation.parse_generate file = #{file}"
      begin
        unless File.file?(file)
          STDERR.puts "ERROR: #{file} is an invalid file, please check your path."
          exit(-1)
        end
        template = JSON.parse(File.read(file))
      rescue JSON::ParserError => e
        STDERR.puts e.message
        STDERR.puts "ERROR: Parsing error in #{file}."
        exit(-1)
      end
      basename = File.basename(file)
      absolutename = File.absolute_path(file)

      # InSpec controls generated
      generated_controls = []
      # iterate over the resources
      cfn_resources = template['Resources']
      cfn_resources.keys.each do |cfn_res|
        # split out the last ::, these are all AWS
        cfn_resource = cfn_resources[cfn_res]['Type'].split('::').last
        # split camelcase and join with underscores
        cfn_res_type = 'aws_' + cfn_resource.split(/(?=[A-Z])/).join('_').downcase

        # add translation layer
        if InspecHelper::TRANSLATED_RESOURCES.key?(cfn_res_type)
          Inspec::Log.debug "CloudFormation.parse_generate cfn_res_type = #{cfn_res_type} #{InspecHelper::TRANSLATED_RESOURCES[cfn_res_type]} TRANSLATED"
          cfn_res_type = InspecHelper::TRANSLATED_RESOURCES[cfn_res_type]
        end

        # does this match an InSpec resource?
        if InspecHelper::RESOURCES.include?(cfn_res_type)
          Inspec::Log.debug "CloudFormation.parse_generate cfn_res_type = #{cfn_res_type} MATCH"

          # insert new control based off the resource's ID
          ctrl = Inspec::Control.new
          ctrl.id = "#{cfn_res_type}::#{cfn_res}"
          ctrl.title = "Iggy #{basename} #{cfn_res_type}::#{cfn_res}"
          ctrl.desc = "#{cfn_res_type}::#{cfn_res} from the source file #{absolutename}\nGenerated by Iggy v#{Iggy::VERSION}"
          ctrl.impact = '1.0'

          describe = Inspec::Describe.new
          # describes the resource with the logical_resource_id as argument, replaced at inspec exec
          describe.qualifier.push([cfn_res_type, "resources[#{cfn_res}]"])

          # ensure the resource exists
          describe.add_test(nil, 'exist', nil)

          # EC2 instances should be running
          describe.add_test(nil, 'be_running', nil) if cfn_res_type.eql?('aws_ec2_instance')

          # if there's a match, see if there are matching InSpec properties
          inspec_properties = Iggy::InspecHelper.resource_properties(cfn_res_type)
          cfn_resources[cfn_res]['Properties'].keys.each do |attr|
            # insert '_' on the CamelCase to get camel_case
            attr_split = attr.split(/(?=[A-Z])/)
            property = attr_split.join('_').downcase
            if inspec_properties.member?(property)
              Inspec::Log.debug "CloudFormation.parse_generate #{cfn_res_type} inspec_property = #{property} MATCH"
              value = cfn_resources[cfn_res]['Properties'][attr]
              if (value.is_a? Hash) || (value.is_a? Array)
                #  these get replaced at inspec exec
                if property.eql?('vpc_id') # rubocop:disable Metrics/BlockNesting
                  vpc = cfn_resources[cfn_res]['Properties'][attr].values.first
                  # https://github.com/inspec/inspec/issues/3173
                  describe.add_test(property, 'eq', "resources[#{vpc}]") unless cfn_res_type.eql?('aws_route_table') # rubocop:disable Metrics/BlockNesting
                  # AMI is a Ref into Parameters
                elsif property.eql?('image_id') # rubocop:disable Metrics/BlockNesting
                  amiref = cfn_resources[cfn_res]['Properties'][attr].values.first
                  ami = template['Parameters'][amiref]['Default']
                  describe.add_test(property, 'eq', ami)
                end
              else
                describe.add_test(property, 'eq', value)
              end
            else
              Inspec::Log.debug "CloudFormation.parse_generate #{cfn_res_type} inspec_property = #{property} SKIP"
            end
          end
          ctrl.add_test(describe)
          generated_controls.push(ctrl)
        else
          Inspec::Log.debug "CloudFormation.parse_generate cfn_res_type = #{cfn_res_type} SKIP"
        end
      end
      Inspec::Log.debug "CloudFormation.parse_generate generated_controls = #{generated_controls}"
      generated_controls
    end
  end
end
