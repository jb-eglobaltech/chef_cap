require File.expand_path(File.join(File.dirname(__FILE__), "spec_helper"))

describe ChefCapConfiguration do
  describe ".set_repository_settings" do
    context "the repository specific settings" do
      before do
        ENV["rev"] = "SOME_REV"
      end

      it "should set repository values for a git repository" do
        configuration = mock("Configuration")
        configuration.stub!(:repository => "git@somegitrepo")
        configuration.should_receive(:set).with(:scm, :git)
        configuration.should_receive(:set).with(:git_enable_submodules, 1)
        configuration.should_receive(:default_run_options).and_return({})
        configuration.should_receive(:depend).with(:remote, :command, "git")
        configuration.should_receive(:set).with(:revision, anything)
        ChefCapConfiguration.configuration = configuration

        ChefCapConfiguration.set_repository_settings
      end

      it "should set repository values for an svn repository" do
        configuration = mock("Configuration")
        ChefCapConfiguration.configuration = configuration
        configuration.stub!(:repository => "svn://somesvnrepo")
        configuration.should_receive(:set).with(:scm, :svn)
        configuration.should_receive(:depend).with(:remote, :command, "svn")
        configuration.should_receive(:set).with(:revision, anything)

        ChefCapConfiguration.set_repository_settings
      end
    end

    it "should set the revision variable so other capistrano tasks will have the right revision value" do
      configuration = mock("Configuration")
      ChefCapConfiguration.configuration = configuration
      configuration.stub!(:repository => nil)
      ENV["rev"] = "SOME_REV"
      configuration.should_receive(:set).with(:revision, "SOME_REV")

      ChefCapConfiguration.set_repository_settings
      ENV["rev"] = nil
    end

  end
end
