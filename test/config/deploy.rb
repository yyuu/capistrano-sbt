set :application, "capistrano-sbt"
set :repository,  "."
set :deploy_to do
  File.join("/home", user, application)
end
set :deploy_via, :copy
set :scm, :none
set :use_sudo, false
set :user, "vagrant"
set :password, "vagrant"
set :ssh_options, {:user_known_hosts_file => "/dev/null"}

## java ##
require "capistrano-jdk-installer"
set(:java_version_name, "7u15")
set(:java_oracle_username) { ENV["JAVA_ORACLE_USERNAME"] || abort("java_oracle_username was not set") }
set(:java_oracle_password) { ENV["JAVA_ORACLE_PASSWORD"] || abort("java_oracle_password was not set") }
set(:java_tools_path_local) { File.expand_path("tmp/java") }
set(:java_accept_license, true)
set(:java_license_title, "Oracle Binary Code License Agreement for Java SE")
set(:java_setup_remotely, true)
set(:java_setup_locally, true)

role :web, "192.168.33.10"
role :app, "192.168.33.10"
role :db,  "192.168.33.10", :primary => true

$LOAD_PATH.push(File.expand_path("../../lib", File.dirname(__FILE__)))
require "capistrano-sbt"

def _invoke_command(cmdline, options={})
  if options[:via] == :run_locally
    run_locally(cmdline)
  else
    invoke_command(cmdline, options)
  end
end

def assert_file_exists(file, options={})
  begin
    _invoke_command("test -f #{file.dump}", options)
  rescue
    logger.debug("assert_file_exists(#{file}) failed.")
    _invoke_command("ls #{File.dirname(file).dump}", options)
    raise
  end
end

def assert_file_not_exists(file, options={})
  begin
    _invoke_command("test \! -f #{file.dump}", options)
  rescue
    logger.debug("assert_file_not_exists(#{file}) failed.")
    _invoke_command("ls #{File.dirname(file).dump}", options)
    raise
  end
end

def assert_command(cmdline, options={})
  begin
    _invoke_command(cmdline, options)
  rescue
    logger.debug("assert_command(#{cmdline}) failed.")
    raise
  end
end

def assert_command_fails(cmdline, options={})
  failed = false
  begin
    _invoke_command(cmdline, options)
  rescue
    logger.debug("assert_command_fails(#{cmdline}) failed.")
    failed = true
  ensure
    abort unless failed
  end
end

def reset_sbt!
  variables.each_key do |key|
    reset!(key) if /^sbt_/ =~ key
  end
end

def uninstall_sbt!
  run("rm -f #{sbt_jar_file.dump}")
  run_locally("rm -f #{sbt_jar_file_local.dump}")
end

task(:test_all) {
  find_and_execute_task("test_default")
}

namespace(:test_default) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_default", "test_default:setup"
  after "test_default", "test_default:teardown"

  task(:setup) {
    uninstall_sbt!
    set(:sbt_version, "0.12.2")
    set(:sbt_use_extras, false)
    set(:sbt_compile_locally, true)
#   set(:sbt_update_settings, true)
#   set(:sbt_update_settings_locally, true)
    find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    reset_sbt!
    uninstall_sbt!
  }

  task(:test_run_sbt) {
    assert_file_exists(sbt_jar_file)
    assert_command("#{sbt_cmd} --version")
  }

  task(:test_run_sbt_via_run_locally) {
    assert_file_exists(sbt_jar_file_local, :via => :run_locally)
#   assert_command("#{sbt_cmd_local} --version", :via => :run_locally)
  }
}

# vim:set ft=ruby sw=2 ts=2 :
