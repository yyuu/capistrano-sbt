# capistrano-sbt

a capistrano recipe to deploy [sbt](https://github.com/harrah/xsbt) based projects.

## Installation

Add this line to your application's Gemfile:

    gem 'capistrano-sbt'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-sbt

## Usage

This recipes will try to do following things during Capistrano `deploy:setup` and `deploy` tasks.

1. Download and install sbt for current project
2. Prepare optional `*.sbt` for current project (optional)
3. Build sbt project remotely (default) or locally

To build you sbt projects during Capistrano `deploy` tasks, add following in you `config/deploy.rb`. By default, sbt build will run after the Capistrano's `deploy:finalize_update`.

    # config/deploy.rb
    require "capistrano-sbt"

Following options are available to manage your sbt build.

 * `:sbt_use_extras` - Use [sbt-extras](https://github.com/paulp/sbt-extras) to manage sbt. `true` by default.
 * `:sbt_extras_url` - The download url of sbt-extras.
 * `:sbt_version` - If `:sbt_use_extras` was set as `false`, download specified version of `sbt-launch.jar` and set it up as `sbt`. If no version was given, try loading version from `project/build.properties`.
 * `:sbt_setup_remotely` - Setup `sbt` on remote servers. As same value as `:sbt_update_remotely` by default.
 * `:sbt_setup_locally` - Setup `sbt` on local server. Asa same value as `:sbt_update_locally` by default.
 * `:sbt_update_remotely` - Run `sbt` on remote servers. `true` by default.
 * `:sbt_update_locally` - Run `sbt` on local server. `false` by default.
 * `:sbt_goals` - The `sbt` commands and tasks to be be executed. Run `reload clean package` by default.
 * `:sbt_project_path` - The project path to be built on remote servers.
 * `:sbt_project_path_local` - The project path to be built on local server.
 * `:sbt_settings` - List of optional `*.sbt` files for remote servers.
 * `:sbt_settings_local` - List of optional `*.sbt` files for local server.
 * `:sbt_template_path` - The local path where the templates of `*.sbt` are in. By default, searches from `config/templates`.
 * `:sbt_settings_path` - The destination path of the optional `*.sbt` files.
 * `:sbt_settings_path_local` - The destination path of the optional `*.sbt` files.
 * `:sbt_java_home` - Optional `JAVA_HOME` settings for `sbt` on remote servers.
 * `:sbt_java_home_local` - Optional `JAVA_HOME` settings for `sbt` on local server.
 * `:sbt_log_noformat` - Do not colorize `sbt` outputs. `true` by default.
 * `:sbt_release_build` - Skip building on SNAPSHOT version. `false` by default.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

- YAMASHITA Yuu (https://github.com/yyuu)
- Geisha Tokyo Entertainment Inc. (http://www.geishatokyo.com/)

## License

MIT
