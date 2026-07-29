require 'spec_helper'

describe 'chef_client_updater resource' do
  platform 'ubuntu', '22.04'

  describe 'chef-ice product validation' do
    # Use chef_client_updater::default (reads product_name from node attribute).
    # test::chef_ice does not exist; the default recipe is the canonical entry point.
    context 'when using chef-ice as product_name' do
      let(:chef_run) do
        ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '22.04', step_into: ['chef_client_updater']) do |node|
          node.normal['chef_client_updater']['product_name'] = 'chef-ice'
          node.normal['chef_client_updater']['version'] = '18.0.0'
        end
      end

      it 'raises an error about unsupported product' do
        expect { chef_run.converge('chef_client_updater::default') }.to raise_error(RuntimeError, /Unsupported product: chef-ice/)
      end
    end

    context 'when using chef as product_name' do
      let(:chef_run) do
        ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '22.04', step_into: ['chef_client_updater']) do |node|
          node.normal['chef_client_updater']['version'] = '18.0.0'
          node.automatic['chef_packages'] = { 'chef' => { 'version' => '18.0.0' } }
        end
      end

      it 'does not raise an error' do
        expect { chef_run.converge('chef_client_updater::default') }.not_to raise_error
      end
    end
  end

  describe 'license_id parameter' do
    # Set attributes in the runner block (not in before) so they are guaranteed to be
    # present when the recipe is compiled during converge.
    # Stub mixlib_install at the ChefClientUpdaterHelper level (where desired_version lives)
    # to return a fake artifact matching the current version, so update_necessary? returns
    # false without making any real HTTP calls. allow_any_instance_of(Chef::Provider) cannot
    # stub methods defined on the LWRP subclass itself.
    context 'when license_id is provided' do
      let(:chef_run) do
        ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '22.04', step_into: ['chef_client_updater']) do |node|
          node.normal['chef_client_updater']['version'] = '18.0.0'
          node.normal['chef_client_updater']['license_id'] = 'test-license-123'
          node.automatic['chef_packages'] = { 'chef' => { 'version' => '18.0.0' } }
        end
      end

      before do
        fake_artifact = double('artifact', version: '18.0.0', url: 'https://example.com/chef.rpm')
        fake_mixlib = double('Mixlib::Install', artifact_info: [fake_artifact])
        allow_any_instance_of(ChefClientUpdaterHelper).to receive(:load_mixlib_install)
        allow_any_instance_of(ChefClientUpdaterHelper).to receive(:load_mixlib_versioning)
        allow_any_instance_of(ChefClientUpdaterHelper).to receive(:mixlib_install).and_return(fake_mixlib)
      end

      it 'does not log a warning about missing license_id' do
        expect(Chef::Log).not_to receive(:warn).with(/No license_id specified/)
        chef_run.converge('chef_client_updater::default')
      end
    end

    context 'when license_id is not provided' do
      let(:chef_run) do
        ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '22.04', step_into: ['chef_client_updater']) do |node|
          node.normal['chef_client_updater']['version'] = '18.0.0'
          node.automatic['chef_packages'] = { 'chef' => { 'version' => '18.0.0' } }
        end
      end

      it 'logs a warning about missing license_id' do
        expect(Chef::Log).to receive(:warn).with(/No license_id specified/)
        chef_run.converge('chef_client_updater::default')
      end
    end
  end
end
