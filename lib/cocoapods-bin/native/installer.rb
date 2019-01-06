require 'parallel'
require 'cocoapods'
require 'cocoapods-bin/native/pod_source_installer'

module Pod
	class Installer
		alias_method :old_create_pod_installer, :create_pod_installer
		def create_pod_installer(pod_name)
			installer = old_create_pod_installer(pod_name)
			installer.installation_options = installation_options
			installer
		end

		# rewrite install_pod_sources
		alias_method :old_install_pod_sources, :install_pod_sources
    def install_pod_sources
    	if installation_options.install_with_multi_processes
	      @installed_specs = []
	      pods_to_install = sandbox_state.added | sandbox_state.changed
	      title_options = { :verbose_prefix => '-> '.green }
	      # 多进程下载，多线程时 log 会显著交叉，多进程好点，但是多进程需要利用文件锁对 cache 进行保护
	      # in_processes: 10
	      Parallel.each(root_specs.sort_by(&:name), in_threads: 10) do |spec|
	        if pods_to_install.include?(spec.name)
	          if sandbox_state.changed.include?(spec.name) && sandbox.manifest
	            current_version = spec.version
	            previous_version = sandbox.manifest.version(spec.name)
	            has_changed_version = current_version != previous_version
	            current_repo = analysis_result.specs_by_source.detect { |key, values| break key if values.map(&:name).include?(spec.name) }
	            current_repo &&= current_repo.url || current_repo.name
	            previous_spec_repo = sandbox.manifest.spec_repo(spec.name)
	            has_changed_repo = !previous_spec_repo.nil? && current_repo && (current_repo != previous_spec_repo)
	            title = "Installing #{spec.name} #{spec.version}"
	            title << " (was #{previous_version} and source changed to `#{current_repo}` from `#{previous_spec_repo}`)" if has_changed_version && has_changed_repo
	            title << " (was #{previous_version})" if has_changed_version && !has_changed_repo
	            title << " (source changed to `#{current_repo}` from `#{previous_spec_repo}`)" if !has_changed_version && has_changed_repo
	          else
	            title = "Installing #{spec}"
	          end
	          UI.titled_section(title.green, title_options) do
	            install_source_of_pod(spec.name)
	          end
	        else
	          UI.titled_section("Using #{spec}", title_options) do
	            create_pod_installer(spec.name)
	          end
	        end
	      end
	    else
	    	old_install_pod_sources
	    end
    end
	end

  module Downloader
    class Cache
    	# 多线程锁
    	@@lock = Mutex.new

    	# 后面如果要切到进程的话，可以在 cache root 里面新建一个文件
    	# 利用这个文件 lock
    	# https://stackoverflow.com/questions/23748648/using-fileflock-as-ruby-global-lock-mutex-for-processes

    	# rmtree 在多进程情况下可能  Directory not empty @ dir_s_rmdir 错误
    	# old_ensure_matching_version 会移除不是同一个 CocoaPods 版本的组件缓存
    	alias_method :old_ensure_matching_version, :ensure_matching_version
    	def ensure_matching_version
    		@@lock.synchronize { old_ensure_matching_version }
    	end

    end
  end
end