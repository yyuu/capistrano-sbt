require "capistrano-sbt/version"
require "capistrano"
require "capistrano/configuration/actions/file_transfer_ext"
require "capistrano/configuration/resources/file_resources"
require "uri"

module Capistrano
  module Sbt
    def self.extended(configuration)
      configuration.load {
        namespace(:sbt) {
          _cset(:sbt_version, '0.12.2')
          _cset(:sbt_group_id) {
            case sbt_version
            when /^0\.(?:7|10)\.\d+$/, /^0\.11\.[0-2]$/
              'org.scala-tools.sbt'
            else
              'org.scala-sbt'
            end
          }
          _cset(:sbt_jar_url) {
            "http://typesafe.artifactoryonline.com/typesafe/ivy-releases/#{sbt_group_id}/sbt-launch/#{sbt_version}/sbt-launch.jar"
          }
          _cset(:sbt_tools_path) { File.join(shared_path, "tools", "sbt") }
          _cset(:sbt_tools_path_local) { File.expand_path("tools/sbt") }
          _cset(:sbt_archive_path) { sbt_tools_path }
          _cset(:sbt_archive_path_local) { sbt_tools_path_local }
          _cset(:sbt_jar_file) { File.join(sbt_tools_path, "sbt-#{sbt_version}", File.basename(URI.parse(sbt_jar_url).path)) }
          _cset(:sbt_jar_file_local) { File.join(sbt_tools_path_local, "sbt-#{sbt_version}", File.basename(URI.parse(sbt_jar_url).path)) }
          _cset(:sbt_use_extras, true)
          _cset(:sbt_extras_url, "https://raw.github.com/paulp/sbt-extras/master/sbt")
          _cset(:sbt_extras_file) { File.join(sbt_tools_path, "sbt") }
          _cset(:sbt_extras_file_local) { File.join(sbt_tools_path_local, "sbt") }
          _cset(:sbt_extras_check_interval, 86400)
          _cset(:sbt_extras_check_timestamp) { (Time.now - sbt_extras_check_interval).strftime("%Y%m%d%H%M") }
          _cset(:sbt_cmd) {
            if fetch(:sbt_java_home, nil)
              env = "env JAVA_HOME=#{sbt_java_home.dump}"
              java = "#{sbt_java_home}/bin/java"
            else
              env = ""
              java = "java"
            end
            if sbt_use_extras
              "#{env} #{sbt_extras_file} #{sbt_options.join(' ')}".strip
            else
              "#{env} #{java} -jar #{sbt_jar_file} #{sbt_options.join(' ')}".strip
            end
          }
          _cset(:sbt_cmd_local) {
            if fetch(:sbt_java_home_local, nil)
              env = "env JAVA_HOME=#{sbt_java_home_local.dump}"
              java = "#{sbt_java_home_local}/bin/java"
            else
              env = ""
              java = "java"
            end
            if sbt_use_extras
              "#{env} #{sbt_extras_file_local} #{sbt_options_local.join(' ')}".strip
            else
              "#{env} #{java} -jar #{sbt_jar_file_local} #{sbt_options_local.join(' ')}".strip
            end
          }
          _cset(:sbt_project_path) {
            release_path
          }
          _cset(:sbt_project_path_local) {
            Dir.pwd
          }
          _cset(:sbt_target_path) {
            File.join(sbt_project_path, 'target')
          }
          _cset(:sbt_target_path_local) {
            File.join(sbt_project_path_local, File.basename(sbt_target_path))
          }
          _cset(:sbt_template_path, File.join(File.dirname(__FILE__), 'templates'))
          _cset(:sbt_update_settings, false)
          _cset(:sbt_update_settings_locally, false)
          _cset(:sbt_settings_path) { File.join(sbt_project_path, 'sbt') }
          _cset(:sbt_settings_path_local) { File.join(sbt_project_path_local, 'sbt') }
          _cset(:sbt_settings, [])
          _cset(:sbt_settings_local, [])
          _cset(:sbt_cleanup_settings, [])
          _cset(:sbt_cleanup_settings_local, [])
          _cset(:sbt_compile_locally, false) # perform precompilation on localhost
          _cset(:sbt_goals, %w(reload clean package))
          _cset(:sbt_common_options) {
            options = []
            if fetch(:sbt_log_noformat, true)
              options << if sbt_use_extras
                           "-no-colors"
                         else
                           "-Dsbt.log.noformat=true"
                         end
            end
            options
          }
          _cset(:sbt_options) {
            options = sbt_common_options + fetch(:sbt_extra_options, [])
            if sbt_update_settings
              options << if sbt_use_extras
                           "-sbt-dir #{sbt_settings_path}"
                         else
                           "-Dsbt.global.base=#{sbt_settings_path}"
                         end
            end
            options
          }
          _cset(:sbt_options_local) {
            options = sbt_common_options + fetch(:sbt_extra_options_local, [])
            if sbt_update_settings_locally
              options << if sbt_use_extras
                           "-sbt-dir #{sbt_settings_path_local}"
                         else
                           "-Dsbt.global.base=#{sbt_settings_path_local}"
                         end
            end
            options
          }

          desc("Setup sbt.")
          task(:setup, :roles => :app, :except => { :no_release => true }) {
            transaction {
              install
              update_settings if sbt_update_settings
              setup_locally if sbt_compile_locally
            }
          }
          after 'deploy:setup', 'sbt:setup'

          desc("Setup sbt locally.")
          task(:setup_locally, :except => { :no_release => true }) {
            transaction {
              install_locally
              update_settings_locally if sbt_update_settings_locally
            }
          }

          def _install(options={})
            execute = []
            if sbt_use_extras
              extras_file = options.delete(:extras_file)
              execute << "mkdir -p #{File.dirname(extras_file)}"
              x = "/tmp/sbt-extras.#{$$}"
              execute << "touch -t #{sbt_extras_check_timestamp} #{x}"
              execute << "( test #{extras_file} -nt #{x} || wget --no-verbose -O #{extras_file} #{sbt_extras_url} )"
              execute << "touch #{extras_file}"
              execute << "rm -f #{x}"
              execute << "( test -x #{extras_file} || chmod a+x #{extras_file} )"
            else
              jar_file = options.delete(:jar_file)
              execute << "mkdir -p #{File.dirname(jar_file)}"
              execute << "( test -f #{jar_file} || wget --no-verbose -O #{jar_file} #{sbt_jar_url} )"
              execute << "test -f #{jar_file}"
            end
            execute.join(' && ')
          end

          task(:install, :roles => :app, :except => { :no_release => true }) {
            run(_install(:jar_file => sbt_jar_file, :extras_file => sbt_extras_file))
          }

          task(:install_locally, :except => { :no_release => true }) {
            run_locally(_install(:jar_file => sbt_jar_file_local, :extras_file => sbt_extras_file_local))
          }

          task(:update_settings, :roles => :app, :except => { :no_release => true }) {
            sbt_settings.each do |f|
              safe_put(template(f, :path => sbt_template_path), File.join(sbt_settings_path, f))
            end
            run("rm -f #{sbt_cleanup_settings.map { |x| x.dump }.join(' ')}") unless sbt_cleanup_settings.empty?
          }

          task(:update_settings_locally, :except => { :no_release => true }) {
            sbt_settings_local.each do |f|
              File.write(File.join(sbt_settings_path_local, f), template(f, :path => sbt_template_path))
            end
            run_locally("rm -f #{sbt_cleanup_settings_local.map { |x| x.dump }.join(' ')}") unless sbt_cleanup_settings_local.empty?
          }

          desc("Update sbt build.")
          task(:update, :roles => :app, :except => { :no_release => true }) {
            transaction {
              if sbt_compile_locally
                update_locally
              else
                execute
              end
            }
          }
          after 'deploy:finalize_update', 'sbt:update'

          desc("Update sbt build locally.")
          task(:update_locally, :except => { :no_release => true }) {
            transaction {
              execute_locally
              upload_locally
            }
          }

          def _sbt(cmd, path, goals=[])
            "cd #{path.dump} && #{cmd} #{goals.map { |s| s.dump }.join(' ')}"
          end

          def _sbt_parse_version(s)
            # FIXME: is there any better way to get project version?
            lastline = s.split(/(?:\r?\n)+/)[-1]
            lastline.split[-1]
          end

          _cset(:sbt_release_build, false)
          _cset(:sbt_snapshot_pattern, /-SNAPSHOT$/i)
          _cset(:sbt_project_version) {
            _sbt_parse_version(capture(_sbt(sbt_cmd, sbt_project_path, ["show version"])))
          }
          _cset(:sbt_project_version_local) {
            _sbt_parse_version(run_locally(_sbt(sbt_cmd_local, sbt_project_path_local, ["show version"])))
          }

          def _validate_project_version(version_key)
            if sbt_release_build
              version = fetch(version_key)
              if sbt_snapshot_pattern === version
                abort("Skip to build project since \`#{version}' is a SNAPSHOT version.")
              end
            end
          end

          desc("Perform sbt build.")
          task(:execute, :roles => :app, :except => { :no_release => true }) {
            on_rollback {
              run(_sbt(sbt_cmd, sbt_project_path, %w(clean)))
            }
            _validate_project_version(:sbt_project_version)
            run(_sbt(sbt_cmd, sbt_project_path, sbt_goals))
          }

          desc("Perform sbt build locally.")
          task(:execute_locally, :roles => :app, :except => { :no_release => true }) {
            on_rollback {
              run_locally(_sbt(sbt_cmd_local, sbt_project_path_local, %w(clean)))
            }
            _validate_project_version(:sbt_project_version_local)
            cmdline = _sbt(sbt_cmd_local, sbt_project_path_local, sbt_goals)
            logger.info(cmdline)
            abort("execution failure") unless system(cmdline)
          }

          _cset(:sbt_tar, 'tar')
          _cset(:sbt_tar_local, 'tar')
          _cset(:sbt_target_archive) {
            "#{sbt_target_path}.tar.gz"
          }
          _cset(:sbt_target_archive_local) {
            "#{sbt_target_path_local}.tar.gz"
          }
          task(:upload_locally, :roles => :app, :except => { :no_release => true }) {
            on_rollback {
              run("rm -rf #{sbt_target_path} #{sbt_target_archive}")
            }
            begin
              run_locally("cd #{File.dirname(sbt_target_path_local)} && #{sbt_tar_local} chzf #{sbt_target_archive_local} #{File.basename(sbt_target_path_local)}")
              upload(sbt_target_archive_local, sbt_target_archive)
              run("cd #{File.dirname(sbt_target_path)} && #{sbt_tar} xzf #{sbt_target_archive} && rm -f #{sbt_target_archive}")
            ensure
              run_locally("rm -f #{sbt_target_archive_local}")
            end
          }
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::Sbt)
end

# vim:set ft=ruby :
