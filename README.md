The ECHI (External Call History Interface) Converter
-------------

Provides a Ruby based utility for fetching Avaya CMS / ECHI files in binary/ASCII form from an FTP server, converting them, if necessary, to ASCII and then inserting them into a database via ActiveRecord.  With this utility you only need the standard Avaya CMS Release 13 or better without any additional software or utilities from Avaya, as this utility will process either binary or ASCII output from the Avaya CMS.

Status
======
This release is now in production use within Call Centers using the Avaya CMS.  The utility successfully and reliably imports the data provided by the Avaya CMS ECHI into various databases, including Microsoft Sqlserver, Oracle and MySQL.  This provides the repository of call segments that may then be used to provide detailed Cradle to Grave reporting for the call center.

Features
========
The utility provides the following capabilities:

  * Support of ActiveRecord (means you may use Oracle, MySQL, MS-SQL, Postgres, DB2, ODBC, etc)
  * Generate your schema via ActiveRecord Migrations automatically
  * Fetch Binary or ASCII CSV files from the Avaya CMS platform via FTP
  * Insert the records into the defined database table using database transactions, via ActiveRecord, on a per file basis to support recovery on failure
  * Change schema structure via YML configuration file to accommodate various releases of the ECHI format
  * Supports inserting data from the various '.dat' files provided by the Avaya CMS into associated tables
  * Runs as a daemon (via fork) on Posix (*NIX) and a service on Windows
  * Has a watchdog process on Posix or you may set a service watch on Windows
  * Allows for multiple FTP sessions to be used for greater performance

Table names:

  * echi_records - stores all ECHI data
  * echi_logs - stores a log entry for each file processed
  * echi_acds - stores the data from the acd.dat file
  * echi_agents - stores the data from the agname.dat file
  * echi_aux_reasons - stores the data from the aux_rsn.dat file
  * echi_cwcs - stores data from the cwc.dat file
  * echi_splits - stores data from the split.dat file
  * echi_trunk_groups - stores data from the tkgrp.dat file
  * echi_vdns - stores data from the vdn.dat file
  * echi_vectors - stores data from the vector.dat file

What ECHI-Converter is not
=============
* A reporting engine
* A set of database maintenance scripts

Requirements
============
* [Ruby v1.8.6+](http://www.ruby-lang.org/)
* [Rubygems v1.2+](http://www.rubygems.org/)
* [ActiveRecord v2.1+](http://activerecord.rubyforge.org/)
* [ActiveSupport v2.1+](http://activesupport.rubyforge.org/)
* [Daemons v1.0.10+](http://daemons.rubyforge.org/)
* [FasterCSV v1.2.3+](http://fastercsv.rubyforge.org/)
* [Rake v0.8.1+](http://rake.rubyforge.org/)
* [UUIDTools v1.0.3+](http://sporkmonger.com/projects/uuidtools/)
* [Win32-service v.0.6.1+](http://win32utils.rubyforge.org/) (Manual install for Windows only)
* Avaya CMS ECHI Release 12+ enabled and configured to send to an FTP server

Installing
==========
    `gem install echi-converter`

Setup
=====
First, create the directory with all of the project files where you will run this application from:

    `echi-converter create myproject`

Once you have installed a project into your preferred directory, you then need to configure for your environment.  The first step is to modify each of these files:

  * config/application.yml
    * Change each of the 'echi' settings for connecting to your local FTP server where the CMS puts the ASCII/binary files
    * Select which schema you would like to use (ie - extended_version12.yml) based on what you have in place
  * config/database.yml
    * Change to match your local database and database login credentials, full ActiveRecord support
    * Note: Your database user and database must exist before running rake, as rake will then create the schema

Once this is complete, then simply run these commands from the project directory:

  * rake migrate (creates the tables required for the system)
  * echi-converter (starts the server daemon, refer to its usage)

Note:  When using a Windows FTP server, you must configure the FTP server to provide a UNIX directory listing format.

Usage
======
* echi-converter create myproject - create the local project to run the ECHI converter from
* echi-converter upgrade myproject - location of project to upgrade after a new gem is installed

For POSIX (*NIX):

* echi-converter run myproject - Run the ECHI converter interactively from the location given
* echi-converter start myproject - Start the ECHI converter in daemon mode from the location given
* echi-converter stop myproject - Stop the ECHI converter daemon
* echi-converter restart myproject - Restart the ECHI converter
* echi-converter zap myproject - If there has been an unexpected close and the system still thinks the converter is running, clean up the pid files

For MS-Windows:

* echi-converter install myproject - install the service (must specify complete path such as c:\path\to\my\project - if the directory name or path has any spaces, please enclose the "myproject" in double quotes )
* echi-converter start - start the service
* echi-converter stop - stop the service
* echi-converter pause - pause the service
* echi-converter resume - resume the service
* echi-converter status - returns the status of a configured service
* echi-converter delete - delete the service"

* If you would like to run the script interactively, you may also execute this command:
** ruby "c:\myproject\lib\main_win32.rb"

Multi-byte character support:

* If you require multi-byte character support be sure to set your database to 'utf8' as well as uncomment the option 'encoding: utf8' in the config/database.yml file

Demonstration of usage
================
Start the daemon/service:

    `echi-converter start myproject`

Stop the daemon/service:

    `echi-converter stop myproject`

Supported Platforms
==================
While the use of Ruby allows for operation on a multitude of platforms, these are the platforms that have actually been tested on.  If you have success running on other platforms, please feel free to provide details on the Google Group.

Operating Systems
===============
* POSIX
* Windows XP SP2
* Windows 2000
* Windows 2003

Databases
=========
* MySQL
* Microsoft Sqlserver
* DB2
* Sqlite3
* Postgres
* Oracle

FTP Servers
============
* VSFTP
* Windows 2003/XP FTP Servers (When using a Windows FTP server, you must configure the FTP server to provide a UNIX directory listing format.)

Related Avaya Documentation for ECHI
==============
* [Avaya Call Management System Release 14 External Call History Interface](http://support.avaya.com/elmodocs2/cms/R14/ECHI.pdf)
* [Avaya Call Management System Release 13 External Call History Interface](http://support.avaya.com/elmodocs2/cms_r13_1/07-300737_ECHI.pdf)

Screencast
============
You may view the screencast on howto install and use the ECHI-Converter [here](http://www.screencast.com/t/lQQkIVkUZMr).

Consulting Services
=============
If you would like help installing, configuring or adding features please do not hesitate to contact the consulting services of Adhearsion [here](http://new.adhearsion.com/consulting).

Forum
======
Please report questions on the [Google Group](http://groups.google.com/group/echi-converter)
Please report bugs on the [Bug tracker](https://github.com/mojolingo/echi-converter/issues)

How to submit patches
==============
* Read the [8 steps for fixing other people's code](http://drnicwilliams.com/2007/06/01/8-steps-for-fixing-other-peoples-code/)
* Submit a pull request on github

License
========
This code is free to use under the terms of the LGPL license.

Contact
========
Comments are welcome. Send an email to [jason [at] goecke.net](mailto:jason@goecke.net).

Brought to you by
=================
* [Adhearsion](http://www.adhearsion.com), the open-source, unconventional voice framework that ties technologies together neatly.