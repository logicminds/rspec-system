require 'securerandom'
require 'fileutils'
require 'systemu'
require 'net/ssh'
require 'net/scp'
require 'rspec-system/node_set/base'

module RSpecSystem
  # A NodeSet implementation for lxc-docker
  class NodeSet::Docker < NodeSet::Base

    include RSpecSystem::Log
    include RSpecSystem::Util
    PROVIDER_TYPE = 'docker'

    # Creates a new instance of RSpecSystem::NodeSet::Docker
    #
    # @param setname [String] name of the set to instantiate
    # @param config [Hash] nodeset configuration hash
    # @param custom_prefabs_path [String] path of custom prefabs yaml file
    # @param options [Hash] options Hash
    def initialize(setname, config, custom_prefab_path, options)
      super
    end

    # returns boolean if docker can be used
    def docker_available?
      system('docker ps > /dev/null')
    end

    # Launch nodes
    #
    # @return [void]
    def launch
      if not docker_available?
        log.info "[Docker#launch] Docker not available or docker is not running"
        return nil
      end
      log.info "[Docker#launch] Begin setting up docker"
      docker_containers = nodes.inject({}) do |hash, (k,v)|
        options = config['nodes'][k]['docker_options']
        ps = v.provider_specifics['docker']
        raise 'No provider specifics for this prefab' if ps.nil?
        baseimage = ps['baseimage']
        raise "No base image specified for this prefab" if baseimage.nil?
        hostname = k
        # if the images does not exist pull it from the assigned authority (docker-io)
        pull_image(baseimage) if not image_exists?(baseimage)
        image_name = make_unique_name(k)
        log.info "[Docker#launch] building image #{image_name} from image #{baseimage}"
        build_image(image_name, baseimage,options)
        log.info "[Docker#launch] launching container #{k} from built image #{image_name}"
        container = run_container(hostname, image_name, options)
        raise "Could not create container #{image_name}" if container.nil? or container.empty?
        hash[k] = {
          :id   => container,
          :name => image_name,
        }

        hash
      end
      RSpec.configuration.rs_storage[:nodes] = docker_containers
      nil
    end

    # This will create the docker file and then build the image from the file.  After building the image
    # it will remove the docker file if destroy is true
    # Should we ever need to execute ssh commands as a nonroot user this would need to be added
    # dockerfile.puts "RUN useradd rsuser && echo 'rsuser:rspec' | chpasswd && echo \"rsuser    ALL=(ALL)  NOPASSWD:ALL\" >> /etc/sudoers"

    def build_image(name, baseimage, options)
      if not docker_available?
        log.info "[Docker#launch] Docker not available or docker is not running"
        return nil
      end
      log.info "[Docker#launch] Generating docker file"
      File.open("buildfile-#{name}", 'w') do | dockerfile|
        dockerfile.puts "FROM #{baseimage}"
        dockerfile.puts "MAINTAINER rspec-system"
        if not options['commits'].nil?
          options['commits'].each do | key, value|
            dockerfile.puts "RUN #{run_commands(value)}"
          end
        end
        dockerfile.puts "RUN /usr/bin/ssh-keygen -q -t rsa1 -f /etc/ssh/ssh_host_key -C '' -N '' && \\ \n"+
                  "/usr/bin/ssh-keygen -q -t rsa -f /etc/ssh/ssh_host_rsa_key -C '' -N '' && \\ \n" +
                  "/usr/bin/ssh-keygen -q -t dsa -f /etc/ssh/ssh_host_dsa_key -C '' -N '' "
        dockerfile.puts "RUN mkdir /var/run/sshd && echo 'root:rspec' | chpasswd"
        dockerfile.puts "RUN sed -ri 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config && sed -ri 's/#UsePAM no/UsePAM no/g' /etc/ssh/sshd_config"
        dockerfile.puts 'EXPOSE 22'
        dockerfile.puts 'ENTRYPOINT ["/usr/sbin/sshd", "-D"]'
      end
      raise "Dockerfile buildfile-#{name} was not created successfully, filesystem full?" if File.size("buildfile-#{name}") < 1
      system("docker build -t \"#{name}\" - < buildfile-#{name}")
      if destroy
        FileUtils.rm("buildfile-#{name}")
      end
    end

    def has_nodes?
      RSpec.configuration.rs_storage.has_key?(:nodes) and RSpec.configuration.rs_storage[:nodes].length > 0
    end

    def container_running?(id)

    end

    def make_unique_name(name)
      "rspec-system-#{name}-#{SecureRandom.hex(10)}"
    end

    def run_commands(runs)
      commands = runs.collect do |key, value|
        value
      end
      commands.join(" && \\ \n")
    end
    # synced directories returns the docker syntax to attach host volumes to the container
    # there is a issue here where docker does not start if any of the directories to be mounted
    # overlap each other
    # example:   /tmp/dir1/test1   /tmp/dir1/test1/dir2
    def synced_dirs(options)
      folders = options['shared_directories'].collect do |key, value|
        "-v #{File.expand_path(value['src'])}:#{value['dst']}:ro"
      end
      folders.join(' ')
    end

    # runs the image and returns the container id
    # setup the port to be exposed on localhost random port (-p 127.0.0.1::22 )
    def run_container(hostname, name, options)
      log.info("docker run -p 127.0.0.1::22 #{synced_dirs(options)} -d -h #{hostname} #{name}")
      %x{docker run -p 127.0.0.1::22 #{synced_dirs(options)} -d -h "#{hostname}" #{name}}.chomp
    end

    def kill_container(name, id)
      log.info "[Docker#kill_container] kill container #{name} (#{id})"
      system("docker kill #{id}")
    end

    def rm_image(name)
      log.info "[Docker#rm_image] removing image #{name}"
      system("docker rmi #{name}")
    end

    def rm_container(name, id)
      log.info "[Docker#rm_container] removing container #{name} (#{id})"
      system("docker rm #{id}")
    end

    def pull_image(name)
      system("docker pull #{name}")
    end

    # image_exists? returns a boolean value if the image name exists
    def image_exists?(name)
      system("docker images | grep #{name} > /dev/null")
    end

    # mapped_port will find the port number that is exposed to the external container host
    def mapped_port(container)
      %x{docker port #{container} 22}.chomp.split(':').last
    end

    def container_ip(container_id)
      '127.0.0.1'
      #%x{docker inspect #{container_id} | grep IPAddress | cut -d '"' -f 4}.chomp
    end

    # Connect to the nodes
    #
    # @return [void]
    def connect
      nodes.each do |k,v|
        container = RSpec.configuration.rs_storage[:nodes][k][:id]
        port = mapped_port(container)
        ip   = container_ip(container)
        raise "Could not get ip from docker container?" if ip.nil? or ip.empty?
        raise "Could not get port from docker container?" if port.nil? or port.empty?

        log.info "Container has ip address of: #{ip}"
        ssh       = ssh_connect(:host => ip, :user => 'root', :net_ssh_options => {
          :password => 'rspec',
          :port     => port
        })

        RSpec.configuration.rs_storage[:nodes][k][:ssh] = ssh
      end

      nil
    end

    # Shutdown the NodeSet by shutting down all nodes.
    #
    # @return [void]
    def teardown
      if not docker_available?
        log.info "[Docker#launch] Docker not available or docker is not running"
        return nil
      end
      if not has_nodes?
        log.info "[Docker#launch] no containers to destroy"
        return nil
      end

      log.info "[Docker#teardown] killing containers"
      nodes.each do |k, v|
        v = RSpec.configuration.rs_storage[:nodes][k]
        #log.debug "Node: #{v.inspect}"
        next if v[:id].empty?  # if the container was never created, no need to destroy
        conn = v[:ssh]
        if not conn.nil?
          log.info "[Docker#teardown] stop ssh container #{k}"
          conn.close unless conn.closed?
        end
        if destroy
          kill_container(k, v[:id])
          rm_container(k, v[:id])
          rm_image(v[:name])
        else
          log.info "[Docker#teardown] Skipping kill container #{k} #{v[:id]}"
          log.info "[Docker#teardown] Skipping rmi image #{k} #{v[:name]}"
        end
      end
      nil
    end

    # Transfer files to a host in the NodeSet.
    #
    # @param opts [Hash] options
    # @return [Boolean] returns true if command succeeded, false otherwise
    # @todo This is damn ugly, because we ssh in as vagrant, we copy to a temp, we should be able to
    # use docker to cp files over Usage: docker cp CONTAINER:PATH HOSTPATH
    #
    #   path then move it later. Its slow and brittle and we need a better
    #   solution. Its also very Linux-centrix in its use of temp dirs.
    def rcp(opts)
      dest = opts[:d].name
      source = opts[:sp]
      dest_path = opts[:dp]

      # Grab a remote path for temp transfer
      tmpdest = tmppath

      # Do the copy and print out results for debugging
      ssh = RSpec.configuration.ssh_channels[dest][:ssh]
      ssh.scp.upload! source.to_s, tmpdest.to_s, :recursive => true

      # Now we move the file into their final destination
      result = run(:n => opts[:d], :c => "mv #{tmpdest} #{dest_path}")
      if result[:exit_code] == 0
        return true
      else
        return false
      end
    end
  end
end
