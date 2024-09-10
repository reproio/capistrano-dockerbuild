dockerbuild_plugin = self

namespace :docker do
  desc "check directory exist"
  task :check do
    on fetch(:docker_build_server_host) do
      execute :mkdir, "-p", dockerbuild_plugin.docker_build_base_path.dirname.to_s
      execute :git, :'ls-remote', repo_url, "HEAD"
    end
  end

  desc "Clone the repo to docker build base directory"
  task :clone => [:'docker:check'] do
    on fetch(:docker_build_server_host) do
      if fetch(:docker_build_no_worktree)
        if test " [ -f #{dockerbuild_plugin.docker_build_base_path}/.git/HEAD ] "
          info "The repository is at #{dockerbuild_plugin.docker_build_base_path}"
        else
          within dockerbuild_plugin.docker_build_base_path.dirname do
            execute :git, :clone, repo_url, dockerbuild_plugin.docker_build_base_path.to_s
          end
        end
      else
        if test " [ -f #{dockerbuild_plugin.docker_build_base_path}/HEAD ] "
          info t(:mirror_exists, at: dockerbuild_plugin.docker_build_base_path.to_s)
        else
          within dockerbuild_plugin.docker_build_base_path.dirname do
            execute :git, :clone, "--mirror", repo_url, dockerbuild_plugin.docker_build_base_path.to_s
          end
        end
      end
    end
  end

  desc "Update the repo mirror to reflect the origin state"
  task update_mirror: :'docker:clone' do
    on fetch(:docker_build_server_host) do
      within dockerbuild_plugin.docker_build_base_path do
        execute :git, :remote, :update, "--prune"
      end
    end
  end

  desc "build and push docker image on remote host"
  task :build => [:'docker:update_mirror'] do
    on fetch(:docker_build_server_host) do
      within dockerbuild_plugin.docker_build_base_path do
        if fetch(:docker_build_no_worktree)
          commands = "sha1=$(git rev-parse #{fetch(:branch)}); git reset --hard ${sha1}; #{fetch(:docker_build_cmd).map {|c| c.to_s.shellescape }.join(" ")}"
          execute(:flock, "capistrano_dockerbuild.lock", "-c", "'#{commands}'")
        else
          timestamp = Time.now.to_i
          git_sha1 = `git rev-parse #{fetch(:branch)}`.chomp
          worktree_dir_name = "worktree-#{git_sha1}-#{timestamp}"

          execute(:git, :worktree, :add, worktree_dir_name, git_sha1)

          begin
            within worktree_dir_name do
              execute(*fetch(:docker_build_cmd))
            end
          ensure
            execute(:rm, "-rf", worktree_dir_name)
            execute(:git, :worktree, :prune)
            # Execute "git gc" manually to avoid "There are too many unreachable loose objects" warning
            execute(:git, :gc, "--auto", "--prune=#{fetch(:git_gc_prune_date)}")
          end
        end
      end
    end
  end

  task :push => [:'docker:build'] do
    on fetch(:docker_build_server_host) do
      execute(:docker, :tag, fetch(:docker_tag_full), fetch(:docker_remote_tag_full))
      execute(:docker, :push, fetch(:docker_remote_tag_full))
      if fetch(:docker_latest_tag)
        latest_tag = "#{fetch(:docker_registry) &.+ "/"}#{fetch(:docker_remote_repository_name)}:latest"
        execute(:docker, :tag, fetch(:docker_tag_full), latest_tag)
        execute(:docker, :push, latest_tag)
      end
    end
  end

  task :push_unless_exists => [:'docker:build'] do
    on fetch(:docker_build_server_host) do
      unless test "docker manifest inspect #{fetch(:docker_remote_tag_full)}"
        invoke "docker:push"
      end
    end
  end

  task :cleanup_local_images do
    on fetch(:docker_build_server_host) do
      local_images = []
      capture(:docker, "images --format='{{.ID}}\t{{.Repository}}\t{{.CreatedAt}}'").split("\n").map do |line|
        id, repository, created_at = line.split("\t")
        if repository == fetch(:docker_repository_name)
          local_images << { id: id, created_at: created_at }
        end
      end
      local_images.uniq!  # Same image could exist in different repository.
      if local_images.size > fetch(:keep_docker_image_count)
        deleting_image_ids = local_images.sort_by { |i| i[:created_at] }.first(local_images.size - fetch(:keep_docker_image_count)).map { |i| i[:id] }
        execute(:docker, "rmi -f #{deleting_image_ids.join(" ")}")
      end
    end
  end
end
