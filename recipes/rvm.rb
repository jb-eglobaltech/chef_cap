namespace :bootstrap do
  desc "Create a standalone rvm installation with a default ruby to use with chef-solo"
  task :rvm do
    begin
      ruby_version
    rescue
      set :ruby_version, default_ruby_version
    end
    if ruby_version =~ /^[0-9]/
      ruby_version = "ruby-#{ruby_version}"
    end
    rvm_standup_script = <<-SH
      #!/bin/bash
      #
      RVM_URL="https://raw.github.com/wayneeseguin/rvm/master/binscripts/rvm-installer"
      export PATH=$PATH:/usr/local/rvm/bin:~/.rvm/bin
      HAVE_RVM_ALREADY=`which rvm 2>/dev/null`
      if [ $? -eq 0 ]; then
        echo "Found RVM: " `which rvm`
        echo "Looks like RVM is already on this machine. Recording to /tmp/.chef_cap_rvm_path"
        which rvm > /tmp/.chef_cap_rvm_path
        `cat /tmp/.chef_cap_rvm_path` list | grep "No rvm rubies installed"
        if [ $? -eq 0 ]; then
          echo "No rvm rubies installed. Installing from capistrano setting :ruby_version #{ruby_version}"
          `cat /tmp/.chef_cap_rvm_path` install #{ruby_version}
          `cat /tmp/.chef_cap_rvm_path` --default use #{ruby_version}
        fi
        `cat /tmp/.chef_cap_rvm_path` list | grep "Default ruby not set"
        if [ $? -eq 0 ]; then
          echo "No rvm default set."
          `cat /tmp/.chef_cap_rvm_path` alias create default #{ruby_version}
        fi
        exit 0
      else
        echo "Could not find RVM, PATH IS: ${PATH}"
        echo "Going to attempt to attempt to download and install RVM from ${RVM_URL}"
      fi

      HAVE_CURL=`which curl 2>/dev/null`
      if [ $? -eq 0 ]; then
        RVM_TEMP_FILE=`mktemp /tmp/rvm_bootstrap.XXXXXX`
        curl -k $RVM_URL | sed "s/curl /curl -k /g" > $RVM_TEMP_FILE
        chmod u+rx $RVM_TEMP_FILE
        bash -s stable < $RVM_TEMP_FILE
        rm -f $RVM_TEMP_FILE
        which rvm > /tmp/.chef_cap_rvm_path
        `cat /tmp/.chef_cap_rvm_path` list | grep "No rvm rubies installed"
        if [ $? -eq 0 ]; then
          echo "No rvm rubies installed. Installing from capistrano setting :ruby_version #{ruby_version}"
          `cat /tmp/.chef_cap_rvm_path` install #{ruby_version}
          `cat /tmp/.chef_cap_rvm_path` --default use #{ruby_version}
          `cat /tmp/.chef_cap_rvm_path` alias create default #{ruby_version}
        fi
      else
        echo "FATAL ERROR: I have no idea how to download RVM without curl!"
        exit 1
      fi
    SH
    put rvm_standup_script, "/tmp/chef-cap-#{rails_env}-rvm-standup.sh", :mode => "0700"
    sudo "/tmp/chef-cap-#{rails_env}-rvm-standup.sh"
  end
end
