require "capistrano-sbt/version"
require "capistrano"
require "capistrano/configuration/actions/file_transfer_ext"
require "capistrano/configuration/resources/file_resources"
require "uri"

module Capistrano
  module SBT
    def self.extended(configuration)
      configuration.load {
        namespace(:sbt) {
          _cset(:sbt_roles, [:app])
          _cset(:sbt_tools_path) { File.join(shared_path, "tools", "sbt") }
          _cset(:sbt_tools_path_local) { File.expand_path("tools/sbt") }
          _cset(:sbt_archive_path) { sbt_tools_path }
          _cset(:sbt_archive_path_local) { sbt_tools_path_local }
          _cset(:sbt_path) {
            if sbt_use_extras
              File.join(sbt_tools_path, "sbt-extras")
            else
              File.join(sbt_tools_path, "sbt-#{sbt_version}")
            end
          }
          _cset(:sbt_path_local) {
            if sbt_use_extras
              File.join(sbt_tools_path_local, "sbt-extras")
            else
              File.join(sbt_tools_path_local, "sbt-#{sbt_version}")
            end
          }
          _cset(:sbt_bin_path) { sbt_path }
          _cset(:sbt_bin_path_local) { sbt_path_local }
          _cset(:sbt_bin) { File.join(sbt_bin_path, "sbt") }
          _cset(:sbt_bin_local) { File.join(sbt_bin_path_local, "sbt") }
          _cset(:sbt_project_path) { release_path }
          _cset(:sbt_project_path_local) { File.expand_path(".") }
          _cset(:sbt_target_path) { File.join(sbt_project_path, "target") }
          _cset(:sbt_target_path_local) { File.join(sbt_project_path_local, "target") }
          _cset(:sbt_template_path) { File.expand_path("config/templates") }

          ## sbt-extras
          _cset(:sbt_use_extras, true)
          _cset(:sbt_extras_url, "https://raw.github.com/paulp/sbt-extras/master/sbt")
          _cset(:sbt_extras_file) { File.join(sbt_tools_path, "sbt") }
          _cset(:sbt_extras_file_local) { File.join(sbt_tools_path_local, "sbt") }

          ## sbt-launch.jar
          _cset(:sbt_version, "0.12.2")
          _cset(:sbt_group_id) {
            case sbt_version
            when /^0\.(?:7|10)\.\d+$/, /^0\.11\.[0-2]$/
              "org.scala-tools.sbt"
            else
              "org.scala-sbt"
            end
          }
          _cset(:sbt_launch_jar_url) {
            if exists?(:sbt_jar_url)
              logger.info(":sbt_jar_url has been deprecated. use :sbt_launch_jar_url instead.")
              fetch(:sbt_jar_url)
            else
              "http://typesafe.artifactoryonline.com/typesafe/ivy-releases/#{sbt_group_id}/sbt-launch/#{sbt_version}/sbt-launch.jar"
            end
          }
          _cset(:sbt_launch_jar) {
            if exists?(:sbt_jar_file)
              logger.info(":sbt_jar_file has been deprecated. use :sbt_launch_jar instead.")
              fetch(:sbt_jar_file)
            else
              File.join(sbt_path, "sbt-launch.jar")
            end
          }
          _cset(:sbt_launch_jar_local) {
            if exists?(:sbt_jar_file_local)
              logger.info(":sbt_jar_file_local has been deprecated. use :sbt_launch_jar_local instead.")
              fetch(:sbt_jar_file_local)
            else
              File.join(sbt_path_local, "sbt-launch.jar")
            end
          }

          ## SBT environment
          _cset(:sbt_common_environment, {})
          _cset(:sbt_default_environment) {
            environment = {}
            environment["JAVA_HOME"] = fetch(:sbt_java_home) if exists?(:sbt_java_home)
            environment["PATH"] = [ sbt_bin_path, "$PATH" ].join(":") if sbt_setup_remotely
            _merge_environment(sbt_common_environment, environment)
          }
          _cset(:sbt_default_environment_local) {
            environment = {}
            environment["JAVA_HOME"] = fetch(:sbt_java_home_local) if exists?(:sbt_java_home_local)
            environment["PATH"] = [ sbt_bin_path, "$PATH" ].join(":") if sbt_setup_locally
            _merge_environment(sbt_common_environment, environment)
          }
          _cset(:sbt_environment) { _merge_environment(sbt_default_environment, fetch(:sbt_extra_environment, {})) }
          _cset(:sbt_environment_local) { _merge_environment(sbt_default_environment_local, fetch(:sbt_extra_environment_local, {})) }
          def _command(cmdline, options={})
            environment = options.fetch(:env, {})
            if environment.empty?
              cmdline
            else
              env = (["env"] + environment.map { |k, v| "#{k}=#{v.dump}" }).join(" ")
              "#{env} #{cmdline}"
            end
          end
          def command(cmdline, options={})
            _command(cmdline, :env => sbt_environment.merge(options.fetch(:env, {})))
          end
          def command_local(cmdline, options={})
            _command(cmdline, :env => sbt_environment_local.merge(options.fetch(:env, {})))
          end
          _cset(:sbt_cmd) { command("#{sbt_bin.dump} #{sbt_options.map { |x| x.dump }.join(" ")}") }
          _cset(:sbt_cmd_local) { command_local("#{sbt_bin_local.dump} #{sbt_options_local.map { |x| x.dump }.join(" ")}") }
          _cset(:sbt_goals, %w(reload clean package))
          _cset(:sbt_common_options) {
            options = []
            if fetch(:sbt_log_noformat, true)
              if sbt_use_extras
                options << "-no-colors"
              else
                options << "-Dsbt.log.noformat=true"
              end
            end
            options
          }
          _cset(:sbt_default_options) {
            options = sbt_common_options.dup
            if sbt_update_settings
              if sbt_use_extras
                options << "-sbt-dir #{sbt_settings_path.dump}"
              else
                options << "-Dsbt.global.base=#{sbt_settings_path.dump}"
              end
            end
            options
          }
          _cset(:sbt_default_options_local) {
            options = sbt_common_options.dup
            if sbt_update_settings_locally
              if sbt_use_extras
                options += ["-sbt-dir", sbt_settings_path_local]
              else
                options << "-Dsbt.global.base=#{sbt_settings_path_local.dump}"
              end
            end
            options
          }
          _cset(:sbt_options) { sbt_default_options + fetch(:sbt_extra_options, []) }
          _cset(:sbt_options_local) { sbt_default_options_local + fetch(:sbt_extra_options_local, []) }

          _cset(:sbt_setup_remotely) { sbt_update_remotely }
          _cset(:sbt_setup_locally) { sbt_update_locally }
          _cset(:sbt_update_remotely) { not(sbt_update_locally) }
          _cset(:sbt_update_locally) { # perform update on localhost
            if exists?(:sbt_compile_locally)
              logger.info(":sbt_compile_locally has been deprecated. use :sbt_update_locally instead.")
              fetch(:sbt_compile_locally, false)
            else
              false
            end
          }

          if top.namespaces.key?(:multistage)
            after "multistage:ensure", "sbt:setup_default_environment"
          else
            on :start do
              if top.namespaces.key?(:multistage)
                after "multistage:ensure", "sbt:setup_default_environment"
              else
                setup_default_environment
              end
            end
          end

          _cset(:sbt_environment_join_keys, %w(DYLD_LIBRARY_PATH LD_LIBRARY_PATH MANPATH PATH))
          def _merge_environment(x, y)
            x.merge(y) { |key, x_val, y_val|
              if sbt_environment_join_keys.include?(key)
                ( y_val.split(":") + x_val.split(":") ).uniq.join(":")
              else
                y_val
              end
            }
          end

          task(:setup_default_environment, :roles => sbt_roles, :except => { :no_release => true }) {
            if fetch(:sbt_setup_default_environment, true)
              set(:default_environment, _merge_environment(default_environment, sbt_environment))
            end
          }

          def _invoke_command(cmdline, options={})
            if options[:via] == :run_locally
              run_locally(cmdline)
            else
              invoke_command(cmdline, options)
            end
          end

          def _download_extras(uri, filename, options={})
            execute = []
            execute << "mkdir -p #{File.dirname(filename).dump}"
            if fetch(:sbt_update_extras, true)
              t = (Time.now - fetch(:sbt_extras_check_interval, 86400).to_i).strftime("%Y%m%d%H%M")
              x = "/tmp/sbt-extras.#{$$}"
              execute << "touch -t #{t.dump} #{x.dump}"
              execute << "( test #{filename.dump} -nt #{x.dump} || wget --no-verbose -O #{filename.dump} #{uri.dump} )"
              execute << "touch #{filename.dump}"
              execute << "rm -f #{x.dump}"
              execute << "( test -x #{filename.dump} || chmod 755 #{filename.dump} )"
            else
              execute << "( test -f #{filename.dump} || wget --no-verbose -O #{filename.dump} #{uri.dump} )"
              execute << "( test -x #{filename.dump} || chmod 755 #{filename.dump} )"
            end
            _invoke_command(execute.join(" && "), options)
          end

          def _download_launch_jar(uri, filename, options={})
            execute = []
            execute << "mkdir -p #{File.dirname(filename).dump}"
            execute << "( test -f #{filename.dump} || wget --no-verbose -O #{filename.dump} #{uri.dump} )"
            _invoke_command(execute.join(" && "), options)
          end

          def _upload(filename, remote_filename, options={})
            mode = options.delete(:mode)
            _invoke_command("mkdir -p #{File.dirname(remote_filename).dump}", options)
            transfer_if_modified(:up, filename, remote_filename, fetch(:sbt_upload_options, {}).merge(options))
            if mode
              mode = mode.is_a?(Numeric) ? mode.to_s(8) : mode.to_s
              _invoke_command("chmod #{mode.dump} #{remote_filename.dump}", options)
            end
          end

          def _install_extras(filename, options={})
            # nop
          end

          def _install_launch_jar(jar, sbt, options={})
            via = options.delete(:via)
            script = (<<-EOS).gsub(/^\s*/, "") # TODO: this should be configurable
              #!/bin/sh -e
              java -Xms512M -Xmx1536M -Xss1M -XX:+CMSClassUnloadingEnabled -XX:MaxPermSize=384M -jar `dirname $0`/sbt-launch.jar "$@"
            EOS
            if via == :run_locally
              run_locally("mkdir -p #{File.dirname(sbt).dump}")
              File.write(sbt, script)
              run_locally("( test -x #{sbt.dump} || chmod 755 #{sbt.dump} )")
            else
              safe_put(script, sbt, {:mode => "755", :run_method => via}.merge(options))
            end
          end

          def _installed?(destination, options={})
            sbt = File.join(destination, "sbt")
            cmdline = "test -d #{destination.dump} && test -x #{sbt.dump}"
            _invoke_command(cmdline, options)
            true
          rescue
            false
          end

          ## setup
          desc("Setup sbt.")
          task(:setup, :roles => sbt_roles, :except => { :no_release => true }) {
            transaction {
              setup_remotely if sbt_setup_remotely
              setup_locally if sbt_setup_locally
            }
          }
          after "deploy:setup", "sbt:setup"

          task(:setup_remotely, :roles => sbt_roles, :except => { :no_release => true }) {
            if sbt_use_extras
              _download_extras(sbt_extras_url, sbt_bin_local, :via => :run_locally)
              _upload(sbt_bin_local, sbt_bin, :mode => "755")
              unless _installed?(sbt_path)
                _install_extras(sbt_bin)
              end
            else
              _download_launch_jar(sbt_launch_jar_url, sbt_launch_jar_local, :via => :run_locally)
              _upload(sbt_launch_jar_local, sbt_launch_jar, :mode => "644")
              unless _installed?(sbt_path)
                _install_launch_jar(sbt_launch_jar, sbt_bin)
              end
            end
            _installed?(sbt_path)
            update_settings if sbt_update_settings
          }

          desc("Setup sbt locally.")
          task(:setup_locally, :roles => sbt_roles, :except => { :no_release => true }) {
            if sbt_use_extras
              _download_extras(sbt_extras_url, sbt_bin_local, :via => :run_locally)
              unless _installed?(sbt_path_local, :via => :run_locally)
                _install_extras(sbt_bin_local, :via => :run_locally)
              end
            else
              _download_launch_jar(sbt_launch_jar_url, sbt_launch_jar_local, :via => :run_locally)
              unless _installed?(sbt_path_local, :via => :run_locally)
                _install_launch_jar(sbt_launch_jar_local, sbt_bin_local, :via => :run_locally)
              end
            end
            _installed?(sbt_path_local, :via => :run_locally)
            update_settings_locally if sbt_update_settings_locally
          }

          _cset(:sbt_update_settings) { sbt_setup_remotely and not(sbt_settings.empty?) }
          _cset(:sbt_update_settings_locally) { sbt_setup_locally and not(sbt_settings_local.empty?) }
          _cset(:sbt_settings_path) { File.join(sbt_project_path, "sbt") } # sbt.global.base
          _cset(:sbt_settings_path_local) { File.join(sbt_project_path_local, "sbt") } # sbt.global.base
          _cset(:sbt_settings, [])
          _cset(:sbt_settings_local) { sbt_settings }
          task(:update_settings, :roles => sbt_roles, :except => { :no_release => true }) {
            sbt_settings.each do |file|
              safe_put(template(file, :path => sbt_template_path), File.join(sbt_settings_path, file))
            end
          }

          task(:update_settings_locally, :rols => sbt_roles, :except => { :no_release => true }) {
            sbt_settings_local.each do |file|
              destination = File.join(sbt_settings_path_local, file)
              run_locally("mkdir -p #{File.dirname(destination).dump}")
              File.write(destination, template(file, :path => sbt_template_path))
            end
          }

          ## update
          desc("Update sbt build.")
          task(:update, :roles => sbt_roles, :except => { :no_release => true }) {
            transaction {
              update_remotely if sbt_update_remotely
              update_locally if sbt_update_locally
            }
          }
          _cset(:sbt_update_hook_type, :after)
          _cset(:sbt_update_hook, "deploy:finalize_update")
          on(:start) do
            [ sbt_update_hook ].flatten.each do |hook|
              send(sbt_update_hook_type, hook, "sbt:update") if hook
            end
          end

          task(:update_remotely, :roles => sbt_roles, :except => { :no_release => true }) {
            execute_remotely
          }

          desc("Update sbt build locally.")
          task(:update_locally, :roles => sbt_roles, :except => { :no_release => true }) {
            execute_locally
            upload_locally
          }

          def _parse_project_version(s)
            # FIXME: is there any better way to get project version?
            lastline = s.split(/(?:\r?\n)+/)[-1]
            lastline.split[-1]
          end

          _cset(:sbt_project_version) {
            _parse_project_version(sbt.exec(["show version"], :via => :capture))
          }
          _cset(:sbt_project_version_local) {
            _parse_project_version(sbt.exec_locally(["show version"], :via => :capture_locally))
          }
          _cset(:sbt_snapshot_pattern, /-SNAPSHOT$/i)
          def _validate_project_version(key)
            if fetch(:sbt_release_build, false)
              version = fetch(key)
              abort("Skip to build project since \`#{version}' is a SNAPSHOT version.") if sbt_snapshot_pattern === version
            end
          end

          desc("Perform sbt build.")
          task(:execute, :roles => sbt_roles, :except => { :no_release => true }) {
            execute_remotely
          }

          task(:execute_remotely, :roles => sbt_roles, :except => { :no_release => true }) {
            on_rollback do
              sbt.exec("clean")
            end
            _validate_project_version(:sbt_project_version)
            sbt.exec(sbt_goals)
          }

          desc("Perform sbt build locally.")
          task(:execute_locally, :roles => sbt_roles, :except => { :no_release => true }) {
            on_rollback {
              sbt.exec_locally("clean")
            }
            _validate_project_version(:sbt_project_version_local)
            sbt.exec_locally(sbt_goals)
          }

          task(:upload_locally, :rolse => sbt_roles, :except => { :no_release => true }) {
            on_rollback do
              run("rm -rf #{sbt_target_path.dump}")
            end
            filename = "#{sbt_target_path_local}.tar.gz"
            remote_filename = "#{sbt_target_path}.tar.gz"
            begin
              run_locally("cd #{File.dirname(sbt_target_path_local).dump} && tar chzf #{filename.dump} #{File.basename(sbt_target_path_local).dump}")
              run("mkdir -p #{File.dirname(sbt_target_path).dump}")
              top.upload(filename, remote_filename)
              run("cd #{File.dirname(sbt_target_path).dump} && tar xzf #{remote_filename.dump}")
            ensure
              run("rm -f #{remote_filename.dump}") rescue nil
              run_locally("rm -f #{filename.dump}") rescue nil
            end
          }

          def _exec_command(args=[], options={})
            args = [ args ].flatten
            sbt = options.fetch(:sbt, "sbt")
            execute = []
            execute << "cd #{options[:path].dump}" if options.key?(:path)
            execute << "#{sbt} #{args.map { |x| x.dump }.join(" ")}"
            execute.join(" && ")
          end

          ## public methods
          def exec(args=[], options={})
            cmdline = _exec_command(args, { :path => sbt_project_path, :sbt => sbt_cmd, :via => :run }.merge(options))
            _invoke_command(cmdline, options)
          end

          def exec_locally(args=[], options={})
            via = options.delete(:via)
            cmdline = _exec_command(args, { :path => sbt_project_path_local, :sbt => sbt_cmd_local, :via => :run_locally }.merge(options))
            if via == :capture_locally
              _invoke_command(cmdline, options.merge(:via => :run_locally))
            else
              logger.trace("executing locally: #{cmdline.dump}")
              elapsed = Benchmark.realtime do
                system(cmdline)
              end
              if $?.to_i > 0 # $? is command exit code (posix style)
                raise Capistrano::LocalArgumentError, "Command #{cmd} returned status code #{$?}"
              end
              logger.trace "command finished in #{(elapsed * 1000).round}ms"
            end
          end
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::SBT)
end

# vim:set ft=ruby :
