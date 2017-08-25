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

## Variables

#### Common Variables
Use common variables
- repo_url
- branch

| name                          | required | default                                                                                                            | desc                                                                                     |
| ----                          | ----     | ----                                                                                                               | ----                                                                                     |
| docker_build_server_host      | yes      | nil                                                                                                                | Build server hostname or SSH::Host object                                                |
| docker_build_base_dir         | yes      | nil                                                                                                                | Repository clone to here, and execute build command here                                 |
| docker_registry               | no       | nil                                                                                                                | Docker registry hostname. if use DockerHub, keep nil                                     |
| docker_build_cmd              | no       | `-> { [:docker, "build", "-t", fetch(:docker_tag_full), "."] }`                                                    | Execute command for image building                                                       |
| docker_repository_name        | no       | `-> { fetch(:application) }`                                                                                       | Use by `docker tag {{docker_repository_name}}:tag`                                       |
| docker_tag                    | no       | `-> { fetch(:branch) }`                                                                                            | Use by `docker tag repository:{{docker_tag}}`                                            |
| docker_tag_full               | no       | `-> { #{fetch(:docker_repository_name)}:#{fetch(:docker_tag)}" }`                                                  | Use by `docker tag {{docker_tag_full}}`                                                  |
| docker_remote_repository_name | no       | `-> { fetch(:docker_repository_name) }`                                                                            | Use by `docker push docker_registry/{{docker_remote_repository_name}}:docker_remote_tag` |
| docker_remote_tag             | no       | `-> { fetch(:docker_tag) }`                                                                                        | Use by `docker push docker_registry/docker_remote_repository_name:{{docker_remote_tag}}` |
| docker_remote_tag_full        | no       | `-> { "#{fetch(:docker_registry) &.+ "/"}#{fetch(:docker_remote_repository_name)}:#{fetch(:docker_remote_tag)}" }` | Use by `docker push {{docker_remote_tag_full}}`                                          |
| keep_docker_image_count       | no       | 10                                                                                                                 |                                                                                          |


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
- docker tag `#{docker_tag_full}` `#{docker_remote_tag_full}`
- docker push `#{docker_remote_tag_full}`

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
