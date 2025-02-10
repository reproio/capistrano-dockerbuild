# Capistrano::Dockerbuild

Capistrano tasks for `docker build` on remote server.

These tasks depends on Git.
And so remote server must have git command.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'capistrano-dockerbuild'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-dockerbuild

## Usage

Add `require` and `install_plugin` to Capfile.

```ruby
require 'capistrano/dockerbuild'
install_plugin Capistrano::Dockerbuild
```

```ruby
# deploy.rb

set :application, :sample_project

set :repo_url, 'git@github.com:example/example.git'

set :git_sha1, `git rev-parse HEAD`.chomp

set :branch, fetch(:git_sha1)

set :ssh_user, ENV["SSH_USER"] || ENV["USER"] || Etc.getlogin

set :ssh_options, {
  user: fetch(:ssh_user),
  port: 22,
  use_agent: true,
}

# add :docker_build role to server definition
# add :arch property to server definition
server "docker-build-amd64.example.com", roles: [:docker_build], ssh_options: fetch(:ssh_options), arch: "amd64"
server "docker-build-arm64.example.com", roles: [:docker_build], ssh_options: fetch(:ssh_options), arch: "arm64"

set :docker_registry, "ghcr.io"
set :docker_build_base_dir, "/home/#{fetch(:ssh_user)}/#{fetch(:application)}"

# if docker_build_cmd is proc and has more than 1 arity, pass host object.
set :docker_build_cmd, ->(host) {
  [:docker, "build", "-f", "Dockerfile", "-t", fetch(:docker_tag_with_arch).call(host), "--build-arg", "host=#{host}", "."]
}
set :docker_tag, "ghcr.io/NAMESPACE/IMAGE_NAME:#{fetch(:git_sha1)}"
```

If any servers have `arch` property, this plugin enables multi architecture mode.

The behavior of multi architecture mode is following.

1. build image with a arch suffix like `-amd64`
1. push the image
1. create a manifest list of pushed images and push it on first server

## Variables

#### Common Variables
Use common variables
- repo_url
- branch

| name                          | required | default                                                                                                            | desc                                                                                     |
| ----                          | ----     | ----                                                                                                               | ----                                                                                     |
| docker_build_base_dir         | yes      | nil                                                                                                                | Repository clone to here, and execute build command here                                 |
| docker_build_cmd              | no       | `->(host) { [:docker, :build, "-t", fetch(:docker_tag_with_arch).call(host), "."] }`                                                    | Execute command for image building                                                       |
| docker_tag                    | no       | `-> { fetch(:application) + ":" + fetch(:branch) }`                                                                                            | Use by `docker tag repository:{{docker_tag}}`                                            |
| docker_latest_tag       | no       | false                                                                                                                 | Add latest tag to building image                                                         |
| keep_docker_image_count       | no       | 10                                                                                                                 |                                                                                          |
| git_http_username             | no       | nil                                                                                                                | See below                                                                                |
| git_http_password             | no       | nil                                                                                                                | See below                                                                                |

If you want to use GitHub Apps installation access token or something to authorize repository access using HTTPS protocol. You can set variables in your config/deploy.rb:

```ruby
set :git_http_username, -> { ENV["GIT_HTTP_USERNAME"] }
set :git_http_password, -> { ENV["GIT_HTTP_PASSWORD"] }
set :repo_url, -> do
  if fetch(:git_http_username) && fetch(:git_http_password)
    "https://github.com/owner/repo.git"
  else
    "git@github.com:owner/repo.git"
  end
end
```

Update remote URL always if you set proper value to all of `repo_url`, `git_http_username`, and `git_http_password`.

## Tasks

#### docker:check
- Ensure `#{docker_build_base_dir}`
- Ensure git reachable

#### docker:clone
- Clone repo to `#{docker_build_base_dir}` as mirror

#### docker:update_mirror
- git remote update `#{docker_build_base_dir}`

#### docker:build
- Create `#{branch}` worktree to `#{docker_tag}-#{timestamp}`
- With in worktree dir, execute `#{docker_build_cmd}`
- Clear worktree

#### docker:push
- docker push `#{docker_tag}`

#### docker:cleanup_local_images
- Remove docker images
- Leave `keep_docker_image_count` images
- Remove from the oldest image

## Task Dependency

docker:push => docker:build => docker:update_mirror => docker:clone => docker:check

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/reproio/capistrano-dockerbuild.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
