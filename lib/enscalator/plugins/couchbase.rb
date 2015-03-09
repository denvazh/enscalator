module Enscalator
  module Couchbase
    def couchbase_init(db_name)
      @couchbase_mapping ||=
        mapping 'AWSCouchbaseAMI', {
        :'us-east-1' => { :amd64 => 'ami-403b4328' },
        :'us-west-2' => { :amd64 => 'ami-c398c6f3' },
        :'us-west-1' => { :amd64 => 'ami-1a554c5f' },
        :'eu-west-1' => { :amd64 => 'ami-8129aaf6' },
        :'ap-southeast-1' => { :amd64 => 'ami-88745fda' },
        :'ap-northeast-1' => { :amd64 => 'ami-6a7b676b' },
        :'sa-east-1' => { :amd64 => 'ami-59229f44' }
      }

      parameter "Couchbase#{db_name}KeyName",
        :Description => 'Name of the ssh key pair',
        :Type => 'String',
        :MinLength => '1',
        :MaxLength => '64',
        :AllowedPattern => '[a-zA-Z][a-zA-Z0-9]*',
        :ConstraintDescription => 'must begin with a letter and contain only alphanumeric characters.'

      parameter_allocated_storage "Couchbase#{db_name}",
        default: 5,
        min: 5,
        max: 1024

      parameter_instance_class "Couchbase#{db_name}", default: 'm1.medium',
        allowed_values: %w(m1.medium m1.large m1.xlarge m2.xlarge
                              m2.2xlarge m2.4xlarge c1.medium c1.xlarge
                              cc1.4xlarge cc2.8xlarge cg1.4xlarge)

      instance_vpc("Couchbase#{db_name}",
                   find_in_map('AWSCouchbaseAMI', ref('AWS::Region'), 'amd64'),
                   ref_resource_subnet_a,
                   [ref_private_security_group, ref_resource_security_group],
                   dependsOn:[], properties: {
                     :KeyName => ref("Couchbase#{db_name}KeyName"),
                     :InstanceType => ref("Couchbase#{db_name}InstanceClass")
                   })

    end
  end
end
