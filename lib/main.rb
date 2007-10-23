require 'rubygems'
require 'yaml'

#Determine our working directory
@workingdirectory = File.expand_path(File.dirname(__FILE__))
require @workingdirectory + '/echi-converter.rb'
include EchiConverter

#Open the configuration file
configfile = @workingdirectory + '/../config/application.yml' 
@config = YAML::load(File.open(configfile))

#Load ActiveRecord Models
require @workingdirectory + '/database.rb'

#Load the configured schema
schemafile = @workingdirectory + "/../config/" + @config["echi_schema"]
@echi_schema = YAML::load(File.open(schemafile))

#Open the logfile with appropriate output level
initiate_logger
  
#If configured for database insertion, connect to the database
if @config["export_type"] == 'database' || @config["export_type"] == 'both'
  connect_database
end

@log.info "Running..."

loop do
  #Process the files
  ftp_files = fetch_ftp_files
  #Grab filenames from the to_process directory after an FTP fetch, so if the 
  #system fails it may pick up where it left off
  to_process_dir = @workingdirectory + "/../files/to_process/"
  
  #Establish where to copy the processed files to
  @processeddirectory = set_directory(@workingdirectory)
  
  Dir.entries(to_process_dir).each do | file |
    if file != "." && file != ".."
      if @config["echi_format"] == 'BINARY'
        record_cnt = convert_binary_file file
      elsif @config["echi_format"] == 'ASCII'
        record_cnt = process_ascii file
      end
    end
    @log.info "Processed file #{file} with #{record_cnt.to_s} records"
  end

  sleep @config["fetch_interval"]

  #Make sure we did not lose our database connection while we slept
  if ActiveRecord::Base.connected? == 'FALSE'
    connect_database
  end
end

#Close the logfile
@log.info "Shutdown..."
@log.close