namespace :bootstrap do
  desc "Create a standalone rbenv installation with a default ruby to use with chef-solo"
  task :rbenv do
    set :ruby_version, default_ruby_version
    ruby_version.gsub!(/^ruby\-/,'')
    standup_script = <<-SH
      #!/bin/bash
      #
      # And now install rbenv
      export PATH=$HOME/bin:$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH

      HAVE_RBENV_ALREADY=`which rbenv 2>/dev/null`
      if [ $? != 0 ]; then
        echo "Install rbenv dependencies..."
        sudo yum install -y git
        echo "Building rbenv..."
        git clone git://github.com/sstephenson/rbenv.git ~/.rbenv
        # Add rbenv to your path
        echo 'export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"' >> .bashrc
        echo 'eval "$(rbenv init -)"' >> .bashrc
        source ~/.bash_profile
      fi;

      # Install ruby-build
      HAVE_RUBY_BUILD=`which ruby-build 2>/dev/null`
      if [ $? != 0 ]; then
        echo "Building ruby-build..."
        cd /tmp
        git clone git://github.com/sstephenson/ruby-build.git
        cd ruby-build
        PREFIX=$HOME ./install.sh
        cd $HOME
      fi;

      # Install Ruby #{ruby_version}
      HAVE_CORRECT_VERSION=`rbenv versions | grep '#{ruby_version}' | wc -l`
      if [ $HAVE_CORRECT_VERSION -eq 0 ]; then
        echo "Installing Ruby dependencies..."
        sudo yum install -y automake gcc make libtool curl zlib zlib-devel patch readline readline-devel libffi-devel openssl openssl-devel
        echo "Installing #{ruby_version}..."
        rbenv install #{ruby_version}
        rbenv global #{ruby_version}
        # Rehash!
        rbenv rehash
      fi;
    SH
    put standup_script, "/tmp/chef-cap-#{rails_env}-rbenv-standup.sh", :mode => "0700"
    run "/tmp/chef-cap-#{rails_env}-rbenv-standup.sh"
  end
end
