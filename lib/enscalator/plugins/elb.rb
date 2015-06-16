module Enscalator
  module Plugins
    # Internet facing ELB instance
    module Elb

      # Create new ELB instance
      #
      # @param stack_name [String] must be stack name from @options[:stack_name]
      # @param region [String] must be region from @options[:region]
      # @param elb_name [String, Hash] ELB instance name - can be either String or Fn::Join
      # @param web_server_port [Integer] application port to which ELB redirects traffic
      # @param zone_name [String] zone name attached to the vpc
      # @return [String] ELB resource name
      def elb_init(stack_name,
                   region,
                   elb_name: join('-', aws_stack_name, 'elb'),
                   web_server_port: 9000,
                   zone_name: 'enjapan.local.',
                   ssl: false,
                   internal: true)

        @elb_resource_name = 'LoadBalancer'

        def vpc_id
          cfn = cfn_resource(cfn_client(region))
          stack = cfn.stack('enjapan-vpc')
          get_resource(stack, 'VpcId')
        end

        parameter 'WebServerPort',
                  :Description => 'TCP/IP Port for the web service',
                  :Default => web_server_port,
                  :Type => 'Number',
                  :MinValue => '0',
                  :MaxValue => '65535',
                  :ConstraintDescription => 'must be an integer between 0 and 65535.'


        security_group_vpc 'ELBSecurityGroup',
                         'Security group of the application servers',
                         vpc_id,
                         securityGroupIngress: [
                           {:IpProtocol => 'tcp',
                            :FromPort => '0',
                            :ToPort => '65535',
                            :CidrIp => '10.0.0.0/8'
                           }
                         ] + (!internal ? [
                           {:IpProtocol => 'tcp',
                            :FromPort => '80',
                            :ToPort => '80',
                            :CidrIp => '0.0.0.0/0'
                           },
                           {:IpProtocol => 'tcp',
                            :FromPort => '443',
                            :ToPort => '443',
                            :CidrIp => '0.0.0.0/0'
                           }
                         ] : []),
                         tags: {
                           'Name' => join('-', aws_stack_name, 'app', 'sg'),
                           'Application' => aws_stack_name
                         }


        if ssl
          parameter 'SSLCertificateId',
            :Description => 'Id of the SSL certificate (iam-servercertgetattributes -s certname)',
            :Type => 'String',
            :ConstraintDescription => 'must be a string'
        end

        subnets = -> {
          internal ? private_subnets : public_subnets
        }

        def private_subnets
          [ref_application_subnet_a, ref_application_subnet_c]
        end

        def public_subnets
          cfn = cfn_resource(cfn_client(region))
          stack = wait_stack(cfn, 'enjapan-vpc')
          [get_resource(stack, 'PublicSubnet1'), get_resource(stack, 'PublicSubnet2')]
        end

        resource @elb_resource_name,
                 :Type => 'AWS::ElasticLoadBalancing::LoadBalancer',
                 :Properties => {
                   :LoadBalancerName => elb_name,
                   :Listeners => [
                     {
                       :LoadBalancerPort => '80',
                       :InstancePort => ref('WebServerPort'),
                       :Protocol => 'HTTP',
                     },
                   ] + (ssl == false ? [] : [{:LoadBalancerPort => '443',
                                                          :InstancePort => ref('WebServerPort'),
                                                          :SSLCertificateId => ref('SSLCertificateId'),
                                                          :Protocol => 'HTTPS'}]),
                   :HealthCheck => {
                     :Target => join('', 'HTTP:', ref_web_server_port, '/'),
                     :HealthyThreshold => '3',
                     :UnhealthyThreshold => '5',
                     :Interval => '30',
                     :Timeout => '5',
                   },
                   :SecurityGroups => [ref('ELBSecurityGroup')],
                   :Subnets => subnets.(),
                   :Tags => [
                     {
                       :Key => 'Name',
                       :Value => elb_name
                     },
                     {
                       :Key => 'Application',
                       :Value => aws_stack_name
                     },
                     {:Key => 'Network', :Value => 'Private'},
                   ],
                 }.merge(internal ? {:Scheme => 'internal'} : {})

        resource 'WebServerPortSecurityGroupId', :Type => 'AWS::EC2::SecurityGroupIngress',
                 :Properties => {
                   :IpProtocol => 'tcp',
                   :FromPort => ref('WebServerPort'),
                   :ToPort => ref('WebServerPort'),
                   :GroupId => get_att('ApplicationSecurityGroup', 'GroupId')
                 }

        output 'LoadBalancerDnsName',
               :Description => 'LoadBalancer DNS Name',
               :Value => get_att('LoadBalancer', 'DNSName')

        post_run do
          cfn = cfn_resource(cfn_client(region))
          stack = wait_stack(cfn, stack_name)
          elb_name = get_resource(stack, 'LoadBalancerDnsName')
          upsert_dns_record(
            zone_name: zone_name,
            record_name: "elb.#{stack_name}.#{zone_name}",
            type: 'CNAME',
            values: [elb_name],
            region: region
          )
        end

        # return resource name
        @elb_resource_name
      end

    end # module Elb
  end # module Plugins
end # module Enscalator
