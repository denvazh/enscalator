module Enscalator
  module Templates
    class CareerCardProductionRDS < Enscalator::EnAppTemplateDSL
      include RDS_Snapshot

      def tpl
        description 'Production RDS stack for Career Card'

        pre_run do
          magic_setup stack_name: 'enjapan-vpc',
                      region: @options[:region],
                      start_ip_idx: 32
        end

        rds_snapshot_init('cc-production-201503261040',
                          allocated_storage: 100,
                          multizone: 'true',
                          parameter_group: 'careercard-production-mysql',
                          instance_class: 'db.m3.large')

        post_run do
          region = @options[:region]
          stack_name = @options[:stack_name]
          client = Aws::CloudFormation::Client.new(region: region)
          cfn = Aws::CloudFormation::Resource.new(client: client)

          stack = wait_stack(cfn, stack_name)
          host = get_resource(stack, 'RDSEndpointAddress')

          upsert_dns_record(
              zone_name: 'enjapan.prod.',
              record_name: "rds.#{stack_name}.enjapan.prod.",
              type: 'CNAME', region: region, values: [host])
        end
      end
    end
  end
end

