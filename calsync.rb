#!/usr/bin/env ruby

require 'rubygems'
require 'bundler'
Bundler.require(:default)

require 'viewpoint'
include Viewpoint::EWS

require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'google/apis/calendar_v3'
require 'fileutils'
require 'logger'
require 'thor'

require 'json'
require 'andand'
require 'pp'
require 'nokogiri'
require 'loofah'
require "yaml/store"

LOGFILE = File.join(Dir.home, '.calsync.log')
DATAFILE = File.join(Dir.home, '.calsync_data.yml')
EWS_CREDENTIALS_PATH = File.join('.', '.credentials', "calsync.json")

OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
APPLICATION_NAME = 'calsync'
CLIENT_SECRETS_PATH = 'client_secret.json'
CREDENTIALS_PATH = File.join(Dir.home, '.credentials', "calsync.yaml")
SCOPE = 'https://www.googleapis.com/auth/calendar'

##
# Ensure valid credentials, either by restoring from the saved credentials
# files or intitiating an OAuth2 authorization. If authorization is required,
# the user's default browser will be launched to approve the request.
#
# @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
def authorize interactive
  FileUtils.mkdir_p(File.dirname(CREDENTIALS_PATH))
  client_id = Google::Auth::ClientId.from_file(CLIENT_SECRETS_PATH)
  token_store = Google::Auth::Stores::FileTokenStore.new(file: CREDENTIALS_PATH)
  authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)
  user_id = 'default'
  credentials = authorizer.get_credentials(user_id)
  if credentials.nil? and interactive
    url = authorizer.get_authorization_url(base_url: OOB_URI)
    code = ask("Open the following URL in the browser and enter the resulting code after authorization\n" + url)
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI)
  end
  credentials
end



#####
##### begin workaround logging issues in Viewpoint
#####
class Z
  def debug?
    return false
  end
  def debug
  end
end
class Viewpoint::EWS::Connection
  def log
    return Z.new
  end
end
class Viewpoint::EWS::Types::CalendarFolder
  def log
    return Z.new
  end
end
class Viewpoint::EWS::Types::ContactsFolder
  def log
    return Z.new
  end
end
class Viewpoint::EWS::Types::TasksFolder
  def log
    return Z.new
  end
end
class Viewpoint::EWS::Types::Folder
  def log
    return Z.new
  end
end
#####
##### end workaround logging issues in Viewpoint
#####


class CalSync < Thor

  no_commands {
    def get_password(prompt="Password: ")
      if STDIN.respond_to?(:noecho)
        print prompt
        STDIN.noecho(&:gets).chomp
      else
        `read -s -p "#{prompt}" password; echo $password`.chomp
      end
    end

    def ews_login
      begin
        require 'io/console'
      rescue LoadError
      end

      # read endpoint and user from file
      file = File.read(EWS_CREDENTIALS_PATH)
      parsed = JSON.parse(file)
      endpoint = parsed['endpoint']
      user = parsed['user']
      pass = get_password("password for #{user} at #{endpoint}: "); puts
      @client = Viewpoint::EWSClient.new endpoint, user, pass
      if @client.nil?
        puts "no client"
        exit
      end
    end

    def redirect_output
      unless LOGFILE == 'STDOUT'
        logfile = File.expand_path(LOGFILE)
        FileUtils.mkdir_p(File.dirname(logfile), :mode => 0755)
        FileUtils.touch logfile
        File.chmod 0644, logfile
        $stdout.reopen logfile, 'a'
      end
      $stderr.reopen $stdout
      $stdout.sync = $stderr.sync = true
    end

    def setup_logger
      redirect_output if options[:log]

      $logger = Logger.new STDOUT
      $logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO
      $logger.info 'starting'
    end

    def dump_item item, io=nil
      io ||= $>
      io.puts "Id=         \"#{item.id}\""
      io.puts "ItemId=     "
      PP.pp(item.item_id, io)  # contains id and change_key
      io.puts "Subject=    "
      PP.pp(item.subject, io)
      io.puts "Type=       \"#{item.ews_item[:calendar_item_type][:text]}\""  # Single or RecurringMaster
      io.puts "Start=      \"#{item.start}\""
      io.puts "End=        \"#{item.end}\""
      io.puts "Location=   "
      PP.pp(item.location, io)
      io.puts "Organizer=  \"#{item.organizer.name}\""
      io.puts "RequiredAttendees="
      PP.pp(item.required_attendees.map { |attendee| "#{attendee.name} <#{attendee.email_address}>" }, io) #returns Array of MailboxUser
      io.puts "OptionalAttendees="
      PP.pp(item.optional_attendees.map { |attendee| "#{attendee.name} <#{attendee.email_address}>" }, io) #returns Array of MailboxUser
      io.puts "Recurring=  #{item.recurring?}"
      io.puts "Recurrence= "
      PP.pp(item.recurrence, io)
      io.puts "ChangeKey=  \"#{item.change_key}\""
      io.puts "EWSItem=    "
      PP.pp(item.ews_item, io)  # complete record
    end
  }

  class_option :log,     :type => :boolean, :default => true, :desc => "log output to ~/.calsync.log"
  class_option :verbose, :type => :boolean, :aliases => "-v", :desc => "increase verbosity"

  desc "auth", "Authorize the application with google services"
  def auth
    setup_logger
    #
    # initialize the API
    #
    service = Google::Apis::CalendarV3::CalendarService.new
    service.client_options.application_name = APPLICATION_NAME
    service.authorization = authorize !options[:log]
    service
  end

  desc "test_dump_folders", "dump all folder names"
  def test_dump_folders
    ews_login
    folders = @client.folders
    folders.each { |f| puts f.name }
  end

  desc "test_recurrence", "show all items with recurrences"
  def test_recurrence
    ews_login
    calendar = @client.get_folder :calendar
    items = calendar.items_since(Date.iso8601 '2015-09-15')
    # items = calendar.items
    items.each { |item|
      #puts "#"
      next if item.recurrence.nil? || item.recurring?
      #   next if (item.ews_item[:calendar_item_type][:text] == 'Single')
      dump_item item
      puts '#--------------------------------------'
    }
  end

  desc "test_find_types", "collect types of appointments"
  def test_find_types
    ews_login
    calendar = @client.get_folder :calendar
    #items = calendar.items_since(Date.iso8601 '2015-09-15')
    types = {}
    items = calendar.items({:calendar_view => {:max_entries_returned => 20, :start_date => (DateTime.parse '2015-09-15'), :end_date => (DateTime.now)}})
    items.each { |item|
      types[item.ews_item[:calendar_item_type][:text]] = true
      if item.ews_item[:calendar_item_type][:text] == 'Exception'
        dump_item item
        exit
      end
    }
    puts types.keys
  end

  desc "test_dump_item", "show first calendar item"
  def test_dump_item
    ews_login
    calendar = @client.get_folder :calendar
    events   = calendar.items
    [events.first].each { |event|
      puts event.methods
      dump_item event
      return
    }
  end

  desc "test_lookup_name", "show a specific resolved contact name"
  def test_lookup_name
    ews_login
    resp = @client.ews.resolve_names(:name => "Sharron", :full_contact_data => true)
    puts resp.response_message[:elems][:resolution_set][:elems][0][:resolution][:elems][0]
  end

  desc "test_sync_state", "sync one item, then reset to sync two from the same spot"
  def test_sync_state
    ews_login
    calendar = @client.get_folder :calendar
    puts "got calendar"
    result = calendar.sync_items!(nil, 1)
    dump_item result[:create].first
    puts '--------------------------------------'

    state = calendar.sync_state

    result = calendar.sync_items!(state, 1)
    dump_item result[:create].first
    puts '--------------------------------------'

    calendar = @client.get_folder :calendar
    result = calendar.sync_items!(state, 1)
    dump_item result[:create].first
    puts '--------------------------------------'
    # http://www.rubydoc.info/github/WinRb/Viewpoint/Viewpoint/EWS/Types/GenericFolder#subscribe-instance_method
  end

  desc "test_count_sync", "count items to be synced"
  def test_count_sync
    ews_login
    calendar = @client.get_folder :calendar
    puts "got calendar"
    while not calendar.synced?
      result = calendar.sync_items!
      [:create, :update, :delete, :read_flag_change].each { |flag|
        puts "#{flag}\t#{result[flag].andand.count}" unless result[flag].nil?
      }
    end
  end

  no_commands {
    def reformat_body body
      doc = Loofah.document(body).scrub!(:whitewash)
      txt = doc.text(:encode_special_chars => false)
      txt.gsub!(/\r/, '')        # carriage return
      txt.gsub!(/\u00A0/, ' ')   # non-breaking space -> space
      txt.strip!
      txt.gsub!(/\n\s*\n\s*\n/,"\n\n")
      txt.gsub!(/[ \t]+\n/, "\n")
      return txt.empty? ? nil : txt
    end
  }

  desc "forward_sync", "sync creates from outlook to google"
  def forward_sync
    google_client = auth
    result = google_client.list_calendar_lists
    google_calendar = result.items.select { |item| item.summary == 'outlook' }.first
    $logger.info 'got google calendar'

    ews_login
    outlook_calendar = @client.get_folder :calendar
    $logger.info 'got outlook calendar'

    store = YAML::Store.new(DATAFILE)

    state = store.transaction { store.fetch(:state, nil) }
    while not outlook_calendar.synced?
      result = outlook_calendar.sync_items!(state, 1)

      [:update, :read_flag_change].each { |key|
        result[key].andand.each { |outlook_event|
          begin
            File.open("/home/jeff/calendar.txt", "a") do |ff|
              ff.puts "#{key} #{DateTime.now} ========================================="
              PP.pp(outlook_event.ews_item, ff)
            end
            $logger.info PP.pp(result, "")
            store.transaction {
              state = outlook_calendar.sync_state
              store[:state] = state
            }
          rescue Exception => e
            $logger.error e.message
            $logger.error e.backtrace.inspect
            exit
          end
          $logger.info ""
        }
      }

      key = :delete
      result[key].andand.each { |outlook_event|
        begin
          File.open("/home/jeff/calendar.txt", "a") do |ff|
            ff.puts "#{key} #{DateTime.now} ========================================="
            PP.pp(outlook_event, ff)
          end
          $logger.info PP.pp(result, "")
          store.transaction {
            state = outlook_calendar.sync_state
            store[:state] = state
          }
        rescue Exception => e
          $logger.error e.message
          $logger.error e.backtrace.inspect
          exit
        end
        $logger.info ""
      }

      result[:create].andand.each { |outlook_event|
        google_event = Google::Apis::CalendarV3::Event.new(
          {
            summary: outlook_event.subject,
            location: outlook_event.location,
            description: reformat_body(outlook_event.body),
            #id: outlook_event.id,
            start: {
              date_time: outlook_event.start,
              # time_zone: 'America/Los_Angeles'
            },
            end: {
              date_time: outlook_event.end,
              # time_zone: 'America/Los_Angeles'
            },
            recurrence: [
              # 'RRULE:FREQ=DAILY;COUNT=2'
            ],
            attendees: [
              # {email: 'lpage@example.com'},
              # {email: 'sbrin@example.com'}
            ],
            #      reminders: {
            #        use_default: false,
            #        overrides: [
            #          {'method' => 'email', minutes: 24 * 60},
            #          {'method' => 'popup', minutes: 10}
            #        ],
            #      },
          }
        )

        #$logger.info google_event

        begin
          File.open("/home/jeff/calendar.txt", "a") do |ff|
            ff.puts "#{key} #{DateTime.now} ========================================="
            dump_item outlook_event, ff
          end
          # https://developers.google.com/google-apps/calendar/v3/reference/events/insert
          #result = google_client.insert_event google_calendar.id, google_event
          $logger.info PP.pp(result, "")
          store.transaction {
            state = outlook_calendar.sync_state
            store[:state] = state
          }
        rescue Exception => e
          $logger.error e.message
          $logger.error e.backtrace.inspect
          exit
        end
        $logger.info ""
      }
    end
    $logger.info 'done syncing'
  end

  desc "test_create_gcal", "test creation of an item on google calendar"
  def test_create_gcal
    client = auth
    result = client.list_calendar_lists
    calendar = result.items.select { |item| item.summary == 'outlook' }.first

    event = Google::Apis::CalendarV3::Event.new(
      {
        summary: 'Google I/O 2015',
        location: '800 Howard St., San Francisco, CA 94103',
        description: 'A chance to hear more about Google\'s developer products.',
        start: {
          date_time: '2016-06-04T09:00:00-07:00',
          time_zone: 'America/Los_Angeles'
        },
        end: {
          date_time: '2016-06-04T17:00:00-07:00',
          time_zone: 'America/Los_Angeles'
        },
        recurrence: [
          'RRULE:FREQ=DAILY;COUNT=2'
        ],
        attendees: [
          {email: 'lpage@example.com'},
          {email: 'sbrin@example.com'}
        ],
        #      reminders: {
        #        use_default: false,
        #        overrides: [
        #          {'method' => 'email', minutes: 24 * 60},
        #          {'method' => 'popup', minutes: 10}
        #        ],
        #      },
      }
    )

    result = client.insert_event(calendar.id, event)
    puts "Event created: #{result.html_link}"
  end
end

CalSync.start
