require "cgi"
require "uri"

class Capistrano::Dockerbuild < Capistrano::Plugin
  def set_defaults
    set_if_empty :docker_tag, -> { fetch(:application) + ":" + fetch(:branch) }
    set :docker_tag_with_arch, ->(host) do
      arch_suffix = host.properties.arch ? "-#{host.properties.arch}" : ""
      fetch(:docker_tag) + arch_suffix
    end
    set_if_empty :docker_build_cmd, ->(host) do
      [:docker, :build, "-t", fetch(:docker_tag_with_arch).call(host), "."]
    end
    set_if_empty :docker_latest_tag, false
    set_if_empty :keep_docker_image_count, 10
    set_if_empty :git_gc_prune_date, "3.days.ago"
    set_if_empty :docker_build_no_worktree, false
  end

  def define_tasks
    eval_rakefile File.expand_path("../tasks/docker.rake", __FILE__)
  end

  def docker_build_base_path
    raise "Need to set :docker_build_base_dir" unless fetch(:docker_build_base_dir)
    Pathname(fetch(:docker_build_base_dir))
  end

  def git_repo_url
    if fetch(:git_http_username) && fetch(:git_http_password)
      URI.parse(repo_url).tap do |repo_uri|
        repo_uri.user     = fetch(:git_http_username)
        repo_uri.password = CGI.escape(fetch(:git_http_password))
      end.to_s
    elsif fetch(:git_http_username)
      URI.parse(repo_url).tap do |repo_uri|
        repo_uri.user = fetch(:git_http_username)
      end.to_s
    else
      repo_url
    end
  end
end
