
require 'capistrano'
require 'uri'

module Capistrano
  module Sbt
    def self.extended(configuration)
      configuration.load {
        namespace(:sbt) {
          _cset(:sbt_version, '0.11.2')
          _cset(:sbt_jar_url) {
            "http://typesafe.artifactoryonline.com/typesafe/ivy-releases/org.scala-tools.sbt/sbt-launch/#{sbt_version}/sbt-launch.jar"
          }
          _cset(:sbt_jar_file) {
            File.join(shared_path, 'tools', 'sbt', "sbt-#{sbt_version}", File.basename(URI.parse(sbt_jar_url).path))
          }
          _cset(:sbt_jar_file_local) {
            File.join(File.expand_path('.'), 'tools', 'sbt', "sbt-#{sbt_version}", File.basename(URI.parse(sbt_jar_url).path))
          }
          _cset(:sbt_cmd) {
            if fetch(:sbt_java_home, nil)
              "env JAVA_HOME=#{sbt_java_home} #{sbt_java_home}/bin/java -jar #{sbt_jar_file} #{sbt_options.join(' ')}"
            else
              "java -jar #{sbt_jar_file} #{sbt_options.join(' ')}"
            end
          }
          _cset(:sbt_cmd_local) {
            if fetch(:sbt_java_home_local, nil)
              "env JAVA_HOME=#{sbt_java_home_local} #{sbt_java_home_local}/bin/java -jar #{sbt_jar_file_local} #{sbt_options_local.join(' ')}"
            else
              "java -jar #{sbt_jar_file_local} #{sbt_options_local.join(' ')}"
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
          _cset(:sbt_settings_path) {
            sbt_project_path
          }
          _cset(:sbt_settings_path_local) {
            sbt_project_path_local
          }
          _cset(:sbt_settings, [])
          _cset(:sbt_settings_local, [])
          _cset(:sbt_cleanup_settings, [])
          _cset(:sbt_cleanup_settings_local, [])
          _cset(:sbt_compile_locally, false) # perform precompilation on localhost
          _cset(:sbt_goals, %w(reload clean package))
          _cset(:sbt_common_options, [])
          _cset(:sbt_options) {
            sbt_common_options + fetch(:sbt_extra_options, [])
          }
          _cset(:sbt_options_local) {
            sbt_common_options + fetch(:sbt_extra_options_local, [])
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

          task(:install, :roles => :app, :except => { :no_release => true }) {
            run(<<-E)
              ( test -d #{File.dirname(sbt_jar_file)} || mkdir -p #{File.dirname(sbt_jar_file)} ) &&
              ( test -f #{sbt_jar_file} || wget --no-verbose -O #{sbt_jar_file} #{sbt_jar_url} ) &&
              test -f #{sbt_jar_file};
            E
          }

          task(:install_locally, :except => { :no_release => true }) { # TODO: make install and install_locally together
            run_locally(<<-E)
              ( test -d #{File.dirname(sbt_jar_file_local)} || mkdir -p #{File.dirname(sbt_jar_file_local)} ) &&
              ( test -f #{sbt_jar_file_local} || wget --no-verbose -O #{sbt_jar_file_local} #{sbt_jar_url} ) &&
              test -f #{sbt_jar_file_local};
            E
          }

          task(:update_settings, :roles => :app, :except => { :no_release => true }) {
            tmp_files = []
            on_rollback {
              run("rm -f #{tmp_files.join(' ')}") unless tmp_files.empty?
            }
            sbt_settings.each { |file|
              tmp_files << tmp_file = File.join('/tmp', File.basename(file))
              src_file = File.join(sbt_template_path, file)
              dst_file = File.join(sbt_settings_path, file)
              run(<<-E)
                ( test -d #{File.dirname(dst_file)} || mkdir -p #{File.dirname(dst_file)} ) &&
                ( test -f #{dst_file} && mv -f #{dst_file} #{dst_file}.orig; true );
              E
              if File.file?(src_file)
                put(File.read(src_file), tmp_file)
              elsif File.file?("#{src_file}.erb")
                put(ERB.new(File.read("#{src_file}.erb")).result(binding), tmp_file)
              else
                abort("sbt:update_settings: no such template found: #{src_file} or #{src_file}.erb")
              end
              run("diff #{dst_file} #{tmp_file} || mv -f #{tmp_file} #{dst_file}")
            }
            run("rm -f #{sbt_cleanup_settings.join(' ')}") unless sbt_cleanup_settings.empty?
          }

          task(:update_settings_locally, :except => { :no_release => true }) {
            sbt_settings_local.each { |file|
              src_file = File.join(sbt_template_path, file)
              dst_file = File.join(sbt_settings_path_local, file)
              run_locally(<<-E)
                ( test -d #{File.dirname(dst_file)} || mkdir -p #{File.dirname(dst_file)} ) &&
                ( test -f #{dst_file} && mv -f #{dst_file} #{dst_file}.orig; true );
              E
              if File.file?(src_file)
                File.open(dst_file, 'w') { |fp|
                  fp.write(File.read(src_file))
                }
              elsif File.file?("#{src_file}.erb")
                File.open(dst_file, 'w') { |fp|
                  fp.write(ERB.new(File.read("#{src_file}.erb")).result(binding))
                }
              else
                abort("sbt:update_settings_locally: no such template: #{src_file} or #{src_file}.erb")
              end
            }
            run_locally("rm -f #{sbt_cleanup_settings_local.join(' ')}") unless sbt_cleanup_settings_local.empty?
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

          desc("Perform sbt build.")
          task(:execute, :roles => :app, :except => { :no_release => true }) {
            on_rollback {
              run("cd #{sbt_project_path} && #{sbt_cmd} clean")
            }
            run("cd #{sbt_project_path} && #{sbt_cmd} #{sbt_goals.join(' ')}")
          }

          desc("Perform sbt build locally.")
          task(:execute_locally, :roles => :app, :except => { :no_release => true }) {
            setup_locally
            on_rollback {
              run_locally("cd #{sbt_project_path_local} && #{sbt_cmd_local} clean")
            }
            cmd = "cd #{sbt_project_path_local} && #{sbt_cmd_local} #{sbt_goals.join(' ')}"
            logger.info(cmd)
            abort("execution failure") unless system(cmd)
          }

          task(:upload_locally, :roles => :app, :except => { :no_release => true }) {
            on_rollback {
              run("rm -rf #{sbt_target_path}")
            }
            run_locally("test -d #{sbt_target_path_local}")
            run("mkdir -p #{sbt_target_path}")
            find_servers_for_task(current_task).each { |server|
              run_locally("rsync -lrt --chmod=u+rwX,go+rX #{sbt_target_path_local}/ #{user}@#{server.host}:#{sbt_target_path}/")
            }
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
