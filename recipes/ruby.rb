namespace :bootstrap do
  desc "Create a standalone rbenv installation with a default ruby to use with chef-solo"
  task :ruby do
    local_rvs = ruby_version_switcher rescue 'rvm'
    local_env = rails_env rescue 'unknown'

    case local_rvs
    when 'rbenv'

      set :default_environment, {
        'PATH' => "$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH:/usr/sbin"
      }
      set :ruby_version_switcher, "rbenv"
      set :exec_chef_solo, "chef-solo -c /tmp/chef-cap-solo-#{local_env}.rb #{debug_flag}"
    else
      ## rvm is the default
      set :default_environment, {
        'PATH' => "$PATH:/usr/sbin"
      }
      set :ruby_version_switcher, "rvm"
      set :rvm_bin_path, "/tmp/.chef_cap_rvm_path"
      set :exec_chef_solo, "`cat #{rvm_bin_path}` default exec chef-solo -c /tmp/chef-cap-solo-#{local_env}.rb #{debug_flag}"
    end

    depend :remote, :command, ruby_version_switcher
    depend :remote, :command, "chef-solo"

    after "bootstrap:ruby", "bootstrap:#{ruby_version_switcher}"
  end
end
