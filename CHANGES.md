v0.1.0 (Yamashita, Yuu)

* Use [sbt-extras](https://github.com/paulp/sbt-extras) by default.
* Setup `PATH` and `JAVA_HOME` in `:default_environment`.
* Rename the module; `s/Capistrano::Sbt/Capistrano::SBT/g`
* Rename some of options:
  * `:sbt_compile_locally` -> `:sbt_update_locally`
* Changed default value of `:sbt_settings`. Now it is empty by default. You need to specify the filename explicitly.
* Add convenience methods such like `sbt.exec()`.

v0.1.1 (Yamashita, Yuu)

* Set up `:default_environment` after the loading of the recipes, not after the task start up.

v0.1.2 (Yamashita, Yuu)

* Skip setting up `:default_environment` if the installation is not requested.
* Fix a stupid bug in `sbt.exec_locally()`.
