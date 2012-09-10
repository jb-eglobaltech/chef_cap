require File.expand_path(File.join(File.dirname(__FILE__), "spec_helper"))

describe "chef_cap" do

  let(:chef_cap) {
    FakeChefCapConfiguration.create(@test_dna)
  }

  before do
    @test_dna = <<-JS
      {
        "chef": {
          "root": "path_to_cookbooks"
        }
      }
    JS
  end

  it "hijacks the load method to silently ignore the config/deploy load line if deploy.rb does not exist" do
    File.should_receive(:exist?).and_return(false)
    chef_cap.load("foo").should == true
  end

  it "loads a JSON file and assigns values to capistrano variables" do
    @test_dna = <<-JS
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "application": {
          "name": "frobble"
        }
      }
    JS
    chef_cap.cap_variable[:application].should == "frobble"
  end

  it "loads all the required capistrano variables" do
    @test_dna = <<-JS
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "application": {
          "name": "frobble",
          "repository": "git@somehost:user/repo.git"
        },
        "environments": {
          "defaults": {
            "user": "myuser",
            "ruby": {
              "version": "1.9.2-HEAD"
            }
          },
          "some_env": {
            "user": "newenvuser",
            "servers": [
              {
                "hostname": "localhost",
                "roles": ["app", "someotherrole", "db"],
                "primary": ["db"]
              }
            ]
          }
        }
      }
    JS
    chef_cap.cap_variable[:application].should == "frobble"
    chef_cap.cap_variable[:repository].should == "git@somehost:user/repo.git"
    chef_cap.cap_variable[:scm].should == :git
    chef_cap.cap_variable[:user].should == "myuser"
    chef_cap.cap_variable[:ruby_version].should == "1.9.2-HEAD"

    chef_cap.cap_variable[:rails_env].should be_nil
    chef_cap.cap_task[:some_env].should_not be_nil
    chef_cap.cap_task[:some_env].call
    chef_cap.cap_variable[:rails_env].should == "some_env"
    chef_cap.cap_variable[:user].should == "newenvuser"
    chef_cap.cap_role[:someotherrole].should_not be_nil
    chef_cap.cap_role[:someotherrole][:servers].should include("localhost")
    chef_cap.cap_role[:app][:servers].should include("localhost")
    chef_cap.cap_role[:db][:servers].should include("localhost")
    chef_cap.cap_role[:db][:primary].should == "localhost"
  end

  it "stores the environment settings in a capistrano variable" do
    @test_dna = <<-JS
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "application": {
          "name": "frobble",
          "repository": "git@somehost:user/repo.git"
        },
        "environments": {
          "defaults": {
            "user": "myuser"
          },
          "some_env": {
            "user": "newenvuser"
          }
        }
      }
    JS
    chef_cap.cap_variable[:environments].should_not be_nil
    chef_cap.cap_variable[:environments]["some_env"].should_not be_nil
    chef_cap.cap_variable[:environments]["some_env"]["user"].should == "newenvuser"
  end

  describe "default_environment" do
    it "sets the RAILS_ENV to rails_env" do
      @test_dna = <<-ERB
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "environments": {
          "some_env": {
              "rails_env": "my_env"
            }
        }
      }
      ERB

      chef_cap.cap_task[:some_env].call
      chef_cap.default_environment["RAILS_ENV"].should == "my_env"
    end
  end

  describe "merging defaults and a specific environment" do
    it "sets the RAILS_ENV to rails_env" do
      @test_dna = <<-ERB
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "environments": {
          "defaults": {
              "rails_env": "default",
              "foo": "bar"
          },
          "some_env": {
              "rails_env": "my_env"
          }
        }
      }
      ERB

      chef_cap.cap_task[:some_env].call
      chef_cap.cap_variable[:environment].should_not be_nil
      chef_cap.cap_variable[:environment]["rails_env"].should == "my_env"
      chef_cap.cap_variable[:environment]["foo"].should == "bar"
    end
  end

  describe ":repositories" do
    context "svn" do
      before do
        @test_dna = <<-JS
          {
            "chef": {
              "root": "path_to_cookbooks"
            },
            "application": {
              "repository": "svn://somehost:user/repo/trunk"
            }
          }
        JS
      end

      it "sets the scm to svn if the repository looks to be subversion" do
        chef_cap.cap_variable[:repository].should == "svn://somehost:user/repo/trunk"
        chef_cap.cap_variable[:scm].should == :svn
      end

      it "adds a dependency on git existing on the remote machine" do
        chef_cap.cap_depends["svn"].should_not be_nil
        chef_cap.cap_depends["svn"].should == { :remote => :command }
      end

    end

    context "git" do

      before do
        @test_dna = <<-JS
          {
            "chef": {
              "root": "path_to_cookbooks"
            },
            "application": {
              "repository": "git@somehost:user/repo.git"
            }
          }
        JS
      end

      it "sets additional git settings if the repository looks to be git" do
        chef_cap.cap_variable[:repository].should == "git@somehost:user/repo.git"
        chef_cap.cap_variable[:scm].should == :git
        chef_cap.cap_variable[:git_enable_submodules].should == 1
      end

      it "adds a dependency on git existing on the remote machine" do
        chef_cap.cap_depends["git"].should_not be_nil
        chef_cap.cap_depends["git"].should == { :remote => :command }
      end

      it "sets the default_run_options pty to true" do
        chef_cap.default_run_options[:pty].should be_true
      end
    end

  end

  describe "ssh keys" do

    before do
      @test_dna = <<-ERB
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "environments": {
          "defaults": {
            "ssh": {
              "deploy_key_file": "#{File.join(File.dirname(__FILE__), '..', 'fixtures', 'ssh_deploy_key')}",
              "authorized_pub_file": "#{File.join(File.dirname(__FILE__), '..', 'fixtures', 'ssh_public_key')}",
              "known_hosts": "knownhostscontent",
              "options": {
                "keys": "some_ssh_key_path",
                "username": null
              }
            }
          },
          "nossh": {
            "ssh": {
              "deploy_key_file": null
            }
          }
        }
      }
      ERB
    end

    describe "ssh:transfer_keys" do
      context "setting variables" do
        before do
          chef_cap.stub!(:put).and_return(true)
          chef_cap.cap_task["ssh:transfer_keys"].call
        end

        it "parses out the deploy private key" do
          chef_cap.cap_variable[:ssh_deploy_key_file].should_not be_nil
          chef_cap.cap_variable[:ssh_deploy_key_file].should == File.join(File.dirname(__FILE__), '..', 'fixtures', 'ssh_deploy_key')
        end

        it "parses out the authorized public file" do
          chef_cap.cap_variable[:ssh_authorized_pub_file].should_not be_nil
          chef_cap.cap_variable[:ssh_authorized_pub_file].should == File.join(File.dirname(__FILE__), '..', 'fixtures', 'ssh_public_key')
        end

        it "parses out the known hosts file" do
          chef_cap.cap_variable[:ssh_known_hosts].should_not be_nil
          chef_cap.cap_variable[:ssh_known_hosts].should == "knownhostscontent"
        end
      end

      it "creates a task that uploads the keys to the server users .ssh directory" do
        chef_cap.cap_namespace[:ssh].should be_true
        chef_cap.cap_task["ssh:transfer_keys"].should_not be_nil
        chef_cap.should_receive(:put).with("dsa imaprivatekey", ".ssh/id_dsa", :mode => "0600").and_return(true)
        chef_cap.should_receive(:put).with("imapublickey", ".ssh/authorized_keys", :mode => "0600").and_return(true)
        chef_cap.should_receive(:put).with("knownhostscontent", ".ssh/known_hosts", :mode => "0600").and_return(true)

        chef_cap.cap_task["ssh:transfer_keys"].call
      end


      it "adds a before chef:setup hook that that uploads the keys on every deploy" do
        chef_cap.cap_before["chef:setup"].should_not be_nil
        chef_cap.cap_before["chef:setup"].should include("ssh:transfer_keys")
      end

      it "adds dependencies on remote files for the ssh files to be uploaded" do
        chef_cap.stub(:put).and_return(true)
        chef_cap.cap_task["ssh:transfer_keys"].call
        chef_cap.cap_depends[".ssh/id_dsa"].should_not be_nil
        chef_cap.cap_depends[".ssh/id_dsa"].should == { :remote => :file }

        chef_cap.cap_depends[".ssh/authorized_keys"].should_not be_nil
        chef_cap.cap_depends[".ssh/authorized_keys"].should == { :remote => :file }

        chef_cap.cap_depends[".ssh/known_hosts"].should_not be_nil
        chef_cap.cap_depends[".ssh/known_hosts"].should == { :remote => :file }
      end
    end

    describe "ssh:set_options" do
      it "parses out keys" do
        chef_cap.cap_task["ssh:set_options"].call
        chef_cap.cap_ssh_options[:keys].should_not be_nil
        chef_cap.cap_ssh_options[:keys].should == "some_ssh_key_path"
      end

      it "adds a before ssh:transfer_keys hook to call ssh:set_options" do
        chef_cap.cap_before["ssh:transfer_keys"].should_not be_nil
        chef_cap.cap_before["ssh:transfer_keys"].should include("ssh:set_options")
      end

      it "adds a after <environment> hook to call ssh:set_options" do
        chef_cap.cap_after[:nossh].should_not be_nil
        chef_cap.cap_after[:nossh].should include("ssh:set_options")
      end

      it "does not set nil values" do
        chef_cap.cap_task["ssh:set_options"].call
        chef_cap.cap_ssh_options.has_key?(:username).should be_false
        chef_cap.cap_ssh_options.has_key?(:config).should be_false
      end
    end

    context "when a value is null" do
      it "will be not be uploaded" do
        chef_cap.cap_variable[:ssh_deploy_key_file].should_not be_nil
        chef_cap.cap_task[:nossh].call
        chef_cap.cap_variable[:ssh_deploy_key_file].should be_nil

        chef_cap.should_not_receive(:put).with("dsa imaprivatekey", ".ssh/id_dsa", :mode => "0600")
        chef_cap.should_receive(:put).with("imapublickey", ".ssh/authorized_keys", :mode => "0600").and_return(true)
        chef_cap.should_receive(:put).with("knownhostscontent", ".ssh/known_hosts", :mode => "0600").and_return(true)

        chef_cap.cap_task["ssh:transfer_keys"].call
        chef_cap.cap_variable[:ssh_deploy_key_file].should be_nil
      end
    end

  end

  describe "rbenv bootstrap" do
    it "uploads a shell script to the server and runs it as root" do
      @test_dna = <<-ERB
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "environments": {
          "some_env": {
              "ruby_version_switcher": "rbenv",
              "rails_env": "my_env"
            }
        }
      }
      ERB

      chef_cap.cap_task[:some_env].call
      chef_cap.cap_namespace[:bootstrap].should_not be_nil
      chef_cap.cap_task["bootstrap:rbenv"].should_not be_nil

      chef_cap.should_receive(:put)
      chef_cap.should_receive(:run).with("/tmp/chef-cap-my_env-rbenv-standup.sh")
      chef_cap.cap_task["bootstrap:rbenv"].call
    end
  end

  describe "rvm bootstrap" do
    it "uploads a shell script to the server and runs it as root" do
      @test_dna = <<-ERB
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "environments": {
          "some_env": {
              "rails_env": "my_env"
            }
        }
      }
      ERB

      chef_cap.cap_task[:some_env].call
      chef_cap.cap_namespace[:bootstrap].should_not be_nil
      chef_cap.cap_task["bootstrap:rvm"].should_not be_nil

      chef_cap.should_receive(:put)
      chef_cap.should_receive(:sudo).with("/tmp/chef-cap-my_env-rvm-standup.sh")
      chef_cap.cap_task["bootstrap:rvm"].call
    end
  end

  describe "task :chef:cleanup" do
    it "creates a task that wipes all /tmp/chef-cap* files" do
      chef_cap.cap_namespace[:chef].should_not be_nil
      chef_cap.cap_task["chef:cleanup"].should_not be_nil

      chef_cap.should_receive(:sudo).with("rm -rf /tmp/chef-cap*")
      chef_cap.cap_task["chef:cleanup"].call
    end
  end

  describe "namespace :chef" do

    it "runs chef:setup before chef:deploy" do
      chef_cap.cap_before["chef:deploy"].should_not be_nil
      chef_cap.cap_before["chef:deploy"].should include("chef:setup")
    end

    it "runs bootstrap:ruby before chef:setup" do
      chef_cap.cap_before["chef:setup"].should_not be_nil
      chef_cap.cap_before["chef:setup"].should include("bootstrap:ruby")
    end

    describe "task :deploy" do
      let(:test_dna) do
        <<-JS
        {
          "chef": {
            "root": "path_to_cookbooks",
            "version": "0.1982.1234"
          },
          "environments": {
            "some_env": {
              "rails_env": "myenv",
              "servers": [
                {
                  "hostname": "localhost",
                  "roles": ["role1", "role2"]
                },
                {
                  "hostname": "otherhost.com",
                  "roles": ["role1"]
                }
              ]
            }
          },
          "roles": {
            "role1": { "run_list": ["foo"] },
            "role2": { "run_list": ["foo", "bar"] }
          }
        }
        JS
      end

      before do
        @test_dna = test_dna
        chef_cap.cap_task[:some_env].should_not be_nil
        chef_cap.cap_task[:some_env].call
        chef_cap.stub(:system).and_return(true)
      end

      it "exists" do
        chef_cap.cap_namespace[:chef].should be_true
        chef_cap.cap_task["chef:deploy"].should_not be_nil
      end

      it "modifies the default run list for each host and stores all modified structure" do
        chef_cap.roles.keys.should == ["role1", "role2"]

        chef_cap.stub!(:put => "stubbed")
        chef_cap.stub!(:upload => "stubbed")
        chef_cap.stub!(:sudo => "stubbed")

        chef_cap.cap_variable[:environment_settings].should_not be_nil

        chef_cap.parallel_mocks << proc { |server_session|
          server_session.stub!(:put => "stubbed")
          server_session.stub!(:sudo => "stubbed")
        }

        chef_cap.cap_task["chef:deploy"].call

        chef_cap.parallel_sessions.each do |server_session|
          if server_session.things_that_were_set.keys.include? "node_hash_for_localhost"
            server_session.things_that_were_set["node_hash_for_localhost"]["environment"]["roles"].should == ["role1", "role2"]
            server_session.things_that_were_set["node_hash_for_localhost"]["run_list"].should == ["foo", "bar"]
          elsif server_session.things_that_were_set.keys.include? "node_hash_for_otherhost"
            server_session.things_that_were_set["node_hash_for_otherhost"]["environment"]["roles"].should == ["role1"]
            server_session.things_that_were_set["node_hash_for_otherhost"]["run_list"].should == ["foo"]
          end
        end
      end

      it "that uploads the DNA.json and a solo.rb file" do
        localhost_dna = JSON.parse(@test_dna).dup
        otherhost_dna = JSON.parse(@test_dna).dup
        localhost_dna["run_list"] = ["foo", "bar"]
        localhost_dna["environment"] = localhost_dna["environments"]["some_env"]
        otherhost_dna["run_list"] = ["foo"]
        otherhost_dna["environment"] = otherhost_dna["environments"]["some_env"]

        chef_cap.parallel_mocks << proc { |server_session|
          server_session.should_receive(:put).with(anything, anything, :mode => "0600").at_least(:once).and_return("mocked")
          server_session.stub!(:set => "stubbed")
          server_session.stub!(:sudo => "stubbed")
        }
        chef_cap.should_receive(:put).ordered.with("cookbook_path '/tmp/chef-cap-myenv/path_to_cookbooks/cookbooks'", "/tmp/chef-cap-solo-myenv.rb", :mode => "0600").and_return("mocked")
        chef_cap.stub!(:upload => "stubbed")
        chef_cap.stub!(:sudo => "stubbed")
        chef_cap.cap_task["chef:deploy"].call
      end

      it "uploads the cookbooks" do
        Tempfile.should_receive(:new).and_return(double(:path => "/tmp/temp_file", :close => nil, :unlink => nil))
        chef_cap.stub!(:put => "stubbed")
        chef_cap.should_receive(:upload).with("/tmp/temp_file", "/tmp/chef-cap-myenv.tbz", :mode => "0700").and_return("mocked")
        chef_cap.stub!(:sudo => "stubbed")
        chef_cap.parallel_mocks << proc { |server_session|
          server_session.stub!(:put => "stubbed")
          server_session.stub!(:set => "stubbed")
          server_session.stub!(:sudo => "stubbed")
        }
        chef_cap.cap_task["chef:deploy"].call
      end

      context "using rvm" do
        it "sets up chef gem" do
          chef_cap.cap_servers.should_not be_empty
          chef_cap.should_receive(:sudo).ordered.with("`cat /tmp/.chef_cap_rvm_path` default exec gem specification --version '>=0.1982.1234' chef 2>&1 | awk 'BEGIN { s = 0 } /^name:/ { s = 1; exit }; END { if(s == 0) exit 1 }' || sudo `cat /tmp/.chef_cap_rvm_path` default exec gem install chef --no-ri --no-rdoc --version=0.1982.1234 && echo 'Chef Solo already on this server.'").and_return("mocked")
          chef_cap.should_receive(:sudo).ordered.with("`cat /tmp/.chef_cap_rvm_path` default exec which chef-solo").and_return("mocked")

          chef_cap.cap_task["bootstrap:ruby"].call
          chef_cap.cap_task["chef:setup"].call
        end

        it "installs rvm + ruby and run it if it does not exist" do
          chef_cap.cap_servers.should_not be_empty
          chef_cap.stub!(:put => "stubbed")
          chef_cap.should_receive(:sudo).ordered.with("/tmp/chef-cap-myenv-rvm-standup.sh").and_return("mocked")
          chef_cap.cap_task["bootstrap:rvm"].call
        end
      end

      context "using rbenv" do

        let(:test_dna) do
          <<-JS
        {
          "chef": {
            "root": "path_to_cookbooks",
            "version": "0.1982.1234"
          },
          "environments": {
            "some_env": {
              "rails_env": "myenv",
              "ruby_version_switcher": "rbenv",
              "servers": [
                {
                  "hostname": "localhost",
                  "roles": ["role1", "role2"]
                },
                {
                  "hostname": "otherhost.com",
                  "roles": ["role1"]
                }
              ]
            }
          },
          "roles": {
            "role1": { "run_list": ["foo"] },
            "role2": { "run_list": ["foo", "bar"] }
          }
        }
          JS
        end

        it "sets up chef gem" do
          chef_cap.cap_servers.should_not be_empty
          chef_cap.stub!(:put => "stubbed")
          chef_cap.should_receive(:run).ordered.with("`cat /tmp/.chef_cap_rbenv_path` exec gem specification --version '>=0.1982.1234' chef 2>&1 | awk 'BEGIN { s = 0 } /^name:/ { s = 1; exit }; END { if(s == 0) exit 1 }' || `cat /tmp/.chef_cap_rbenv_path` exec gem install chef --no-ri --no-rdoc --version=0.1982.1234 && echo 'Chef Solo already on this server.'").and_return("mocked")
          chef_cap.should_receive(:run).ordered.with("`cat /tmp/.chef_cap_rbenv_path` rehash").and_return("mocked")

          chef_cap.cap_task["bootstrap:ruby"].call
          chef_cap.cap_task["chef:setup"].call
        end

        it "installs rbenv + ruby and run it if it does not exist" do
          chef_cap.cap_servers.should_not be_empty
          chef_cap.stub!(:put => "stubbed")
          chef_cap.should_receive(:run).ordered.with("/tmp/chef-cap-myenv-rbenv-standup.sh").and_return("mocked")
          chef_cap.cap_task["bootstrap:rbenv"].call
        end
      end
    end

    describe "task :run_chef_solo" do

      context "with a db role" do
        before do
          @test_dna = <<-JS
        {
          "chef": {
            "root": "path_to_cookbooks"
          },
          "environments": {
            "some_env": {
              "rails_env": "myenv",
              "role_order": { "db": ["app"] },
              "servers": [
                {
                  "hostname": "dbhost",
                  "roles": ["db"]
                },
                {
                  "hostname": "apphost",
                  "roles": ["app"]
                }
              ]
            }
          },
          "roles": {
            "db": { "run_list": [] },
            "app": { "run_list": [] }
          }
        }
          JS

          chef_cap.cap_task[:some_env].should_not be_nil
          chef_cap.cap_task[:some_env].call
          chef_cap.cap_task["bootstrap:ruby"].call
          chef_cap.cap_task["chef:setup_to_run_chef_solo"].call
        end

        it "invokes chef-solo on db hosts then app and web only hosts" do
          chef_cap.cap_servers.should_not be_empty

          chef_cap.should_receive(:sudo).ordered.with(/.*chef-solo.*/, :hosts => ["dbhost"]).and_return("mocked")
          chef_cap.should_receive(:sudo).ordered.with(/.*chef-solo.*/, :hosts => ["apphost"]).and_return("mocked")
          chef_cap.cap_task["bootstrap:ruby"].call
          chef_cap.cap_task["chef:run_chef_solo"].call
        end
      end

      context "without a db role" do
        before do
          @test_dna = <<-JS
            {
              "chef": {
                "root": "path_to_cookbooks"
              },
              "environments": {
                "some_env": {
                  "rails_env": "some_env",
                  "servers": [
                    {
                      "hostname": "somehost",
                      "roles": ["somerole"]
                    }
                  ]
                }
              },
              "roles": {
                "somerole": { "run_list": [] }
              }
            }
          JS

          chef_cap.cap_task[:some_env].should_not be_nil
          chef_cap.cap_task[:some_env].call
          chef_cap.cap_task["bootstrap:ruby"].call
          chef_cap.cap_task["chef:setup_to_run_chef_solo"].call
        end


        it "works" do
          chef_cap.stub!(:sudo)
          chef_cap.cap_task["chef:run_chef_solo"].call
        end
      end

      context "with multiple dependent roles" do
        before do
          @test_dna = <<-JS
        {
          "chef": {
            "root": "path_to_cookbooks"
          },
          "environments": {
            "some_env": {
              "rails_env": "myenv",
              "role_order": { "dep0": ["dep1", "dep2"], "dep1": ["dep3"] },
               "servers": [
                {
                  "hostname": "dep0host",
                  "roles": ["dep0"]
                },
                {
                  "hostname": "dep1host",
                  "roles": ["dep1"]
                },
                {
                  "hostname": "dep2host",
                  "roles": ["dep2"]
                },
                {
                  "hostname": "dep3host",
                  "roles": ["dep3"]
                }
              ]
            }
          },
          "roles": {
            "dep0": { "run_list": [] },
            "dep1": { "run_list": [] },
            "dep2": { "run_list": [] },
            "dep3": { "run_list": [] }
          }
        }
          JS

          chef_cap.cap_task[:some_env].should_not be_nil
          chef_cap.cap_task[:some_env].call
          chef_cap.cap_task["bootstrap:ruby"].call
          chef_cap.cap_task["chef:setup_to_run_chef_solo"].call
        end

        it "invokes chef-solo on dep0 then dep1 and dep2 then finally dep3" do
          chef_cap.cap_servers.should_not be_empty

          chef_cap.should_receive(:sudo).ordered.with(anything, :hosts => ["dep0host"]).and_return("mocked")
          chef_cap.should_receive(:sudo).ordered.with(anything, :hosts => ["dep1host", "dep2host"]).and_return("mocked")
          chef_cap.should_receive(:sudo).ordered.with(anything, :hosts => ["dep3host"]).and_return("mocked")
          chef_cap.cap_task["chef:run_chef_solo"].call
        end

      end

      context "with multiple roles where some required role host is missing" do
        before do
          @test_dna = <<-JS
        {
          "chef": {
            "root": "path_to_cookbooks"
          },
          "environments": {
            "defaults": {
              "role_order": { "dep0": ["dep1"], "dep1": ["dep2", "dep3"] }
            },
            "some_env": {
              "rails_env": "myenv",
               "servers": [
                {
                  "hostname": "dep0host",
                  "roles": ["dep0", "dep4"]
                },
                {
                  "hostname": "dep2host",
                  "roles": ["dep2", "dep3"]
                }
              ]
            }
          },
          "roles": {
            "dep0": { "run_list": [] },
            "dep1": { "run_list": [] },
            "dep2": { "run_list": [] },
            "dep3": { "run_list": [] },
            "dep4": { "run_list": [] }
          }
        }
          JS

          chef_cap.cap_task[:some_env].should_not be_nil
          chef_cap.cap_task[:some_env].call
          chef_cap.cap_task["bootstrap:ruby"].call
          chef_cap.cap_task["chef:setup_to_run_chef_solo"].call
        end

        it "invokes chef-solo on dep0 then dep1 and dep2 then finally dep3" do
          chef_cap.cap_servers.should_not be_empty

          chef_cap.should_receive(:sudo).ordered.with(anything, :hosts => ["dep0host"]).and_return("mocked")
          chef_cap.should_receive(:sudo).ordered.with(anything, :hosts => ["dep2host"]).and_return("mocked")
          chef_cap.cap_task["chef:run_chef_solo"].call
        end

      end
    end

    describe "merging roles with shared" do

      before do
        @test_dna = <<-JS
        {
          "chef": {
            "root": "path_to_cookbooks"
          },
          "environments": {
            "some_env": {
              "servers": [
                {
                  "hostname": "localhost",
                  "roles": ["role1", "role2"]
                },
                {
                  "hostname": "otherhost",
                  "roles": ["role2"]
                }
              ]
            }
          },
          "shared": {
            "string": "shouldbeoverwritten",
            "simple": ["one", "two"],
            "complicated": {
              "three": { "shared": "shouldbeoverwritten", "alsoshared": ["shared"] },
              "four": "shouldbeoverwritten",
              "five": "stringtype"
            },
            "somevalue": "shouldbeoverwrittenwithnull",
            "run_list": ["shared"]
          },
          "roles": {
            "role1": {
              "string": "overwritten",
              "simple": ["merged"],
              "somevalue": null,
              "run_list": ["role1", "roleshared"]
            },
            "role2": {
              "complicated": {
                "three": { "shared": "overwritten", "alsoshared": ["merged"] },
                "four": "overwritten",
                "five": ["newtype"]
              },
              "run_list": ["role2", "roleshared"]
            }
          },
          "run_list": ["everything"]
        }
        JS
        chef_cap.stub(:system).and_return(true)
      end

      it "merges recursively all shared and all roles data down into top level keys" do
        chef_cap.stub!(:put => "stubbed")
        chef_cap.stub!(:upload => "stubbed")
        chef_cap.stub!(:sudo => "stubbed")

        chef_cap.cap_task[:some_env].call

        chef_cap.parallel_mocks << proc { |server_session|
          server_session.stub!(:put => "stubbed")
          server_session.stub!(:sudo => "stubbed")
        }

        chef_cap.cap_task["chef:deploy"].call

        chef_cap.parallel_sessions.each do |server_session|
          if server_session.things_that_were_set.keys.include? "node_hash_for_localhost"
            server_session.things_that_were_set["node_hash_for_localhost"]["simple"].should == ["one", "two", "merged"]
            server_session.things_that_were_set["node_hash_for_localhost"]["complicated"].should == {"three"=>{"alsoshared"=>["merged"], "shared"=>"overwritten"}, "four"=>"overwritten", "five"=>["newtype"]}
            server_session.things_that_were_set["node_hash_for_localhost"]["string"].should == "overwritten"
            server_session.things_that_were_set["node_hash_for_localhost"]["somevalue"].should be_nil
            server_session.things_that_were_set["node_hash_for_localhost"]["run_list"].should == ["everything", "shared", "role1", "roleshared", "role2"]
          elsif server_session.things_that_were_set.keys.include? "node_hash_for_otherhost"
            server_session.things_that_were_set["node_hash_for_otherhost"]["simple"].should == ["one", "two"]
            server_session.things_that_were_set["node_hash_for_otherhost"]["complicated"].should == {"three"=>{"alsoshared"=>["merged"], "shared"=>"overwritten"}, "four"=>"overwritten", "five"=>["newtype"]}
            server_session.things_that_were_set["node_hash_for_otherhost"]["string"].should == "shouldbeoverwritten"
            server_session.things_that_were_set["node_hash_for_otherhost"]["somevalue"].should == "shouldbeoverwrittenwithnull"
            server_session.things_that_were_set["node_hash_for_otherhost"]["run_list"].should == ["everything", "shared", "role2", "roleshared"]
          end
        end
      end
    end

    describe "node[:deploy_recipe]" do
      before do
        @test_dna = <<-JS
        {
          "chef": {
            "root": "path_to_cookbooks"
          },
          "deploy_recipe": "my_deploy_recipe",
          "environments": {
            "some_env": {
              "something_else": "okay",
              "servers": [
                {
                  "hostname": "localhost",
                  "roles": ["role1", "role2"]
                }
              ]
            }
          },
          "roles": {
            "role1": {
              "string": "overwritten",
              "simple": ["merged"],
              "run_list": ["role1", "roleshared"]
            },
            "role2": {
              "complicated": {
                "three": { "shared": "overwritten", "alsoshared": ["merged"] },
                "four": "overwritten",
                "five": ["newtype"]
              },
              "run_list": ["my_deploy_recipe", "something", "something", "darkside"]
            }
          }
        }
        JS
        chef_cap.stub(:system).and_return(true)
      end

      it "puts the specified deploy_recipe at the very end of the run list" do
        chef_cap.stub!(:put => "stubbed")
        chef_cap.stub!(:upload => "stubbed")
        chef_cap.stub!(:sudo => "stubbed")

        chef_cap.cap_task[:some_env].call

        chef_cap.parallel_mocks << proc { |server_session|
          server_session.stub!(:put => "stubbed")
          server_session.stub!(:sudo => "stubbed")
        }

        chef_cap.cap_task["chef:deploy"].call

        chef_cap.parallel_sessions.each do |server_session|
          server_session.things_that_were_set["node_hash_for_localhost"]["run_list"].should == ["role1", "roleshared", "something", "darkside", "my_deploy_recipe"]
        end
      end
    end

    describe "node[:environment]" do
      before do
        @test_dna = <<-JS
        {
          "chef": {
            "root": "path_to_cookbooks"
          },
          "environments": {
            "defaults": {
              "some_default": "yes"
            },
            "some_env": {
              "something_else": "okay",
              "servers": [
                {
                  "hostname": "localhost",
                  "roles": ["role1", "role2"]
                }
              ]
            },
            "ignored_env": {
              "should_not_be_there": "yup"
            }
          }
        }
        JS
        chef_cap.stub(:system).and_return(true)
      end

      it "contains a copy of the structure of the environment we are in that merged with the defaults" do
        chef_cap.stub!(:put => "stubbed")
        chef_cap.stub!(:upload => "stubbed")
        chef_cap.stub!(:sudo => "stubbed")

        chef_cap.cap_task[:some_env].call

        chef_cap.parallel_mocks << proc { |server_session|
          server_session.stub!(:put => "stubbed")
          server_session.stub!(:sudo => "stubbed")
        }

        chef_cap.cap_task["chef:deploy"].call

        chef_cap.parallel_sessions.each do |server_session|
          if server_session.things_that_were_set.keys.include? "node_hash_for_localhost"
            server_session.things_that_were_set["node_hash_for_localhost"]["environment"].should == {"some_default"=>"yes",
              "something_else"=>"okay",
              "servers"=>[{"primary" => [], "hostname"=>"localhost", "roles"=>["role1", "role2"]}],
              "roles" => []}
          end
        end
      end
    end

    describe "upload" do
      before do
        @test_dna = <<-JS
        {
          "chef": {
            "root": "path_to_cookbooks"
          },
          "upload": [
            {
              "source": "some_source",
              "destination": "some_destination",
              "roles": ["role1"]
            }
          ],
          "environments": {
            "defaults": {
            },
            "some_env": {
              "servers": [
                {
                  "hostname": "localhost",
                  "roles": ["role1", "role2"]
                },
                {
                  "hostname": "otherhost",
                  "roles": ["role2"]
                }
              ]
            }
          }
        }
        JS
      end

      it "defines a chef:upload task and per role tasks" do
        chef_cap.cap_task["chef:upload_all"].should_not be_nil
        chef_cap.cap_task[:chef_upload_for_role1].should_not be_nil
      end

      it "runs chef:upload before chef:deploy" do
        chef_cap.cap_before["chef:deploy"].should_not be_nil
        chef_cap.cap_before["chef:deploy"].should include("chef:upload_all")
      end

      it "takes all hashes listed and uploads the source to the destinations for the given roles" do
        pending "Need to mock out channel inside of run"
        chef_cap.cap_task[:some_env].call

        chef_cap.cap_task["chef:upload_all"].call
        chef_cap.cap_run["md5sum some_destination | cut -f1 -d ' '"].should_not be_nil
        result = chef_cap.cap_run["md5sum some_destination | cut -f1 -d ' '"]
        chef_cap.stub!(:'`' => "whatever result")
        chef_cap.should_receive(:upload).with("some_source", "some_destination", {:mode => "0644"})
        result.call("channel", "stream", "data")
      end
    end
  end

  describe "task :cook" do
    before do
      @test_dna = <<-JS
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "deploy_recipe": "my_deploy_recipe",
        "environments": {
          "some_env": {
            "servers": [
              {
                "hostname": "localhost",
                "roles": ["role1", "role2"]
              }
            ]
          }
        },
        "roles": {
          "role1": {
            "string": "overwritten",
            "simple": ["merged"],
            "run_list": ["role1", "roleshared"]
          }
        }
      }
      JS
    end

    it "defines a cook task that calls chef deploy but without the deploy recipe" do
      chef_cap.cap_task[:cook].should_not be_nil

      chef_cap.cap_task[:some_env].call

      chef_cap.cap_task[:cook].call
    end

    it "calls chef:setup before cook" do
      chef_cap.cap_before["cook"].should_not be_nil
      chef_cap.cap_before["cook"].should include("chef:setup")
    end
  end

  describe "rev environment variable" do
    before do
      @test_dna = <<-JS
      {
        "chef": {
          "root": "path_to_cookbooks"
        },
        "environments": {
          "some_env": {
            "servers": [
              {
                "hostname": "localhost",
                "roles": ["role1", "role2"]
              }
            ]
          }
        },
        "shared": {
          "foo": "bar"
        },
        "roles": {
          "role1": {
            "something": "other"
          }
        }
      }
      JS
    end

    it "shoves the value into the node json alongside branch" do
      ENV['rev'] = "123"
      ENV['branch'] = "somebranch"
      chef_cap.stub(:system).and_return(true)
      chef_cap.stub!(:put => "stubbed")
      chef_cap.stub!(:upload => "stubbed")
      chef_cap.stub!(:sudo => "stubbed")

      chef_cap.cap_task[:some_env].call
      chef_cap.parallel_mocks << proc { |server_session|
        server_session.stub!(:put => "stubbed")
        server_session.stub!(:sudo => "stubbed")
        server_session.should_receive(:set) do |key, value|
          value["environment"]["revision"].should == "123"
          value["environment"]["branch"].should == "somebranch"
        end.twice
      }
      chef_cap.cap_task["chef:deploy"].call
    end
  end

end
