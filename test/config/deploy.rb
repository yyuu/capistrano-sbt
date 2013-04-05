set :application, "capistrano-sbt"
set :repository, File.expand_path("../project", File.dirname(__FILE__))
set :deploy_to do
  File.join("/home", user, application)
end
set :deploy_via, :copy
set :scm, :none
set :use_sudo, false
set :user, "vagrant"
set :password, "vagrant"
set :ssh_options, {
  :auth_methods => %w(publickey password),
  :keys => File.join(ENV["HOME"], ".vagrant.d", "insecure_private_key"),
  :user_known_hosts_file => "/dev/null"
}

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

## sbt ##
set(:sbt_tools_path_local, File.expand_path("tmp/sbt"))
set(:sbt_project_path) { release_path }
set(:sbt_project_path_local, repository)
set(:sbt_settings_path_local, File.expand_path("tmp/sbt/global.base"))

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
  run("rm -rf #{sbt_path.dump}")
  run("rm -f #{sbt_settings.map { |x| File.join(sbt_settings_path, x).dump }.join(" ")}") unless sbt_settings.empty?
  run_locally("rm -f #{sbt_settings_local.map { |x| File.join(sbt_settings_path_local, x).dump }.join(" ")}") unless sbt_settings_local.empty?
  run("rm -rf #{sbt_target_path.dump}")
  run_locally("rm -rf #{sbt_target_path_local.dump}")
  reset_sbt!
end

def _test_sbt_exec_fails(args=[], options={})
  failed = false
  begin
    sbt.exec(args, options)
  rescue
    failed = true
  ensure
    abort unless failed
  end
end

def _test_sbt_exec_locally_fails(args=[], options={})
    failed = false
    begin
      sbt.exec_locally(args, options)
    rescue
      failed = true
    ensure
      abort unless failed
    end
end

task(:test_all) {
  find_and_execute_task("test_default")
  find_and_execute_task("test_with_remote")
  find_and_execute_task("test_with_local")
  find_and_execute_task("test_with_release_build")
  find_and_execute_task("test_with_launch_jar")
}

on(:load) {
  run("rm -rf #{deploy_to.dump}")
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
#   set(:sbt_version, "0.12.2")
    set(:sbt_use_extras, true)
    set(:sbt_setup_remotely, true)
    set(:sbt_setup_locally, true)
    set(:sbt_update_remotely, true)
    set(:sbt_update_locally, true)
    set(:sbt_template_path, File.join(File.dirname(__FILE__), "templates"))
    set(:sbt_settings, %w(global.sbt))
    set(:sbt_release_build, false)
    find_and_execute_task("sbt:setup_default_environment")
    find_and_execute_task("deploy:setup")
    find_and_execute_task("deploy")
  }

  task(:teardown) {
    uninstall_sbt!
  }

  task(:test_run_sbt) {
    assert_file_exists(sbt_bin)
    assert_file_exists(File.join(sbt_settings_path, "global.sbt"))
    assert_command("cd #{sbt_project_path.dump} && #{sbt_cmd} --version")
  }

# task(:test_run_sbt_via_sudo) {
#   assert_command("cd #{sbt_project_path.dump} && #{sbt_cmd} --version", :via => :sudo)
# }

  task(:test_run_sbt_without_path) {
    assert_command("cd #{sbt_project_path.dump} && sbt --version")
  }

  task(:test_run_sbt_via_run_locally) {
    assert_file_exists(sbt_bin_local, :via => :run_locally)
    assert_file_exists(File.join(sbt_settings_path_local, "global.sbt"), :via => :run_locally)
    assert_command("cd #{sbt_project_path_local.dump} && #{sbt_cmd_local} --version", :via => :run_locally)
  }

  task(:test_sbt_exec) {
    sbt.exec("--version")
  }

  task(:test_sbt_exec_fails) {
    _test_sbt_exec_fails("MUST-FAIL")
  }

  task(:test_sbt_exec_locally) {
    sbt.exec_locally("--version")
  }

  task(:test_sbt_exec_locally_fails) {
    _test_sbt_exec_locally_fails("MUST-FAIL")
  }

  task(:test_sbt_artifact) {
    assert_file_exists(File.join(sbt_target_path, "scala-2.10", "capistrano-sbt_2.10-0.0.1-SNAPSHOT.jar"))
  }

  task(:test_sbt_artifact_locally) {
    assert_file_exists(File.join(sbt_target_path_local, "scala-2.10", "capistrano-sbt_2.10-0.0.1-SNAPSHOT.jar"), :via => :run_locally)
  }
}

namespace(:test_with_remote) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_remote", "test_with_remote:setup"
  after "test_with_remote", "test_with_remote:teardown"

  task(:setup) {
    uninstall_sbt!
#   set(:sbt_version, "0.12.2")
    set(:sbt_use_extras, true)
    set(:sbt_setup_remotely, true)
    set(:sbt_setup_locally, false)
    set(:sbt_update_remotely, true)
    set(:sbt_update_locally, false)
    set(:sbt_template_path, File.join(File.dirname(__FILE__), "templates"))
    set(:sbt_settings, %w(global.sbt))
    set(:sbt_release_build, false)
    find_and_execute_task("sbt:setup_default_environment")
    find_and_execute_task("deploy:setup")
    find_and_execute_task("deploy")
  }

  task(:teardown) {
    uninstall_sbt!
  }

  task(:test_run_sbt) {
    assert_file_exists(sbt_bin)
    assert_file_exists(File.join(sbt_settings_path, "global.sbt"))
    assert_command("cd #{sbt_project_path.dump} && #{sbt_cmd} --version")
  }

# task(:test_run_sbt_via_sudo) {
#   assert_command("cd #{sbt_project_path.dump} && #{sbt_cmd} --version", :via => :sudo)
# }

  task(:test_run_sbt_without_path) {
    assert_command("cd #{sbt_project_path.dump} && sbt --version")
  }

  task(:test_run_sbt_via_run_locally) {
#   assert_file_not_exists(sbt_bin_local, :via => :run_locally)
    assert_file_not_exists(File.join(sbt_settings_path_local, "global.sbt"), :via => :run_locally)
#   assert_command_fails("cd #{sbt_project_path_local.dump} && #{sbt_cmd_local} --version", :via => :run_locally)
  }

  task(:test_sbt_exec) {
    sbt.exec("--version")
  }

  task(:test_sbt_exec_fails) {
    _test_sbt_exec_fails("MUST-FAIL")
  }

# task(:test_sbt_exec_locally) {
#   sbt.exec_locally("--version")
# }

# task(:test_sbt_exec_locally_fails) {
#   _test_sbt_exec_locally_fails("MUST-FAIL")
# }

  task(:test_sbt_artifact) {
    assert_file_exists(File.join(sbt_target_path, "scala-2.10", "capistrano-sbt_2.10-0.0.1-SNAPSHOT.jar"))
  }

  task(:test_sbt_artifact_locally) {
    assert_file_not_exists(File.join(sbt_target_path_local, "scala-2.10", "capistrano-sbt_2.10-0.0.1-SNAPSHOT.jar"), :via => :run_locally)
  }
}

namespace(:test_with_local) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_local", "test_with_local:setup"
  after "test_with_local", "test_with_local:teardown"

  task(:setup) {
    uninstall_sbt!
#   set(:sbt_version, "0.12.2")
    set(:sbt_use_extras, true)
    set(:sbt_setup_remotely, false)
    set(:sbt_setup_locally, true)
    set(:sbt_update_remotely, false)
    set(:sbt_update_locally, true)
    set(:sbt_template_path, File.join(File.dirname(__FILE__), "templates"))
    set(:sbt_settings, %w(global.sbt))
    set(:sbt_release_build, false)
    find_and_execute_task("sbt:setup_default_environment")
    find_and_execute_task("deploy:setup")
    find_and_execute_task("deploy")
  }

  task(:teardown) {
    uninstall_sbt!
  }

  task(:test_run_sbt) {
    assert_file_not_exists(sbt_bin)
    assert_file_not_exists(File.join(sbt_settings_path, "global.sbt"))
    assert_command_fails("cd #{sbt_project_path.dump} && #{sbt_cmd} --version")
  }

# task(:test_run_sbt_via_sudo) {
#   assert_command_fails("cd #{sbt_project_path.dump} && #{sbt_cmd} --version", :via => :sudo)
# }

  task(:test_run_sbt_without_path) {
    assert_command_fails("cd #{sbt_project_path.dump} && sbt --version")
  }

  task(:test_run_sbt_via_run_locally) {
    assert_file_exists(sbt_bin_local, :via => :run_locally)
    assert_file_exists(File.join(sbt_settings_path_local, "global.sbt"), :via => :run_locally)
    assert_command("cd #{sbt_project_path_local.dump} && #{sbt_cmd_local} --version", :via => :run_locally)
  }

# task(:test_sbt_exec) {
#   sbt.exec("--version")
# }

# task(:test_sbt_exec_fails) {
#   _test_sbt_exec_fails("MUST-FAIL")
# }

  task(:test_sbt_exec_locally) {
    sbt.exec_locally("--version")
  }

  task(:test_sbt_exec_locally_fails) {
    _test_sbt_exec_locally_fails("MUST-FAIL")
  }

  task(:test_sbt_artifact) {
    assert_file_exists(File.join(sbt_target_path, "scala-2.10", "capistrano-sbt_2.10-0.0.1-SNAPSHOT.jar"))
  }

  task(:test_sbt_artifact_locally) {
    assert_file_exists(File.join(sbt_target_path_local, "scala-2.10", "capistrano-sbt_2.10-0.0.1-SNAPSHOT.jar"), :via => :run_locally)
  }
}

namespace(:test_with_release_build) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_release_build", "test_with_release_build:setup"
  after "test_with_release_build", "test_with_release_build:teardown"

  task(:setup) {
    uninstall_sbt!
#   set(:sbt_version, "0.12.2")
    set(:sbt_use_extras, true)
    set(:sbt_setup_remotely, true)
    set(:sbt_setup_locally, true)
    set(:sbt_update_remotely, true)
    set(:sbt_update_locally, true)
    set(:sbt_template_path, File.join(File.dirname(__FILE__), "templates"))
    set(:sbt_settings, %w(global.sbt))
    set(:sbt_release_build, true)
    find_and_execute_task("sbt:setup_default_environment")
    find_and_execute_task("deploy:setup")
#   find_and_execute_task("deploy")
  }

  task(:teardown) {
    uninstall_sbt!
  }

  task(:test_build_release) {
    reset_sbt!
    begin
      File.write(File.join(sbt_project_path_local, "version.sbt"), %q{version := "0.0.1"})
      find_and_execute_task("deploy")
    ensure
      run_locally("rm -f #{File.join(sbt_project_path_local, "version.sbt").dump}")
    end
  }

  task(:test_build_snapshot) {
    reset_sbt!
    begin
      find_and_execute_task("deploy")
    rescue SystemExit
      aborted = true
    ensure
      run_locally("rm -f #{File.join(sbt_project_path_local, "version.sbt").dump}")
      abort("must fail with SNAPSHOT version") unless aborted
    end
  }
}

namespace(:test_with_launch_jar) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_launch_jar", "test_with_launch_jar:setup"
  after "test_with_launch_jar", "test_with_launch_jar:teardown"

  task(:setup) {
    uninstall_sbt!
#   set(:sbt_version, "0.12.2")
    set(:sbt_use_extras, false)
    set(:sbt_setup_remotely, true)
    set(:sbt_setup_locally, true)
    set(:sbt_update_remotely, true)
    set(:sbt_update_locally, true)
    set(:sbt_template_path, File.join(File.dirname(__FILE__), "templates"))
    set(:sbt_settings, %w(global.sbt))
    set(:sbt_release_build, false)
    find_and_execute_task("sbt:setup_default_environment")
    find_and_execute_task("deploy:setup")
    find_and_execute_task("deploy")
  }

  task(:teardown) {
    uninstall_sbt!
  }

  task(:test_run_sbt) {
    assert_file_exists(sbt_bin)
    assert_file_exists(File.join(sbt_settings_path, "global.sbt"))
    assert_command("cd #{sbt_project_path.dump} && #{sbt_cmd} --version")
  }

# task(:test_run_sbt_via_sudo) {
#   assert_command("cd #{sbt_project_path.dump} && #{sbt_cmd} --version", :via => :sudo)
# }

  task(:test_run_sbt_without_path) {
    assert_command("cd #{sbt_project_path.dump} && sbt --version")
  }

  task(:test_run_sbt_via_run_locally) {
    assert_file_exists(sbt_bin_local, :via => :run_locally)
    assert_file_exists(File.join(sbt_settings_path_local, "global.sbt"), :via => :run_locally)
    assert_command("cd #{sbt_project_path_local.dump} && #{sbt_cmd_local} --version", :via => :run_locally)
  }

  task(:test_sbt_exec) {
    sbt.exec("--version")
  }

  task(:test_sbt_exec_fails) {
    _test_sbt_exec_fails("MUST-FAIL")
  }

  task(:test_sbt_exec_locally) {
    sbt.exec_locally("--version")
  }

  task(:test_sbt_exec_locally_fails) {
    _test_sbt_exec_locally_fails("MUST-FAIL")
  }

  task(:test_sbt_artifact) {
    assert_file_exists(File.join(sbt_target_path, "scala-2.10", "capistrano-sbt_2.10-0.0.1-SNAPSHOT.jar"))
  }

  task(:test_sbt_artifact_locally) {
    assert_file_exists(File.join(sbt_target_path_local, "scala-2.10", "capistrano-sbt_2.10-0.0.1-SNAPSHOT.jar"), :via => :run_locally)
  }
}

# vim:set ft=ruby sw=2 ts=2 :
