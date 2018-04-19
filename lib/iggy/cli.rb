#
# Author:: Matt Ray (<matt@chef.io>)
#
# Copyright:: 2018, Chef Software, Inc <legal@chef.io>
#

require "iggy"

require "inspec"
require "json"
require "thor"

class Iggy::CLI < Thor
  def self.exit_on_failure?
    true
  end

  map %w{-v --version} => "version"

  desc "version", "Display version information", hide: true
  def version
    say("Iggy v#{Iggy::VERSION}")
  end

  class_option :debug,
    :desc    => "Verbose debugging messages",
    :type    => :boolean,
    :default => false

  option :file,
    :aliases => "-f",
    :desc    => "Specify path to the input file",
    :default => "terraform.tfstat"

  option :profile,
    :aliases => "-p",
    :desc    => "Name of profile to generate",
    :default => "iggy"

  desc "terraform [options]", "Convert a Terraform file into an InSpec compliance profile"
  def terraform
    Iggy::Log.level = :debug if options[:debug]
    Iggy::Log.debug "terraform profile = #{options[:profile]}"

    # hash of generated controls
    @generated_controls = {}
    # hash of tagged compliance profiles
    @compliance_profiles = {}

    # read in the terraform.tfstate
    parse_terraform(options[:file])

    Iggy::Log.debug "terraform @generated_controls = #{@generated_controls}"
    Iggy::Log.debug "terraform @compliance_profiles = #{@compliance_profiles}"
    # generate profile
    exit 0
  end

  private
  def parse_terraform(file)
    Iggy::Log.debug "parse_terraform file = #{file}"
    begin
      unless File.file?(file)
        STDERR.puts "ERROR: #{file} is an invalid file, please check your path."
        exit(-1)
      end
      tfstate = JSON.parse(File.read(file))
    rescue JSON::ParserError => e
      STDERR.puts e.message
      STDERR.puts "ERROR: Parsing error in #{file}."
      exit(-1)
    end

    # find all the InSpec resources available
    inspec_resources = Inspec::Resource.registry.keys

    # iterate over the resources
    # this is hard-coded, I expect tfstate files are not homogeneous as the example
    resources = tfstate['modules'][0]['resources']
    resources.keys.each do |tf_resource|
      tf_res_type = resources[tf_resource]['type']

      # does this match an InSpec resource?
      if inspec_resources.include?(tf_res_type)
        Iggy::Log.debug "parse_terraform tf_res_type = #{tf_res_type} MATCH"
        tf_res_id = resources[tf_resource]['primary']['id']
        # insert new control based off the resource's ID
        @generated_controls[tf_res_id] = {}
        @generated_controls[tf_res_id]["name"] = "#{tf_res_type}::#{tf_res_id}"
        @generated_controls[tf_res_id]["impact"] = "1.0"
        @generated_controls[tf_res_id]["title"] = "Iggy #{File.basename(file)} #{tf_res_type}::#{tf_res_id}"
        @generated_controls[tf_res_id]["desc"] = "#{tf_res_type}::#{tf_res_id} from the source file #{File.absolute_path(file)}\nGenerated by Iggy v#{Iggy::VERSION}"
        @generated_controls[tf_res_id]["describe"] = {}
        @generated_controls[tf_res_id]["describe"]["resource"] = tf_res_type
        @generated_controls[tf_res_id]["describe"]["parameter"] = tf_res_id
        @generated_controls[tf_res_id]["describe"]["tests"] = []
        @generated_controls[tf_res_id]["describe"]["tests"][0] = "it { should exist }"
        # if there's a match, see if there are matching InSpec properties
        resources[tf_resource]['primary']['attributes'].keys.each do |attr|
          # not sure how to do this yet
          # @generated_controls[tf_res_id]["describe"]["tests"].append()
        end
      else
        Iggy::Log.debug "parse_terraform tf_res_type = #{tf_res_type} SKIP"
      end

      # is there a tagged profile attached?
      if resources[tf_resource]["primary"]["attributes"]["tags.compliance_profile"]
        # this is probably drastically lacking. What machines are we checking?
        @compliance_profiles[tf_res_id] = resources[tf_resource]["primary"]["attributes"]["tags.compliance_profile"]
      end
    end
  end

end
