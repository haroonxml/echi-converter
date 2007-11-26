require 'rubygems'
require 'active_record'
require 'faster_csv'
require 'net/ftp'
require 'net/smtp'
require 'fileutils'
require 'uuidtools'
require 'thread'
require $workingdir + '/ftp_fetcher.rb'

class Logger
  #Change the logging format to include a timestamp
  def format_message(severity, timestamp, progname, msg)
    "#{timestamp} (#{$$}) #{msg}\n" 
  end
end

module EchiConverter
  def connect_database
    databaseconfig = $workingdir + '/../config/database.yml'
    dblogfile = $workingdir + '/../log/database.log'
    ActiveRecord::Base.logger = Logger.new(dblogfile, $config["log_number"], $config["log_length"])  
    case $config["log_level"]
      when 'FATAL'
        ActiveRecord::Base.logger.level = Logger::FATAL
      when 'ERROR'
        ActiveRecord::Base.logger.level = Logger::ERROR
      when 'WARN'
        ActiveRecord::Base.logger.level = Logger::WARN
      when 'INFO'
        ActiveRecord::Base.logger.level = Logger::INFO
      when 'DEBUG'
        ActiveRecord::Base.logger.level = Logger::DEBUG
    end
    begin
      ActiveRecord::Base.establish_connection(YAML::load(File.open(databaseconfig))) 
      @log.info "Initialized the database"
    rescue => err
      @log.fatal "Could not connect to the database - " + err
      send_email_alert "DATABASE"
    end
  end
  
  #Method to open our application log
  def initiate_logger
    logfile = $workingdir + '/../log/application.log'
    @log = Logger.new(logfile, $config["log_number"], $config["log_length"])
    case $config["log_level"]
      when 'FATAL'
        @log.level = Logger::FATAL
      when 'ERROR'
        @log.level = Logger::ERROR
      when 'WARN'
        @log.level = Logger::WARN
      when 'INFO'
        @log.level = Logger::INFO
      when 'DEBUG'
        @log.level = Logger::DEBUG
    end
  end
  
  #Method to send alert emails
  def send_email_alert reason
    begin
      Net::SMTP.start($config["smtp_server"], $config["smtp_port"]) do |smtp|
        smtp.open_message_stream('donotreply@echi-converter.rubyforge.org', [$config["alert_email_address"]]) do |f|
          f.puts "From: donotreply@echi-converter.rubyforge.org"
          f.puts "To: " + $config['alert_email_address']
          f.puts "Subject: ECHI-Converter Failure"
          case reason 
          when "DATABASE"
            f.puts "Failed to connect to the database."
          when "FTP"
            f.puts "Failed to connect to the ftp server."
          end
            f.puts " "
            f.puts "Please check the ECHI-Converter environment as soon as possible."
        end
      end
    rescue => err
      @log.warn err
    end
  end
  
  #Set the working directory to copy processed files to, if it does not exist creat it
  #Directory names based on year/month so as not to exceed 5K files in a single directory
  def set_directory working_directory
    time = Time.now
    directory_year = working_directory + "/../files/processed/" + time.year.to_s 
    directory_month = directory_year + "/" + time.month.to_s
    
    if File.exists?(directory_month) == false
      if File.exists?(directory_year) == false
        Dir.mkdir(directory_year)
      end
      Dir.mkdir(directory_month)
    end      
    
    return directory_month
  end
  
  #Method to get FTP files
  def get_ftp_files
    filelist_fetcher = FtpFetcher.new
    filequeue = filelist_fetcher.fetch_list @log
    filelist_fetcher.destroy
    
    if filequeue == nil
      return -1
    end
    
    if $config["max_ftp_sessions"] > 1 && filequeue.length > 4
      if $config["max_ftp_sessions"] > filequeue.length
        @log.info "Using " + filequeue.length.to_s + " ftp sessions to fetch files"
        my_threads = []
        cnt = 0
        while cnt < filequeue.length
          my_threads << Thread.new do
            fetcher = Fetcher.new
            result = fetcher.fetch_ftp_files filequeue, @log
            fetcher.destroy
          end
          cnt += 1
        end
        my_threads.each { |aThread|  aThread.join }
      else
        @log.info "Using " + $config["max_ftp_sessions"].to_s + " ftp sessions to fetch files"
        my_threads = []
        cnt = 0
        while cnt < $config["max_ftp_sessions"]
          my_threads << Thread.new do
            fetcher = FtpFetcher.new
            result = fetcher.fetch_ftp_files filequeue, @log
          end
          cnt += 1
        end
        my_threads.each { |aThread|  aThread.join }
      end
    else
      @log.info "Using a single ftp session to fetch the files"
      fetcher = FtpFetcher.new
      result = fetcher.fetch_ftp_files filequeue, @log
    end
    if result == false
      send_email_alert "FTP"
    end
  end
  
  #Method to write to the log table
  def log_processed_file type, filedata
    begin 
      echi_log = EchiLog.new
      echi_log.filename = filedata["name"]
      if type == 'BINARY'
        echi_log.filenumber = filedata["number"]
        echi_log.version = filedata["version"]
      end
      echi_log.records = filedata["cnt"]
      echi_log.processedat = Time.now
      echi_log.save
    rescue => err
      @log.info "Error creating ECHI_LOG entry - " + err
      return -1
    end
    return 0
  end
  
  #Method for parsing the various datatypes from the ECH file
  def dump_binary type, length
    case type
    when 'int' 
      #Process integers, assigning appropriate profile based on length
      #such as long int, short int and tiny int.
      case length
      when 4
        value = @binary_file.read(length).unpack("l").first.to_i
      when 2
        value = @binary_file.read(length).unpack("s").first.to_i
      when 1
        value = @binary_file.read(length).unpack("U").first.to_i
      end
    #Process appropriate intergers into datetime format in the database
    when 'datetime'
      case length 
      when 4
        value = @binary_file.read(length).unpack("l").first.to_i
        value = Time.at(value)
      end
    #Process strings
    when 'str'
      value = @binary_file.read(length).unpack("M").first.to_s.rstrip
    #Process individual bits that are booleans
    when 'bool'
      value = @binary_file.read(length).unpack("b8").last.to_s
    #Process that one wierd boolean that is actually an int, instead of a bit
    when 'boolint'
      value = @binary_file.read(length).unpack("U").first.to_i
      #Change the values of the field to Y/N for the varchar(1) representation of BOOLEAN
      if value == 1
        value = 'Y'
      else
        value = 'N'
      end
    end
    return value
  end
  
  #Mehtod that performs the conversions
  def convert_binary_file filename
    #Open the file to process
    echi_file = $workingdir + "/../files/to_process/" + filename
    @binary_file = open(echi_file,"rb")
    @log.debug "File size: " + @binary_file.stat.size.to_s
    
    #Read header information first
    filenumber = dump_binary 'int', 4
    @log.debug "File_number " + filenumber.to_s
    fileversion = dump_binary 'int', 4
    @log.debug "Version " + fileversion.to_s
    
    begin
      #Perform a transaction for each file, including the log table
      #in order to commit as one atomic action upon success
      EchiRecord.transaction do
        bool_cnt = 0
        @record_cnt = 0
        while @binary_file.eof == FALSE do 
          @log.debug '<====================START RECORD ' + @record_cnt.to_s + ' ====================>'
          echi_record = EchiRecord.new
          @echi_schema["echi_records"].each do | field |
            #We handle the 'boolean' fields differently, as they are all encoded as bits in a single 8-bit byte
            if field["type"] == 'bool'
              if bool_cnt == 0
                bytearray = dump_binary field["type"], field["length"]
              end
              #Ensure we parse the bytearray and set the appropriate flags
              #We need to make sure the entire array is not nil, in order to do Y/N
              #if Nil we then set all no
              if bytearray != nil
                if bytearray.slice(bool_cnt,1) == 1
                  value = 'Y'
                else
                  value = 'N'
                end
              else 
                value = 'N'
              end
              bool_cnt += 1
              if bool_cnt == 8
                bool_cnt = 0
              end
            else
              #Process 'standard' fields
              value = dump_binary field["type"], field["length"]
              @log.debug field["name"] + " { type => #{field["type"]} & length => #{field["length"]} } value => " + value.to_s
            end
            echi_record[field["name"]] = value
          end
          echi_record.save
      
          #Scan past the end of line record
          @binary_file.read(1)
          @log.debug '<====================STOP RECORD ' + @record_cnt.to_s + ' ====================>'
          @record_cnt += 1
        end
        @binary_file.close
      end
    rescue => err
        @log.info "Error processing ECHI file - " + err
    end
          
    #Move the file to the processed directory
    FileUtils.mv(echi_file, @processeddirectory)
    
    if $config["echi_process_log"] == "Y"
      log_processed_file "BINARY", { "name" => filename, "number" => filenumber, "version" => fileversion, "cnt" => @record_cnt }
    end
    
    return @record_cnt
  end

  def process_ascii filename
    echi_file = $workingdir + "/../files/to_process/" + filename
  
    begin
      #Perform a transaction for each file, including the log table
      #in order to commit as one atomic action upon success
      EchiRecord.transaction do
        @record_cnt = 0
        FasterCSV.foreach(echi_file) do |row|
          if row != nil
            @log.debug '<====================START RECORD ' + @record_cnt.to_s + ' ====================>'
            echi_record = EchiRecord.new
            cnt = 0
            @echi_schema["echi_records"].each do | field |
              if field["type"] == "bool" || field["type"] == "bool_int"
                case row[cnt]
                when "0"
                  echi_record[field["name"]] = "N"
                when "1"
                  echi_record[field["name"]] = "Y"
                end
                @log.debug field["name"] + ' == ' + row[cnt]
              else
                echi_record[field["name"]] = row[cnt]
                if row[cnt] != nil
                  @log.debug field["name"] + ' == ' + row[cnt]
                end
              end
              cnt += 1
            end
            echi_record.save
            @log.debug '<====================STOP RECORD ' + @record_cnt.to_s + ' ====================>'
            @record_cnt += 1
          end
        end
      end
    rescue => err
      @log.info "Error processing ECHI file - " + err
    end
  
    #Move the file to the processed directory
    FileUtils.mv(echi_file, @processeddirectory)
  
    if $config["echi_process_log"] == "Y"
      log_processed_file nil, { "name" => filename, "cnt" => @record_cnt }
    end
  
    return @record_cnt
  end

  def insert_dat_data tablename, row
 
    begin
      case tablename
      when "echi_agents"
        echi_dat_record = EchiAgent.new
      when "echi_aux_reasons"
        echi_dat_record = EchiAuxReason.new
      when "echi_cwcs"
        echi_dat_record = EchiCwc.new
      when "echi_vdns"
        echi_dat_record = EchiVdn.new
      end
      cnt = 0
      @echi_schema[tablename].each do | field |
        echi_dat_record[field["name"]] = row[cnt]
        cnt += 1
      end
      echi_dat_record.save
    rescue => err
      @log.info "Unable to insert " + tablename + " file record - " + err
    end
 
  end
  
  #Process the appropriate table name
  def process_proper_table file
    @record_cnt = 0
    process_file = File.open(file["filename"])
    process_file.each do |row|
      if row != nil
        field = row.rstrip.split('|')
        @log.debug '<====================START ' + file["name"] + ' RECORD ' + @record_cnt.to_s + ' ====================>'
        case file["name"]
        when "echi_agents"
          record = EchiAgent.find(:first, :conditions => [ "login_id = ? AND group_id = ?", field[1], field[0]])
        when "echi_aux_reasons"
          record = EchiAuxReason.find(:first, :conditions => [ "aux_reason = ? AND group_id = ?", field[1], field[0]])
        when "echi_cwcs"
          record = EchiCwc.find(:first, :conditions => [ "cwc = ? AND group_id = ?", field[1], field[0]])
        when "echi_vdns"
          record = EchiVdn.find(:first, :conditions => [ "vdn = ? AND group_id = ?", field[1], field[0]])
        end
        if record != nil
          if record.name != field[2]
            record.name = field[2]
            record.update
            @record_cnt += 1
            @log.debug "Updated record - " + field.inspect
          else
            @log.debug "No update required for - " + field.inspect
          end
        else
          insert_dat_data file["name"], field
          @record_cnt += 1
          @log.debug "Inserted new record - " + field.inspect
        end
      end
      @log.debug '<====================STOP ' + file["name"] + ' RECORD ' + @record_cnt.to_s + ' ====================>'
    end
    process_file.close
    
    case file["name"]
    when "echi_agents"
      filename_elements = $config["echi_agent_dat"].split(".")
    when "echi_aux_reasons"
      filename_elements = $config["echi_aux_rsn_dat"].split(".")
    when "echi_cwcs"
      filename_elements = $config["echi_cwc_dat"].split(".")
    when "echi_vdns"
      filename_elements = $config["echi_vdn_dat"].split(".")
    end
    new_filename = filename_elements[0] + "_" + UUID.timestamp_create.to_s + "." + filename_elements[1]
    target_file = @processeddirectory + "/" + new_filename
    begin
      FileUtils.mv(file["filename"], target_file)
      if $config["echi_process_log"] == "Y"
        log_processed_file nil, { "name" => new_filename, "cnt" => @record_cnt }
      end
    rescue => err
      @log.info "Unable to move processed file - " + err
    end
  end
  
  #Method to insert data into 'echi_agents' based on agname.dat
  def process_dat_files
    dat_files = Array.new
    dat_files[0] = { "name" => "echi_agents", "filename" => $workingdir + "/../files/to_process/"  + $config["echi_agent_dat"] }
    dat_files[1] = { "name" => "echi_aux_reasons", "filename" => $workingdir + "/../files/to_process/"  + $config["echi_aux_rsn_dat"] }
    dat_files[2] = { "name" =>"echi_cwcs", "filename" => $workingdir + "/../files/to_process/"  + $config["echi_cwc_dat"] }
    dat_files[3] = { "name" =>"echi_vdns", "filename" => $workingdir + "/../files/to_process/"  + $config["echi_vdn_dat"] }
    
    dat_files.each do |file|
      if File.exists?(file["filename"])
        case file["name"]
        when "echi_agents"
          EchiAgent.transaction do
            process_proper_table file
          end
        when "echi_aux_reasons"
          EchiAuxReason.transaction do
            process_proper_table file
          end
        when "echi_cwcs"
          EchiCwc.transaction do
            process_proper_table file
          end
        when "echi_vdns"
          EchiVdn.transaction do
            process_proper_table file
          end
        end
      end
    end
  end

  require $workingdir + '/echi-converter/version.rb'
end