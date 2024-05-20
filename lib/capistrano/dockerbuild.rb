require "cgi"
require "uri"

class Capistrano::Dockerbuild < Capistrano::Plugin
  def set_defaults
    set_if_empty :docker_build_cmd, -> { [:docker, "build", "-t", fetch(:docker_tag_full), "."] }
    set_if_empty :docker_repository_name, -> { fetch(:application) }
    set_if_empty :docker_tag, -> { fetch(:branch) }
    set_if_empty :docker_tag_full, -> { "#{fetch(:docker_repository_name)}:#{fetch(:docker_tag)}" }
    set_if_empty :docker_remote_repository_name, -> { fetch(:docker_repository_name) }
    set_if_empty :docker_remote_tag, -> { fetch(:docker_tag) }
    set_if_empty :docker_remote_tag_full, -> { "#{fetch(:docker_registry) &.+ "/"}#{fetch(:docker_remote_repository_name)}:#{fetch(:docker_remote_tag)}" }
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
