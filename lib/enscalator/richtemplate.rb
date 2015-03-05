require 'cloudformation-ruby-dsl/cfntemplate'

def rich_template(&block)
  Enscalator::RichTemplateDSL.new(&block)
end

module Enscalator
  class RichTemplateDSL < TemplateDSL
    def pre_run(&block)
      @pre_run_block ||= block if block_given?
      @pre_run_block.call if @pre_run_block
    end

    def post_run(&block)
      return @post_run_block ||= block if block_given?
      @post_run_block.call if @post_run_block
    end
    
    def get_dns_records(zone_name: nil, region: 'us-east-1')
      client = Aws::Route53::Client.new(region: region)
      zone = client.list_hosted_zones[:hosted_zones].select{|x| x.name == zone_name}.first
      records = client.list_resource_record_sets(hosted_zone_id: zone.id)
      records.values.flatten.map{|x| {name: x.name, type: x.type, records: x.resource_records.map(&:value)} if x.is_a?(Aws::Structure)}.compact
    end

    def upsert_dns_record(zone_name: nil, record_name: nil, type: 'A', region: 'us-east-1', values: [])
      client = Aws::Route53::Client.new(region: region)
      zone = client.list_hosted_zones[:hosted_zones].select{|x| x.name == zone_name}.first

      client.change_resource_record_sets(
        hosted_zone_id: zone.id,
        change_batch: {
          comment: "dns record for #{record_name}",
          changes: [
            {
              action: "UPSERT",
              resource_record_set: {
                name: record_name,
                type: type,
                resource_records: values.map{|x| {value: x}},
                ttl: 300
              }
            }
          ]
        }
      )
    end

    def tags_to_properties(tags)
      tags.map { |k,v| {:Key => k, :Value => v}}
    end

    def description(desc)
      value :Description => desc
    end

    def vpc(name, cidr, enableDnsSupport:nil, enableDnsHostnames:nil, dependsOn:[], tags:{})
      properties = {
        :CidrBlock => cidr,
      }
      properties[:EnableDnsSupport] = enableDnsSupport unless enableDnsSupport.nil?
      properties[:EnableDnsHostnames] = enableDnsHostnames unless enableDnsHostnames.nil?
      unless tags.include?('Name')
        tags['Name'] = join('-', aws_stack_name, name)
      end
      properties[:Tags] = tags_to_properties(tags)
      options = {
        :Type => 'AWS::EC2::VPC',
        :Properties => properties
      }
      options[:DependsOn] = dependsOn unless dependsOn.empty?
      resource name, options
    end


    def subnet(name, vpc, cidr, availabilityZone:'', dependsOn:[], tags:{})
      properties = {
        :VpcId => vpc,
        :CidrBlock => cidr,
      }
      properties[:AvailabilityZone] = availabilityZone unless availabilityZone.empty?
      unless tags.include?('Name')
        tags['Name'] = join('-', aws_stack_name, name)
      end
      properties[:Tags] = tags_to_properties(tags)

      options = {
        :Type => 'AWS::EC2::Subnet',
        :Properties => properties
      }
      options[:DependsOn] = dependsOn unless dependsOn.empty?
      resource name, options
    end


    def security_group(name, description, securityGroupEgress:[], securityGroupIngress:[], dependsOn:[], tags:{})
      properties = {
        :GroupDescription => description
      }
      properties[:SecurityGroupIngress] = securityGroupIngress unless securityGroupIngress.empty?
      properties[:SecurityGroupEgress] = securityGroupEgress unless securityGroupEgress.empty?
      unless tags.include?('Name')
        tags['Name'] = join('-', aws_stack_name, name)
      end
      properties[:Tags] = tags_to_properties(tags)
      options = {
        :Type => 'AWS::EC2::SecurityGroup',
        :Properties => properties
      }
      options[:DependsOn] = dependsOn unless dependsOn.empty?
      resource name, options
    end

    def security_group_vpc(name, description, vpc, securityGroupEgress:[], securityGroupIngress:[], dependsOn:[], tags:{})
      properties = {
        :VpcId => vpc,
        :GroupDescription => description
      }
      properties[:SecurityGroupIngress] = securityGroupIngress unless securityGroupIngress.empty?
      properties[:SecurityGroupEgress] = securityGroupEgress unless securityGroupEgress.empty?
      unless tags.include?('Name')
        tags['Name'] = join('-', aws_stack_name, name)
      end
      properties[:Tags] = tags_to_properties(tags)
      options = {
        :Type => 'AWS::EC2::SecurityGroup',
        :Properties => properties
      }
      options[:DependsOn] = dependsOn unless dependsOn.empty?
      resource name, options
    end

    def network_interface(device_index, options:{})
      options[:DeviceIndex] = device_index
      options
    end

    def instance(name, image_id, subnet, security_groups, dependsOn:[], properties:{})
      raise "Non VPC instance #{name} can not contain NetworkInterfaces" if properties.include?(:NetworkInterfaces)
      raise "Non VPC instance #{name} can not contain VPC SecurityGroups" if properties.include?(:SecurityGroupIds)

    end

    def parameter_allocated_storage(instance_name, default: 5, min: 5, max: 1024)
      parameter "#{instance_name}AllocatedStorage",
        :Default => default.to_s,
        :Description => "The size of the #{instance_name} (Gb)",
        :Type => 'Number',
        :MinValue => min.to_s,
        :MaxValue => max.to_s,
        :ConstraintDescription => "must be between #{min} and #{max}Gb."
    end

    def parameter_instance_class(instance_name, default: 't2.micro', allowed_values:[])
      allowed = allowed_values.any? ? allowed_values :
        %w(t1.micro t2.micro t2.small t2.medium m1.small m1.medium
                   m1.large m1.xlarge m2.xlarge m2.2xlarge m2.4xlarge m3.medium
                   m3.large m3.xlarge m3.2xlarge c1.medium c1.xlarge c3.large
                   c3.xlarge c3.2xlarge c3.4xlarge c3.8xlarge c4.large c4.xlarge
                   c4.2xlarge c4.4xlarge c4.8xlarge g2.2xlarge r3.large r3.xlarge
                   r3.2xlarge r3.4xlarge r3.8xlarge i2.xlarge i2.2xlarge i2.4xlarge
                   i2.8xlarge hi1.4xlarge hs1.8xlarge cr1.8xlarge cc2.8xlarge cg1.4xlarge)

      parameter "#{instance_name}InstanceClass",
        :Default => default,
        :Description => "The #{instance_name} instance type",
        :Type => 'String',
        :AllowedValues => allowed,
        :ConstraintDescription => "must select a valid #{instance_name} instance type."
    end

    def instance_vpc(name, image_id, subnet, security_groups, dependsOn:[], properties:{})
      raise "VPC instance #{name} can not contain NetworkInterfaces and subnet or security_groups" if properties.include?(:NetworkInterfaces)
      raise "VPC instance #{name} can not contain non VPC SecurityGroups" if properties.include?(:SecurityGroups)
      properties[:ImageId] = image_id
      properties[:SubnetId] = subnet
      properties[:SecurityGroupIds] = security_groups
      if properties[:Tags] && !properties[:Tags].any?{|x| x[:Key] == 'Name'}
        properties[:Tags] += {:Key => 'Name', :Value => join('-', aws_stack_name, name)}
      end
      options = {
        :Type => 'AWS::EC2::Instance',
        :Properties => properties
      }

      options[:DependsOn] = dependsOn unless dependsOn.empty?
      resource name, options
    end

    def instance_with_network(name, image_id, network_interfaces, properties:{})
      raise "Instance with NetworkInterfaces #{name} can not contain instance subnet or security_groups" if ([:SubnetId, :SecurityGroups, :SecurityGroupIds] & properties).any?
      properties[:ImageId] = image_id
      properties[:NetworkInterfaces] = network_interfaces
      if properties[:Tags] &&  !properties[:Tags].any?{|x| x[:Key] == 'Name'}
        properties[:Tags] += {:Key => 'Name', :Value => join('-', aws_stack_name, name)}
      end
      options = {
        :Type => 'AWS::EC2::Instance',
        :Properties => properties
      }
      options[:DependsOn] = dependsOn unless dependsOn.empty?
      resource name, options
    end

    def parameter(name, options)
      default(:Parameters, {})[name] = options
      @parameters[name] ||= options[:Default]
      class_eval do
        define_method :"ref_#{name.underscore}" do
          ref(name)
        end
      end
    end

    def method_missing(m, *args, &block)
      if m =~ /\Aref_/
        name = m.to_s.scan(/\Aref_(.*)/).flatten.first
        ref(name.camelize)
      end
    end

    def exec!()
      cfn_cmd_2(self)
      post_run
    end

    def cfn_cmd_2(template)
      action = ARGV[0]
      unless %w(expand diff validate create-stack update-stack).include? action
        $stderr.puts "usage: #{$PROGRAM_NAME} <expand|diff|validate|create-stack|update-stack>"
        exit(2)
      end
      unless (ARGV & %w(--template-body --template-url)).empty?
        $stderr.puts "#{File.basename($PROGRAM_NAME)}:  The --template-body and --template-url command-line options are not allowed."
        exit(2)
      end

      # Find parameters where extension attribute :Immutable is true then remove it from the
      # cfn template since we can't pass it to CloudFormation.
      immutable_parameters = template.excise_parameter_attribute!(:Immutable)

      # Tag CloudFormation stacks based on :Tags defined in the template
      cfn_tags = template.excise_tags!
      # The command line string looks like: --tag "Key=key, Value=value" --tag "Key2=key2, Value2=value"
      cfn_tags_options = cfn_tags.sort.map { |tag| ["--tag", "Key=%s, Value=%s" % tag.split('=')] }.flatten

      # example: <template.rb> cfn-create-stack my-stack-name --parameters "Env=prod" --region eu-west-1
      # Execute the AWS CLI cfn-cmd command to validate/create/update a CloudFormation stack.
      if action == 'diff' or (action == 'expand' and not template.nopretty)
        template_string = JSON.pretty_generate(template)
      else
        template_string = JSON.generate(template)
      end

      if action == 'expand'
        # Write the pretty-printed JSON template to stdout and exit.  [--nopretty] option writes output with minimal whitespace
        # example: <template.rb> expand --parameters "Env=prod" --region eu-west-1 --nopretty
        if template.nopretty
          puts template_string
        else
          puts template_string
        end
        exit(true)
      end

      temp_file = File.absolute_path("#{$PROGRAM_NAME}.expanded.json")
      File.write(temp_file, template_string)

      cmdline = ['aws', 'cloudformation'] + ARGV + ['--template-body', 'file://' + temp_file] + cfn_tags_options
      cfn_params, cmdline = extract_options(cmdline, %w(), %w(--parameters))
      if cfn_params.count > 1
        cfn_params = cfn_params.drop(1).first.split(';').map {|x| key, val = x.split('='); {'ParameterKey' => key, 'ParameterValue' => val}}
        cmdline = cmdline + ['--parameters', cfn_params.to_json]
      end

      # Add the required default capability if no capabilities were specified
      cmdline = cmdline + ['--capabilities', 'CAPABILITY_IAM'] if not ARGV.include?('--capabilities') or ARGV.include?('-c')

      case action
      when 'diff'
        # example: <template.rb> diff my-stack-name --parameters "Env=prod" --region eu-west-1
        # Diff the current template for an existing stack with the expansion of this template.

        # The --parameters and --tag options were used to expand the template but we don't need them anymore.  Discard.
        _, cfn_options = extract_options(ARGV[1..-1], %w(), %w(--parameters --tag))

        # Separate the remaining command-line options into options for 'cfn-cmd' and options for 'diff'.
        cfn_options, diff_options = extract_options(cfn_options, %w(),
                                                    %w(--stack-name --region --parameters --connection-timeout -I --access-key-id -S --secret-key -K --ec2-private-key-file-path -U --url))

        # If the first argument is a stack name then shift it from diff_options over to cfn_options.
        if diff_options[0] && !(/^-/ =~ diff_options[0])
          cfn_options.unshift(diff_options.shift)
        end

        # Run CloudFormation commands to describe the existing stack
        cfn_options_string           = cfn_options.map { |arg| "'#{arg}'" }.join(' ')
        old_template_raw             = exec_capture_stdout("aws cloudformation get-template #{cfn_options_string}")
        # ec2 template output is not valid json: TEMPLATE  "<json>\n"\n
        old_template_object          = JSON.parse(old_template_raw[11..-3])
        old_template_string          = JSON.pretty_generate(old_template_object)
        old_stack_attributes         = exec_describe_stack(cfn_options_string)
        old_tags_string              = old_stack_attributes["TAGS"]
        old_parameters_string        = old_stack_attributes["PARAMETERS"]

        # Sort the tag strings alphabetically to make them easily comparable
        old_tags_string = (old_tags_string || '').split(';').sort.map { |tag| %Q(TAG "#{tag}"\n) }.join
        tags_string     = cfn_tags.sort.map { |tag| "TAG \"#{tag}\"\n" }.join

        # Sort the parameter strings alphabetically to make them easily comparable
        old_parameters_string = (old_parameters_string || '').split(';').sort.map { |param| %Q(PARAMETER "#{param}"\n) }.join
        parameters_string     = template.parameters.sort.map { |key, value| "PARAMETER \"#{key}=#{value}\"\n" }.join

        # Diff the expanded template with the template from CloudFormation.
        old_temp_file = File.absolute_path("#{$PROGRAM_NAME}.current.json")
        new_temp_file = File.absolute_path("#{$PROGRAM_NAME}.expanded.json")
        File.write(old_temp_file, old_tags_string + old_parameters_string + old_template_string)
        File.write(new_temp_file, tags_string + parameters_string + template_string)

        # Compare templates
        system(*["diff"] + diff_options + [old_temp_file, new_temp_file])

        File.delete(old_temp_file)
        File.delete(new_temp_file)

        exit(true)

      when 'validate-template'
        # The validate-template command doesn't support --parameters so remove it if it was provided for template expansion.
        _, cmdline = extract_options(cmdline, %w(), %w(--parameters --tag))

      when 'update-stack'
        # Pick out the subset of cfn-update-stack options that apply to cfn-describe-stacks.
        cfn_options, other_options = extract_options(ARGV[1..-1], %w(),
                                                     %w(--stack-name --region --connection-timeout -I --access-key-id -S --secret-key -K --ec2-private-key-file-path -U --url))

        # If the first argument is a stack name then shift it over to cfn_options.
        if other_options[0] && !(/^-/ =~ other_options[0])
          cfn_options.unshift(other_options.shift)
        end

        # Run CloudFormation command to describe the existing stack
        cfn_options_string = cfn_options.map { |arg| "'#{arg}'" }.join(' ')
        old_stack_attributes = exec_describe_stack(cfn_options_string)

        # If updating a stack and some parameters are marked as immutable, fail if the new parameters don't match the old ones.
        if not immutable_parameters.empty?
          old_parameters_string = old_stack_attributes["PARAMETERS"]
          old_parameters = Hash[(old_parameters_string || '').split(';').map { |pair| pair.split('=', 2) }]
          new_parameters = template.parameters

          immutable_parameters.sort.each do |param|
            if old_parameters[param].to_s != new_parameters[param].to_s
              $stderr.puts "Error: update-stack may not update immutable parameter " +
                "'#{param}=#{old_parameters[param]}' to '#{param}=#{new_parameters[param]}'."
              exit(false)
            end
          end
        end

        # Tags are immutable in CloudFormation.  The cfn-update-stack command doesn't support --tag options, so remove
        # the argument (if it exists) and validate against the existing stack to ensure tags haven't changed.
        # Compare the sorted arrays for an exact match
        old_cfn_tags = old_stack_attributes['TAGS'].split(';').sort rescue [] # Use empty Array if .split fails
        if cfn_tags != old_cfn_tags
          $stderr.puts "CloudFormation stack tags do not match and cannot be updated. You must either use the same tags or create a new stack." +
            "\n" + (old_cfn_tags - cfn_tags).map {|tag| "< #{tag}" }.join("\n") +
            "\n" + "---" +
            "\n" + (cfn_tags - old_cfn_tags).map {|tag| "> #{tag}"}.join("\n")
          exit(false)
        end
        _, cmdline = extract_options(cmdline, %w(), %w(--tag))
      end

      # Execute command cmdline
      unless system(*cmdline)
        $stderr.puts "\nExecution of 'aws cloudformation' failed.  To facilitate debugging, the generated JSON template " +
          "file was not deleted.  You may delete the file manually if it isn't needed: #{temp_file}"
        exit(false)
      end

      File.delete(temp_file)
    end
  end
end
