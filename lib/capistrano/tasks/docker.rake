dockerbuild_plugin = self

namespace :docker do
  desc "check directory exist"
  task :check do
    on roles(:docker_build) do |host|
      execute :mkdir, "-p", dockerbuild_plugin.docker_build_base_path.dirname.to_s
      execute :git, :'ls-remote', dockerbuild_plugin.git_repo_url, "HEAD"
    end
  end

  desc "Clone the repo to docker build base directory"
  task :clone => [:'docker:check'] do
    on roles(:docker_build) do |host|
      if fetch(:docker_build_no_worktree)
        if test " [ -f #{dockerbuild_plugin.docker_build_base_path}/.git/HEAD ] "
          info "The repository is at #{dockerbuild_plugin.docker_build_base_path}"
        else
          within dockerbuild_plugin.docker_build_base_path.dirname do
            execute :git, :clone, dockerbuild_plugin.git_repo_url, dockerbuild_plugin.docker_build_base_path.to_s
          end
        end
      else
        if test " [ -f #{dockerbuild_plugin.docker_build_base_path}/HEAD ] "
          info t(:mirror_exists, at: dockerbuild_plugin.docker_build_base_path.to_s)
        else
          within dockerbuild_plugin.docker_build_base_path.dirname do
            execute :git, :clone, "--mirror", dockerbuild_plugin.git_repo_url, dockerbuild_plugin.docker_build_base_path.to_s
          end
        end
      end
    end
  end

  desc "Update the repo mirror to reflect the origin state"
  task update_mirror: :'docker:clone' do
    on roles(:docker_build) do |host|
      within dockerbuild_plugin.docker_build_base_path do
        execute :git, :remote, "set-url", :origin, dockerbuild_plugin.git_repo_url
        execute :git, :remote, :update, "--prune"
      end
    end
  end

  desc "build docker image on remote host"
  task :build => [:'docker:update_mirror'] do
    on roles(:docker_build) do |host|
      build_cmd = fetch(:docker_build_cmd)
      if build_cmd.is_a?(Proc)
        if build_cmd.arity != 0
          build_cmd = build_cmd.call(host)
        else
          build_cmd = build_cmd.call
        end
      end
      within dockerbuild_plugin.docker_build_base_path do
        if fetch(:docker_build_no_worktree)
          commands = "sha1=$(git rev-parse #{fetch(:branch)}); git reset --hard ${sha1}; #{build_cmd.map {|c| c.to_s.shellescape }.join(" ")}"
          execute(:flock, "capistrano_dockerbuild.lock", "-c", "'#{commands}'")
        else
          timestamp = Time.now.to_i
          git_sha1 = `git rev-parse #{fetch(:branch)}`.chomp
          worktree_dir_name = "worktree-#{git_sha1}-#{timestamp}"

          execute(:git, :worktree, :add, worktree_dir_name, git_sha1)

          begin
            within worktree_dir_name do
              execute(*build_cmd)
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

  desc "push docker image on remote host"
  task :push => [:'docker:build'] do
    on roles(:docker_build) do |host|
      docker_tag_with_arch = fetch(:docker_tag_with_arch).call(host)
      execute(:docker, :push, docker_tag_with_arch)
      if fetch(:docker_latest_tag)
        arch_suffix = host.properties.arch ? "-#{host.properties.arch}" : ""
        latest_tag = docker_tag_with_arch.split(":").first + ":latest" + arch_suffix
        execute(:docker, :tag, docker_tag_with_arch, latest_tag)
        execute(:docker, :push, latest_tag)
      end
    end

    archs = roles(:docker_build).map { |host| host.properties.arch }.compact.uniq
    unless archs.empty?
      on roles(:docker_build).take(1) do |host|
        manifest_tags = archs.map do |arch|
          arch_suffix = "-#{arch}"
          fetch(:docker_tag) + arch_suffix
        end
        execute(:docker, :manifest, :create, "--amend", fetch(:docker_tag), *manifest_tags)
        execute(:docker, :manifest, :push, "--purge", fetch(:docker_tag))

        if fetch(:docker_latest_tag)
          latest_tag = fetch(:docker_tag).split(":").first + ":latest"
          execute(:docker, :manifest, :create, "--amend", latest_tag, *manifest_tags)
          execute(:docker, :manifest, :push, "--purge", latest_tag)
        end
      end
    end
  end

  task :push_unless_exists => [:'docker:build'] do
    on roles(:docker_build).take(1) do
      unless test "docker manifest inspect #{fetch(:docker_tag)}"
        invoke "docker:push"
      end
    end
  end

  task :cleanup_local_images do
    on roles(:docker_build) do |host|
      local_images = []
      capture(:docker, "images --format='{{.ID}}\t{{.Repository}}\t{{.CreatedAt}}'").split("\n").map do |line|
        id, repository, created_at = line.split("\t")
        if repository == fetch(:docker_tag).split(":").first
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
