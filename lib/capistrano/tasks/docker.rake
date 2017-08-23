set_if_empty :docker_build_cmd, -> { [:docker, "build", "-t", fetch(:docker_tag_full), "."] }
set_if_empty :docker_repository_name, -> { fetch(:application) }
set_if_empty :docker_tag, -> { fetch(:branch) }
set_if_empty :docker_tag_full, -> { "#{fetch(:docker_repository_name)}:#{fetch(:docker_tag)}" }
set_if_empty :docker_remote_repository_name, -> { fetch(:docker_repository_name) }
set_if_empty :docker_remote_tag, -> { fetch(:docker_tag) }
set_if_empty :docker_remote_tag_full, -> { "#{fetch(:docker_registry) &.+ "/"}#{fetch(:docker_remote_repository_name)}:#{fetch(:docker_remote_tag)}" }
set_if_empty :keep_docker_image_count, 10

namespace :docker do
  def docker_build_base_path
    raise "Need to set :docker_build_base_dir" unless fetch(:docker_build_base_dir)
    Pathname(fetch(:docker_build_base_dir))
  end

  def docker_push(source_tag, target_tag)
    execute(:docker, :tag, source_tag, target_tag)
    execute(:docker, :push, target_tag)
  end

  desc "check directory exist"
  task :check do
    on fetch(:docker_build_server_host) do
      execute :mkdir, "-p", docker_build_base_path.dirname.to_s
      execute :git, :'ls-remote', repo_url, "HEAD"
    end
  end

  desc "Clone the repo to docker build base directory"
  task :clone => [:'docker:check'] do
    on fetch(:docker_build_server_host) do
      if test " [ -f #{docker_build_base_path}/HEAD ] "
        info t(:mirror_exists, at: docker_build_base_path.to_s)
      else
        within docker_build_base_path.dirname do
          execute :git, :clone, "--mirror", repo_url, docker_build_base_path.to_s
        end
      end
    end
  end

  desc "Update the repo mirror to reflect the origin state"
  task update_mirror: :'docker:clone' do
    on fetch(:docker_build_server_host) do
      within docker_build_base_path do
        execute :git, :remote, :update, "--prune"
      end
    end
  end

  desc "build and push docker image on remote host"
  task :build => [:'docker:update_mirror'] do
    on fetch(:docker_build_server_host) do
      within docker_build_base_path do
        timestamp = Time.now.to_i
        worktree_dir_name = "worktree-#{fetch(:docker_tag)}-#{timestamp}"

        execute(:git, :worktree, :add, worktree_dir_name, fetch(:branch))

        begin
          within worktree_dir_name do
            execute(*fetch(:docker_build_cmd))
          end
        ensure
          execute(:rm, "-rf", worktree_dir_name)
          execute(:git, :worktree, :prune)
          # Execute "git gc" manually to avoid "There are too many unreachable loose objects" warning
          execute(:git, :gc, "--auto", "--prune=3.days.ago")
        end
      end
    end
  end

  task :push => [:'docker:build'] do
    on fetch(:docker_build_server_host) do
      docker_push(fetch(:docker_tag_full), fetch(:docker_remote_tag_full))
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
