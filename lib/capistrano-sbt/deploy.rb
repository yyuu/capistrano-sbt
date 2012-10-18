
require 'capistrano'
require 'tempfile'
require 'uri'

module Capistrano
  module Sbt
    def self.extended(configuration)
      configuration.load {
        namespace(:sbt) {
          _cset(:sbt_version, '0.11.2')
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
          _cset(:sbt_jar_file) {
            File.join(shared_path, 'tools', 'sbt', "sbt-#{sbt_version}", File.basename(URI.parse(sbt_jar_url).path))
          }
          _cset(:sbt_jar_file_local) {
            File.join(File.expand_path('.'), 'tools', 'sbt', "sbt-#{sbt_version}", File.basename(URI.parse(sbt_jar_url).path))
          }
          _cset(:sbt_use_extras, false)
          _cset(:sbt_extras_url, "https://raw.github.com/paulp/sbt-extras/master/sbt")
          _cset(:sbt_extras_file) { File.join(shared_path, 'tools', 'sbt', 'sbt') }
          _cset(:sbt_extras_file_local) { File.join(File.expand_path('.'), 'tools', 'sbt', 'sbt') }
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
          _cset(:sbt_common_options) {
            options = []
            options << "-Dsbt.log.noformat=true" if fetch(:sbt_log_noformat, true)
            options
          }
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

          def _install(options={})
            execute = []
            if sbt_use_extras
              extras_file = options.delete(:extras_file)
              extras_url = options.delete(:extras_url)
              execute << "mkdir -p #{File.dirname(extras_file)}"
              # TODO: check newer version of sbt-extras
              execute << "( test -f #{extras_file} || wget --no-verbose -O #{extras_file} #{extras_url} )"
              execute << "( test -x #{extras_file} || chmod a+x #{extras_file} )"
            else
              jar_file = options.delete(:jar_file)
              jar_url = options.delete(:jar_url)
              execute << "mkdir -p #{File.dirname(jar_file)}"
              execute << "( test -f #{jar_file} || wget --no-verbose -O #{jar_file} #{jar_url} )"
              execute << "test -f #{jar_file}"
            end
            execute.join(' && ')
          end

          task(:install, :roles => :app, :except => { :no_release => true }) {
            run(_install(:jar_file => sbt_jar_file, :jar_url => sbt_jar_url,
                         :extras_file => sbt_extras_file, :extras_url => sbt_extras_url))
          }

          task(:install_locally, :except => { :no_release => true }) {
            run_locally(_install(:jar_file => sbt_jar_file_local, :jar_url => sbt_jar_url,
                                 :extras_file => sbt_extras_file_local, :extras_url => sbt_extras_url))
          }

          def template(file)
            if File.file?(file)
              File.read(file)
            elsif File.file?("#{file}.erb")
              ERB.new(File.read(file)).result(binding)
            else
              abort("No such template: #{file} or #{file}.erb")
            end
          end

          def _update_settings(files_map, options={})
            execute = []
            dirs = files_map.map { |src, dst| File.dirname(dst) }.uniq
            execute << "mkdir -p #{dirs.join(' ')}" unless dirs.empty?
            files_map.each do |src, dst|
              execute << "( diff -u #{dst} #{src} || mv -f #{src} #{dst} )"
              cleanup = options.fetch(:cleanup, [])
              execute << "rm -f #{cleanup.join(' ')}" unless cleanup.empty?
            end
            execute.join(' && ')
          end

          task(:update_settings, :roles => :app, :except => { :no_release => true }) {
            srcs = sbt_settings.map { |f| File.join(sbt_template_path, f) }
            tmps = sbt_settings.map { |f| t=Tempfile.new('sbt');s=t.path;t.close(true);s }
            dsts = sbt_settings.map { |f| File.join(sbt_settings_path, f) }
            begin
              srcs.zip(tmps).each do |src, tmp|
                put(template(src), tmp)
              end
              run(_update_settings(tmps.zip(dsts), :cleanup => sbt_cleanup_settings)) unless tmps.empty?
            ensure
              run("rm -f #{tmps.join(' ')}") unless tmps.empty?
            end
          }

          task(:update_settings_locally, :except => { :no_release => true }) {
            srcs = sbt_settings_local.map { |f| File.join(sbt_template_path, f) }
            tmps = sbt_settings.map { |f| t=Tempfile.new('sbt');s=t.path;t.close(true);s }
            dsts = sbt_settings_local.map { |f| File.join(sbt_settings_path_local, f) }
            begin
              srcs.zip(tmps).each do |src, tmp|
                File.open(tmp, 'wb') { |fp| fp.write(template(src)) }
              end
              run_locally(_update_settings(tmps.zip(dsts), :cleanup => sbt_cleanup_settings_local)) unless tmps.empty?
            ensure
              run_locally("rm -f #{tmps.join(' ')}") unless tmps.empty?
            end
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
            on_rollback {
              run_locally("cd #{sbt_project_path_local} && #{sbt_cmd_local} clean")
            }
            cmd = "cd #{sbt_project_path_local} && #{sbt_cmd_local} #{sbt_goals.join(' ')}"
            logger.info(cmd)
            abort("execution failure") unless system(cmd)
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
