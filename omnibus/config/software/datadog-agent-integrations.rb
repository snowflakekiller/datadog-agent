# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https:#www.datadoghq.com/).
# Copyright 2018 Datadog, Inc.

require './lib/ostools.rb'
require 'json'

name 'datadog-agent-integrations'

dependency 'datadog-pip'
dependency 'datadog-agent'
dependency 'protobuf-py'

if linux?
  # add nfsiostat script
  dependency 'nfsiostat'
end

relative_path 'integrations-core'
whitelist_file "embedded/lib/python2.7"

source git: 'https://github.com/DataDog/integrations-core.git'

integrations_core_version = ENV['INTEGRATIONS_CORE_VERSION']
if integrations_core_version.nil? || integrations_core_version.empty?
  integrations_core_version = 'master'
end
default_version integrations_core_version


blacklist = [
  'datadog_checks_base',  # namespacing package for wheels (NOT AN INTEGRATION)
  'agent_metrics',
  'docker_daemon',
  'kubernetes',
  'ntp',  # provided as a go check by the core agent
]

build do
  # The dir for the confs
  if osx?
    conf_dir = "#{install_dir}/etc/conf.d"
  else
    conf_dir = "#{install_dir}/etc/datadog-agent/conf.d"
  end
  mkdir conf_dir

  # Install the checks and generate the global requirements file
  block do
    all_reqs_file = File.open("#{project_dir}/check_requirements.txt", 'w+')
    # FIX THIS these dependencies have to be grabbed from somewhere
    all_reqs_file.puts "pympler==0.5 --hash=sha256:7d16c4285f01dcc647f69fb6ed4635788abc7a7cb7caa0065d763f4ce3d21c0f"
    all_reqs_file.puts "wheel==0.30.0 --hash=sha256:e721e53864f084f956f40f96124a74da0631ac13fbbd1ba99e8e2b5e9cafdf64"\
        " --hash=sha256:9515fe0a94e823fd90b08d22de45d7bde57c90edce705b22f5e1ecf7e1b653c8"

    all_reqs_file.close

    # required by TUF for meta
    if windows?
      tuf_repo = windows_safe_path("#{install_dir}/etc/datadog-agent/repositories/")
      tuf_repo_meta = windows_safe_path("#{tuf_repo}/public-integrations-core/metadata/")
    else
      tuf_repo = "#{install_dir}/repositories/"
      tuf_repo_meta = "#{tuf_repo}/public-integrations-core/metadata/"
    end

    # Add TUF metadata
    mkdir windows_safe_path("#{tuf_repo}/cache")
    mkdir windows_safe_path("#{tuf_repo_meta}/current")
    mkdir windows_safe_path("#{tuf_repo_meta}/previous")
    if windows?
      file = File.read(windows_safe_path("#{project_dir}/.public-tuf-config.json"))
      tuf_config = JSON.parse(file)
      tuf_config['repositories_dir'] = 'c:\\ProgramData\\Datadog\\repositories'
      erb source: "public-tuf-config.json.erb",
          dest: "#{install_dir}/public-tuf-config.json",
          mode: 0640,
          vars: { tuf_config: tuf_config }
      copy_file windows_safe_path("#{project_dir}/.tuf-root.json"), windows_safe_path("#{install_dir}/etc/datadog-agent/root.json")
    else
      copy windows_safe_path("#{project_dir}/.public-tuf-config.json"), windows_safe_path("#{install_dir}/public-tuf-config.json")
      copy windows_safe_path("#{project_dir}/.tuf-root.json"), windows_safe_path("#{tuf_repo_meta}/current/root.json")
    end

    # Install all the requirements
    if windows?
      pip_args = "install  -r #{project_dir}/check_requirements.txt"
      command "#{windows_safe_path(install_dir)}\\embedded\\scripts\\pip.exe #{pip_args}"
    else
      build_env = {
        "LD_RUN_PATH" => "#{install_dir}/embedded/lib",
        "PATH" => "#{install_dir}/embedded/bin:#{ENV['PATH']}",
      }
      pip "install -r #{project_dir}/check_requirements.txt", :env => build_env
    end

    # Set frozen requirements
    pip "freeze > #{install_dir}/agent_requirements.txt"

    # Windows pip workaround to support globs
    python_bin = "\"#{windows_safe_path(install_dir)}\\embedded\\python.exe\""
    python_pip = "pip install -c #{windows_safe_path(install_dir)}\\agent_requirements.txt #{windows_safe_path(project_dir)}"
    python_pip_req = "pip install -c #{windows_safe_path(install_dir)}\\agent_requirements.txt -r #{windows_safe_path(project_dir)}"

    pinned_requirements = "#{project_dir}/datadog_checks_base/requirements.in"
    if windows?
      command("#{python_bin} -m #{python_pip}\\datadog_checks_base")
      if File.exist? pinned_requirements
        command("#{python_bin} -m #{python_pip_req}\\datadog_checks_base\\requirements.in")
      end
    else
      build_env = {
        "LD_RUN_PATH" => "#{install_dir}/embedded/lib",
        "PATH" => "#{install_dir}/embedded/bin:#{ENV['PATH']}",
      }
      pip "wheel --no-deps .", :env => build_env, :cwd => "#{project_dir}/datadog_checks_base"
      pip "install -c #{install_dir}/agent_requirements.txt *.whl", :env => build_env, :cwd => "#{project_dir}/datadog_checks_base"
      if File.exist? pinned_requirements
        pip "install -c #{install_dir}/agent_requirements.txt -rrequirements.in", :env => build_env, :cwd => "#{project_dir}/datadog_checks_base"
      end
    end

    # Set frozen requirements post `datadog_checks_base` - constraints file will be used by
    # pip to ensure all other integrations dependency sanity.
    pip "freeze > #{install_dir}/agent_requirements.txt"

    Dir.glob("#{project_dir}/*").each do |check_dir|
      check = check_dir.split('/').last

      next if !File.directory?("#{check_dir}") || blacklist.include?(check)

      # If there is no manifest file, then we should assume the folder does not
      # contain a working check and move onto the next
      manifest_file_path = "#{check_dir}/manifest.json"

      # If there is no manifest file, then we should assume the folder does not
      # contain a working check and move onto the next
      File.exist?(manifest_file_path) || next

      manifest = JSON.parse(File.read(manifest_file_path))
      manifest['supported_os'].include?(os) || next

      check_conf_dir = "#{conf_dir}/#{check}.d"
      mkdir check_conf_dir unless File.exist? check_conf_dir

      # For each conf file, if it already exists, that means the `datadog-agent` software def
      # wrote it first. In that case, since the agent's confs take precedence, skip the conf

      # Copy the check config to the conf directories
      conf_file_example = "#{check_dir}/datadog_checks/#{check}/data/conf.yaml.example"
      if File.exist? conf_file_example
        copy conf_file_example, "#{check_conf_dir}/" unless File.exist? "#{check_conf_dir}/conf.yaml.example"
      end

      # Copy the default config, if it exists
      conf_file_default = "#{check_dir}/datadog_checks/#{check}/data/conf.yaml.default"
      if File.exist? conf_file_default
        mkdir check_conf_dir
        copy conf_file_default, "#{check_conf_dir}/" unless File.exist? "#{check_conf_dir}/conf.yaml.default"
      end

      # Copy the metric file, if it exists
      metrics_yaml = "#{check_dir}/datadog_checks/#{check}/data/metrics.yaml"
      if File.exist? metrics_yaml
        mkdir check_conf_dir
        copy metrics_yaml, "#{check_conf_dir}/" unless File.exist? "#{check_conf_dir}/metrics.yaml"
      end

      # We don't have auto_conf on windows yet
      if os != 'windows'
        auto_conf_yaml = "#{check_dir}/datadog_checks/#{check}/data/auto_conf.yaml"
        if File.exist? auto_conf_yaml
          mkdir check_conf_dir
          copy auto_conf_yaml, "#{check_conf_dir}/" unless File.exist? "#{check_conf_dir}/auto_conf.yaml"
        end
      end

      File.file?("#{check_dir}/setup.py") || next
      pinned_requirements = "#{check_dir}/requirements.in"
      if windows?
        command("#{python_bin} -m #{python_pip}\\#{check}")
        if File.exist? pinned_requirements
          command("#{python_bin} -m #{python_pip_req}\\#{check}\\requirements.in")
        end
      else
        build_env = {
          "LD_RUN_PATH" => "#{install_dir}/embedded/lib",
          "PATH" => "#{install_dir}/embedded/bin:#{ENV['PATH']}",
        }
        pip "wheel --no-deps .", :env => build_env, :cwd => "#{project_dir}/#{check}"
        if File.exist? pinned_requirements
          pip "install -c #{install_dir}/agent_requirements.txt *.whl -rrequirements.in", :env => build_env, :cwd => "#{project_dir}/#{check}"
        end
      end
    end
  end
end
