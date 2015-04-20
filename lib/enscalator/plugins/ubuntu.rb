require 'open-uri'

module Enscalator

  # Namespace for enscalator plugins
  module Plugins

    # Ubuntu appliance
    module Ubuntu

      class << self

        # Supported storage types in AWS
        STORAGE=[:'ebs', :'ebs-io1', :'ebs-ssd', :'instance-store']

        # Supported Ubuntu image architectures
        ARCH=[:amd64, :i386]

        # Supported Ubuntu releases
        RELEASE={
            :vivid => '15.04',
            :utopic => '14.10',
            :trusty => '14.04',
            :saucy => '13.10',
            :raring => '13.04',
            :quantal => '12.10',
            :precise => '12.04'
        }

        # Structure to hold parsed record
        Struct.new('Image', :name, :edition, :state, :timestamp, :root_storage, :arch, :region, :ami, :virtualization)

        # Get mapping for Ubuntu images
        #
        # @param release [Symbol, String] release codename or version number
        # @param storage [Symbol] storage kind
        # @param arch [Symbol] architecture
        # @raise [ArgumentError] if release is nil, empty or not one of supported values
        # @raise [ArgumentError] if storage is nil, empty or not one of supported values
        # @raise [ArgumentError] if arch is nil, empty or not one of supported values
        # @return [Hash] mapping for Ubuntu amis
        def get_mapping(release: :trusty, storage: :ebs, arch: :amd64)
          raise ArgumentError, 'release can be either codename or version' unless RELEASE.to_a.flatten.include? release
          raise ArgumentError, "storage can only be one of #{STORAGE.to_s}" unless STORAGE.include? storage
          raise ArgumentError, "arch can only be one of #{ARCH.to_s}" unless ARCH.include? arch
          begin
            version = RELEASE.keys.include?(release) ? release : RELEASE.key(release)
            body = open("https://cloud-images.ubuntu.com/query/#{version}/server/released.current.txt") { |f| f.read }
            body.split("\n").map { |m| m.squeeze("\t").split("\t").reject { |r| r.include? 'aki' } }
                .map { |l| Struct::Image.new(*l) }
                .select(&->(r) { r.root_storage == storage.to_s && r.arch == arch.to_s })
                .group_by(&:region)
                .map(&->(k, v) {
                       [
                           k,
                           v.map(&->(i) { [i.virtualization, i.ami] }).to_h
                       ]
                     }
                )
                .to_h
                .with_indifferent_access
          end
        end

      end # class << self

      # Create new Ubuntu instance
      #
      # @param instance_name [String] instance name
      # @param storage [String] storage kind (ebs or ephemeral)
      # @param arch [String] architecture (amd64 or i386)
      # @param instance_class [String] instance class (type)
      # @param allocate_public_ip [Boolean] automatically allocate public ip address
      def ubuntu_init(instance_name,
                      storage: :'ebs',
                      arch: :amd64,
                      instance_class: 'm1.medium',
                      allocate_public_ip: false)

        mapping 'AWSUbuntuAMI', Ubuntu.get_mapping(storage: storage, arch: arch)

        parameter_keyname "Ubuntu#{instance_name}"

        parameter_allocated_storage "Ubuntu#{instance_name}",
                                    default: 5,
                                    min: 5,
                                    max: 1024

        parameter_instance_class "Ubuntu#{instance_name}",
                                 default: instance_class,
                                 allowed_values: %w(m1.medium m1.large m1.xlarge m2.xlarge
                                                 m2.2xlarge m2.4xlarge c1.medium c1.xlarge
                                                 cc1.4xlarge cc2.8xlarge cg1.4xlarge)

        instance_vpc "Ubuntu#{instance_name}",
                     find_in_map('AWSUbuntuAMI', ref('AWS::Region'), 'hvm'),
                     ref_resource_subnet_a,
                     [ref_private_security_group, ref_resource_security_group],
                     dependsOn: [],
                     properties: {
                         :KeyName => ref("Ubuntu#{instance_name}KeyName"),
                         :InstanceType => ref("Ubuntu#{instance_name}InstanceClass")
                     }

        resource "Ubuntu#{instance_name}PublicIpAddress",
                 :Type => 'AWS::EC2::EIP',
                 :Properties => {
                     :InstanceId => ref("Ubuntu#{instance_name}")
                 } if allocate_public_ip
      end

    end # Ubuntu
  end # Plugins
end # Enscalator
