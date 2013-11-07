require 'fileutils'
require 'systemu'
require 'net/ssh'
require 'net/scp'
require 'rspec-system/node_set/vagrant_base'

module RSpecSystem
  # A NodeSet implementation for Vagrant using the openstack provider
  class NodeSet::VagrantOpenstack < NodeSet::VagrantBase
    PROVIDER_TYPE = 'vagrant_openstack'

    # Name of provider
    #
    # @return [String] name of the provider as used by `vagrant --provider`
    def vagrant_provider_name
      'openstack'
    end

    # Adds virtualbox customization to the Vagrantfile
    #
    # @api private
    # @param name [String] name of the node
    # @param options [Hash] customization options
    # @return [String] a series of vbox.customize lines
    def customize_provider(name,options)
      custom_config = ""
      options.each_pair do |key,value|
        #TODO create checks for required items
        #TODO validate types of input
        #TODO does the inspect values even work?
        next if global_vagrant_options.include?(key)
        case key
        when 'username','api_key','endpoint','keypair_name','ssh_username'
          #required string
          custom_config << "    prov.#{key.to_s} = \"#{value}\"\n"
        when 'flavor','image'
          #required regex
          custom_config << "    prov.#{key.to_s} = /#{value}/\n"
        when 'metadata'
          #required hash
          custom_config << "    prov.#{key.to_s} = #{value.inspect}\n"
        when 'user_data','network','address_id','availability_zone','tenant','floating_ip'
          #optional string
          custom_config << "    prov.#{key.to_s} = \"#{value}\"\n"
        when 'scheduler_hints'
          #optional hash with symbol keys
          custom_config << "    prov.#{key.to_s} = #{value.inspect}\n"
        when 'security_groups'
          #optional array
          custom_config << "    prov.#{key.to_s} = #{value.inspect}\n"
        else
          log.warn("Skipped invalid custom option for node #{name}: #{key}=#{value}")
        end
      end
      custom_config
    end
  end
end
