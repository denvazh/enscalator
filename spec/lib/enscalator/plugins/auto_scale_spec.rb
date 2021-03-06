require 'spec_helper'

describe Enscalator::Plugins::AutoScale do
  let(:app_name) { 'auto_scale_test' }
  let(:description) { 'This is test template for auto scale group' }
  let(:image_id) { 'ami-0123456a' }

  describe '#auto_scale_init' do
    context 'when invoked with default parameters' do
      let(:template_name) { app_name.humanize.delete(' ') }
      let(:template_fixture) do
        as_test_app_name = app_name
        as_test_description = description
        as_test_image_id = image_id
        as_test_template_name = template_name
        gen_richtemplate(as_test_template_name,
                         Enscalator::EnAppTemplateDSL,
                         [described_class]) do
          @app_name = as_test_app_name
          value(Description: as_test_description)
          mock_availability_zones
          auto_scale_init(as_test_image_id)
        end
      end

      it 'generates valid template with default values' do
        cmd_opts = default_cmd_opts(template_fixture.name, template_fixture.name.underscore)
        as_template = template_fixture.new(cmd_opts)
        dict = as_template.instance_variable_get(:@dict)

        launch_config_resource_name = "#{template_name}LaunchConfig"
        auto_scale_resource_name = "#{template_name}AutoScale"

        expect(dict[:Resources].keys).to include(*[launch_config_resource_name, auto_scale_resource_name])
        test_autoscale = dict[:Resources][auto_scale_resource_name]
        expect(test_autoscale[:Type]).to eq('AWS::AutoScaling::AutoScalingGroup')
        expect(test_autoscale[:Properties][:LaunchConfigurationName]).to eq(Ref: launch_config_resource_name)
        default_tag = { Key: 'Name', Value: auto_scale_resource_name, PropagateAtLaunch: true }
        expect(test_autoscale[:Properties][:Tags]).to include(default_tag)
        test_launchconfig = dict[:Resources][launch_config_resource_name]
        expect(test_launchconfig[:Type]).to eq('AWS::AutoScaling::LaunchConfiguration')
        expect(test_launchconfig[:Properties][:ImageId]).to eq(image_id)
      end
    end

    context 'when invoked with custom parameters' do
      let(:template_name) { app_name.humanize.delete(' ') }
      let(:launch_config_props) { { InstanceType: 't2.medium' } }
      let(:auto_scale_props) { { DesiredCapacity: 5, Tags: [{ Key: 'Badname', Value: 'BadValue' }] } }
      let(:auto_scale_tags) { [{ Key: 'TemplateName', Value: template_name }] }
      let(:template_fixture) do
        as_test_app_name = app_name
        as_test_description = description
        as_test_image_id = image_id
        as_test_template_name = template_name
        as_test_launch_config_props = launch_config_props
        as_test_auto_scale_props = auto_scale_props
        as_test_auto_scale_tags = auto_scale_tags
        gen_richtemplate(as_test_template_name,
                         Enscalator::EnAppTemplateDSL,
                         [described_class]) do
          @app_name = as_test_app_name
          value(Description: as_test_description)
          mock_availability_zones
          auto_scale_init(as_test_image_id,
                          launch_config_props: as_test_launch_config_props,
                          auto_scale_props: as_test_auto_scale_props,
                          auto_scale_tags: as_test_auto_scale_tags)
        end
      end

      it 'generates valid template using provided values' do
        cmd_opts = default_cmd_opts(template_fixture.name, template_fixture.name.underscore)
        as_template = nil
        expect do
          as_template = template_fixture.new(cmd_opts)
        end.to output(/Do not use auto_scale_props to set Tags/).to_stderr
        dict = as_template.instance_variable_get(:@dict)
        test_autoscale = dict[:Resources]["#{template_name}AutoScale"]
        expect(test_autoscale[:Properties][:DesiredCapacity]).to eq(auto_scale_props[:DesiredCapacity])
        expect(test_autoscale[:Properties][:Tags]).to include(*auto_scale_tags)
        expect(test_autoscale[:Properties][:Tags]).to_not include(auto_scale_props[:Tags])
        test_launchconfig = dict[:Resources]["#{template_name}LaunchConfig"]
        expect(test_launchconfig[:Properties][:InstanceType]).to eq(launch_config_props[:InstanceType])
      end
    end
  end
end
