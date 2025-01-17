# frozen_string_literal: true

require 'securerandom'
require 'fileutils'
require 'erb'
require 'ostruct'

UNIQUE_FILES_DIR = './test/unique_files'

def require_unique_file(file = 'dog.rb', variables = {})
  uuid = SecureRandom.uuid
  dir = "#{UNIQUE_FILES_DIR}/#{uuid}"
  file_name = file.sub('.erb', '')
  temp_file = "#{dir}/#{file_name}"
  FileUtils.mkdir_p(Pathname.new(temp_file).dirname.to_s)
  file_contents = File.read("./test/#{file}")
  file_contents = ERB.new(file_contents).result(OpenStruct.new(variables).instance_eval { binding }) if variables.any?
  File.open(temp_file, 'w') { |w| w.write(file_contents) }
  require temp_file
  Coverband::Utils::FilePathHelper.full_path_to_relative(File.expand_path(temp_file))
end

def remove_unique_files
  FileUtils.rm_r(UNIQUE_FILES_DIR) if File.exist?(UNIQUE_FILES_DIR)
end

if defined?(Minitest)
  Minitest.after_run do
    remove_unique_files
  end
end
