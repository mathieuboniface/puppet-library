# Puppet Library
# Copyright (C) 2014 drrb
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'fileutils'
require 'monitor'
require 'time'
require 'puppet_library/util/temp_dir'

module PuppetLibrary::Util
    class Git
        DEFAULT_CACHE_TTL_SECONDS = 60
        def initialize(source, cache_path, cache_ttl_seconds = DEFAULT_CACHE_TTL_SECONDS)
            @source = source
            @cache_path = File.expand_path(cache_path)
            @cache_ttl_seconds = cache_ttl_seconds
            @git_dir = File.join(@cache_path, ".git")
            @mutex = Monitor.new
        end

        def tags
            update_cache!
            git("tag").split
        end

        def on_tag(tag)
            update_cache!
            PuppetLibrary::Util::TempDir.use "git" do |path|
                git "checkout #{tag}", path
                yield
            end
        end

        def read_file(path, tag)
            update_cache!
            git "show refs/tags/#{tag}:#{path}"
        end

        def clear_cache!
            @mutex.synchronize do
                FileUtils.rm_rf @cache_path
            end
        end

        def update_cache!
            create_cache unless cache_exists?
            update_cache if cache_stale?
        end

        private
        def create_cache
            @mutex.synchronize do
                git "clone --bare #{@source} #{@git_dir}" unless cache_exists?
                FileUtils.touch fetch_file
            end
        end

        def update_cache
            @mutex.synchronize do
                git "fetch --tags"
            end
        end

        def cache_exists?
            File.directory? @git_dir
        end

        def cache_stale?
            Time.now - last_fetch > @cache_ttl_seconds
        end

        def last_fetch
            if File.exist? fetch_file
                File.stat(fetch_file).mtime
            else
                Time.at(0)
            end
        end

        def fetch_file
            File.join(@git_dir, "FETCH_HEAD")
        end

        def git(command, work_tree = nil)
            work_tree = @cache_path unless work_tree
            Open3.popen3("git --git-dir=#{@git_dir} --work-tree=#{work_tree} #{command}") do |stdin, stdout, stderr, thread|
                stdout.read
            end
        end
    end
end