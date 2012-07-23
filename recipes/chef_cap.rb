require File.expand_path(File.join(File.dirname(__FILE__), "lib", "chef_dna_parser"))
require File.expand_path(File.join(File.dirname(__FILE__), "lib", "chef_cap_helper"))
require File.expand_path(File.join(File.dirname(__FILE__), "lib", "chef_cap_configuration"))
require File.expand_path(File.join(File.dirname(__FILE__), "lib", "chef_cap_initializer"))

class DnaConfigurationError < Exception; end

ChefCapConfiguration.configuration = self
ChefDnaParser.load_dna

before "deploy", "chef:setup"
before "chef:setup", "bootstrap:ruby"

set :application, ChefDnaParser.parsed["application"]["name"] rescue nil
set :repository, ChefDnaParser.parsed["application"]["repository"] rescue nil
set :default_ruby_version, "1.9.3-p0"

ChefCapConfiguration.set_repository_settings

if ChefDnaParser.parsed["environments"]
  if environment_defaults = ChefDnaParser.parsed["environments"]["defaults"]
    ChefCapHelper.parse_hash(environment_defaults)
  end

  set :environments, {}

  ChefDnaParser.parsed["environments"].each_key do |environment|
    next if environment == "default"
    environment_hash = ChefDnaParser.parsed["environments"][environment]
    set :environments, environments.merge(environment => environment_hash)

    desc "Set server roles for the #{environment} environment"
    task environment.to_sym do
      set :environment_settings, environment_hash
      set :rails_env, environment_hash["rails_env"] || environment
      if environment_hash["role_order"]
        set :role_order, environment_hash["role_order"]
      else
        begin
          role_order
        rescue
          set(:role_order, {})
        end
      end

      default_environment["RAILS_ENV"] = rails_env

      ChefCapHelper.parse_hash(environment_hash)
      merged_environment = ChefDnaParser.parsed["environments"]["defaults"] || {} rescue {}
      environment_hash.each { |k, v| ChefCapHelper.recursive_merge(merged_environment || {}, k, v) }
      set :environment, merged_environment

      (environment_hash["servers"] || []).each do |server|
        if server["roles"] && server["hostname"]
          server["roles"].each do |role|
            options = {}
            options[:primary] = true if server["primary"] && server["primary"].include?(role)
            role role.to_sym, server["hostname"], options
          end
        end
      end
    end
    after environment.to_sym, "ssh:set_options"
  end
end

namespace :ssh do
  desc "Transfer SSH keys to the remote server"
  task :transfer_keys do
    private_key = ssh_deploy_key_file rescue false
    public_key = ssh_authorized_pub_file rescue false
    known_hosts = ssh_known_hosts rescue false
    if private_key || public_key || known_hosts
      private_key_remote_file = ".ssh/id_rsa"
      if private_key
        key_contents = File.read(private_key)
        private_key_remote_file = ".ssh/id_dsa" if key_contents =~ /DSA/i
      end
      run "mkdir -p ~/.ssh"
      if private_key
        put(File.read(private_key), private_key_remote_file, :mode => "0600")
      end
      put(File.read(public_key), ".ssh/authorized_keys", :mode => "0600") if public_key
      put(known_hosts, ".ssh/known_hosts", :mode => "0600") if known_hosts
    end
    depend(:remote, :file, private_key_remote_file) if private_key
    depend(:remote, :file, ".ssh/authorized_keys") if public_key
    depend(:remote, :file, ".ssh/known_hosts") if known_hosts
  end

  desc "Set any defined SSH options"
  task :set_options do
    ssh_options[:paranoid] = ssh_options_paranoid rescue nil
    ssh_options[:keys] = ssh_options_keys rescue nil
    ssh_options[:forward_agent] = ssh_options_forward_agent rescue nil
    ssh_options[:username] = ssh_options_username rescue user rescue nil
    ssh_options[:port] = ssh_options_port rescue nil
  end
end
before "chef:setup", "ssh:transfer_keys"
before "ssh:transfer_keys", "ssh:set_options"

if ChefDnaParser.parsed["upload"]
  uploads_for_roles = {}
  ChefDnaParser.parsed["upload"].each do |upload|
    unless upload.has_key?("source") && upload.has_key?("destination") && upload.has_key?("roles")
      raise DnaConfigurationError, "Invalid upload entry, should be {'source':value, 'destination':value, 'roles':[list], 'mode':value}"
    end
    upload["roles"].each do |role|
      uploads_for_roles[role] ||= []
      uploads_for_roles[role] << [upload["source"], upload["destination"], {:mode => upload["mode"] || "0644"}]
    end
  end

  uploads_for_roles.each_pair do |role, file_uploads|
    task "chef_upload_for_#{role}".to_sym, :roles => role do
      file_uploads.each do |file_to_upload|
        # TODO: better then mac local -> linux remote compatibility here
        run "md5sum #{file_to_upload[1]} | cut -f1 -d ' '" do |channel, stream, data|
          remote_md5 = data.to_s.strip
          local_md5 = `md5 #{file_to_upload[0]} | cut -f 2 -d '='`.to_s.strip
          if remote_md5 == local_md5
            puts "#{File.basename(file_to_upload[1])} matches checksum, skipping"
          else
            upload file_to_upload[0], file_to_upload[1], :host => channel[:host]
          end
        end
      end
    end
  end

  namespace :chef do
    desc "Uploads specified files to remote server"
    task :upload_all do
      uploads_for_roles.keys.each do |role|
        send "chef_upload_for_#{role}".to_sym
      end
    end
  end

  before "chef:deploy", "chef:upload_all"
end

if ChefDnaParser.parsed["chef"] && ChefDnaParser.parsed["chef"]["root"]
  set :chef_root_path, ChefDnaParser.parsed["chef"]["root"]
elsif ChefDnaParser.file_path
  default_chef_path = File.expand_path(File.join(File.dirname(ChefDnaParser.file_path)))
  if File.directory?(File.join(default_chef_path, "cookbooks"))
    set :chef_root_path, default_chef_path
  end
else
  raise DnaConfigurationError, "Could not find cookbooks in JSON or as a subdirectory of where your JSON is!"
end

if ChefDnaParser.parsed["chef"] && ChefDnaParser.parsed["chef"]["version"]
  set :chef_version, ChefDnaParser.parsed["chef"]["version"]
else
  default_chef_version = "0.10.8"
  set :chef_version, default_chef_version
end

set :debug_flag, ENV['DEBUG'] ? '-l debug' : ''

namespace :chef do
  task :setup do
    case ruby_version_switcher
    when 'rbenv'
      gem_check_for_chef_cmd = "gem specification --version '>=#{chef_version}' chef 2>&1 | awk 'BEGIN { s = 0 } /^name:/ { s = 1; exit }; END { if(s == 0) exit 1 }'"
      install_chef_cmd = "gem install chef --no-ri --no-rdoc --version=#{chef_version}"
      run "#{gem_check_for_chef_cmd} || #{install_chef_cmd} && echo 'Chef Solo already on this server.'"

      gem_check_for_bundler_cmd = "gem specification --version '>0' bundler 2>&1 | awk 'BEGIN { s = 0 } /^name:/ { s = 1; exit }; END { if(s == 0) exit 1 }'"
      install_bundler_cmd = "gem install bundler --no-ri --no-rdoc"
      run "#{gem_check_for_bundler_cmd} || #{install_bundler_cmd} && echo 'Bundler already on this server.'"
      run "rbenv rehash"
    else
      gem_check_for_chef_cmd = "gem specification --version '>=#{chef_version}' chef 2>&1 | awk 'BEGIN { s = 0 } /^name:/ { s = 1; exit }; END { if(s == 0) exit 1 }'"
      install_chef_cmd = "sudo `cat #{rvm_bin_path}` default exec gem install chef --no-ri --no-rdoc --version=#{chef_version}"
      sudo "`cat #{rvm_bin_path}` default exec #{gem_check_for_chef_cmd} || #{install_chef_cmd} && echo 'Chef Solo already on this server.'"

      gem_check_for_bundler_cmd = "gem specification --version '>0' bundler 2>&1 | awk 'BEGIN { s = 0 } /^name:/ { s = 1; exit }; END { if(s == 0) exit 1 }'"
      install_bundler_cmd = "sudo `cat #{rvm_bin_path}` default exec gem install bundler --no-ri --no-rdoc"
      sudo "`cat #{rvm_bin_path}` default exec #{gem_check_for_bundler_cmd} || #{install_bundler_cmd} && echo 'Bundler already on this server.'"
      sudo "`cat #{rvm_bin_path}` default exec which chef-solo"
    end
  end

  desc "Run chef-solo on the server(s)"
  task :deploy do
    require "tempfile"
    put "cookbook_path '/tmp/chef-cap-#{rails_env}/#{File.basename(chef_root_path)}/cookbooks'", "/tmp/chef-cap-solo-#{rails_env}.rb", :mode => "0600"
    sudo "rm -rf /tmp/chef-cap-#{rails_env}"
    file = Tempfile.new("chef-cap-#{rails_env}")
    file.close
    compressed_chef = file.path
    system("cd #{chef_root_path}/../ && tar cjf #{compressed_chef} --exclude-vcs #{File.basename(chef_root_path)}")
    upload compressed_chef, "/tmp/chef-cap-#{rails_env}.tbz", :mode => "0700"
    sudo "mkdir -p /tmp/chef-cap-#{rails_env}"
    sudo "tar xjf /tmp/chef-cap-#{rails_env}.tbz -C /tmp/chef-cap-#{rails_env}"
    file.unlink
    begin
      env_settings = environment_settings
    rescue
      raise "Could not load environment_settings, usually this means you tried to run the deploy task without calling an <env> first"
    end
    parallel do |session|
      session.else "echo 'Deploying Chef to this machine'" do |channel, stream, data|
        roles_for_host = ChefCapHelper.roles_for_host(roles, channel[:host])

        json_to_modify = ChefDnaParser.parsed.dup
        hash_for_host = ChefCapHelper.merge_roles_for_host(json_to_modify["roles"], roles_for_host)

        shared_hash = json_to_modify["shared"] || {}
        shared_hash.each { |k, v| ChefCapHelper.recursive_merge(json_to_modify, k, v) }
        hash_for_host.each {|k, v| ChefCapHelper.recursive_merge(json_to_modify, k, v) }

        json_to_modify["environment"] ||= json_to_modify["environments"]["defaults"] || {} rescue {}
        env_settings.each { |k, v| ChefCapHelper.recursive_merge(json_to_modify["environment"] || {}, k, v) }

        json_to_modify["environment"]["roles"] = roles_for_host
        json_to_modify["environment"]["revision"] = ChefCapHelper.set_revision if ChefCapHelper.has_revision?
        json_to_modify["environment"]["branch"] = ChefCapHelper.set_branch if ChefCapHelper.has_branch?
        json_to_modify["environment"]["servers"] = ChefCapHelper.intialize_primary_values(json_to_modify["environment"]["servers"])

        should_not_deploy = no_deploy rescue false
        json_to_modify["run_list"] = ChefCapHelper.rewrite_run_list_for_deploy(json_to_modify, should_not_deploy)

        set "node_hash_for_#{channel[:host].gsub(/\./, "_")}", json_to_modify
        put json_to_modify.to_json, "/tmp/chef-cap-#{rails_env}-#{channel[:host]}.json", :mode => "0600"

        rollback_json = json_to_modify.dup
        rollback_json["run_list"] = rollback_json["rollback_run_list"] || []
        set "node_hash_for_#{channel[:host].gsub(/\./, "_")}_rollback", rollback_json
        put rollback_json.to_json, "/tmp/chef-cap-#{rails_env}-#{channel[:host]}-rollback.json", :mode => "0600"
      end
    end
    transaction { chef.run_chef_solo }
  end

  task :setup_to_run_chef_solo do
    set :run_chef_solo_deploy_command, "#{exec_chef_solo} -j /tmp/chef-cap-#{rails_env}-`hostname`.json"
    set :run_chef_solo_rollback_command, "#{exec_chef_solo} -j /tmp/chef-cap-#{rails_env}-`hostname`-rollback.json"
    set :run_chef_solo_block, { :block => lambda { |command_to_run|
      hosts_that_have_run = []
      unless role_order.empty?
        role_order.each do |role, dependent_roles|
          role_hosts = (find_servers(:roles => [role.to_sym]).map(&:host) - hosts_that_have_run).uniq
          dependent_hosts = (find_servers(:roles => dependent_roles.map(&:to_sym)).map(&:host) - role_hosts - hosts_that_have_run).uniq
          if role_hosts.any?
            sudo(command_to_run, :hosts => role_hosts)
            hosts_that_have_run += role_hosts
          end
          if dependent_hosts.any?
            sudo(command_to_run, :hosts => dependent_hosts)
            hosts_that_have_run += dependent_hosts
          end
        end
      else
        sudo(command_to_run)
      end
    } } # Because capistrano automatically calls lambdas on reference which means you can't pass it an argument.
  end

  task :rollback_pre_hook do
  end

  task :rollback_post_hook do
  end

  task :run_chef_solo do
    chef.setup_to_run_chef_solo
    on_rollback do
      chef.rollback_pre_hook
      run_chef_solo_block[:block].call(run_chef_solo_rollback_command)
      chef.rollback_post_hook
    end
    run_chef_solo_block[:block].call(run_chef_solo_deploy_command)
  end

  desc "Remove all chef-cap files from /tmp"
  task :cleanup do
    sudo "rm -rf /tmp/chef-cap*"
  end
end

before "chef:deploy", "chef:setup"
