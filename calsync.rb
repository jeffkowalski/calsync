#!/usr/bin/env ruby

require 'viewpoint'
include Viewpoint::EWS

require 'json'
require 'andand'
require 'awesome_print'


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


#####
#####
#####

begin
  require 'io/console'
rescue LoadError
end

if STDIN.respond_to?(:noecho)
  def get_password(prompt="Password: ")
    print prompt
    STDIN.noecho(&:gets).chomp
  end
else
  def get_password(prompt="Password: ")
    `read -s -p "#{prompt}" password; echo $password`.chomp
  end
end

CREDENTIALS_PATH = File.join('.', '.credentials', "calsync.json")

# read endpoint and user from file
file = File.read(CREDENTIALS_PATH)
parsed = JSON.parse(file)
endpoint = parsed['endpoint']
user = parsed['user']
pass = get_password("password for #{user} at #{endpoint}: "); puts
@client = Viewpoint::EWSClient.new endpoint, user, pass
if @client.nil?
  puts "no client"
  exit
end


#####
#####
#####


def dump_item item
  puts "Id:         #{item.id}"
  puts "ItemId:     #{item.item_id}" # contains id and change_key
  puts "Subject:    #{item.subject}"
  puts "Type:       #{item.ews_item[:calendar_item_type][:text]}"  # Single or RecurringMaster
#  ap item.ews_item  # complete record
  puts "Start:      #{item.start}"
  puts "End:        #{item.end}"
  puts "Location:   #{item.location}"
  puts "Organizer:  #{item.organizer.name}"
  puts "OptionalAttendees:"
  ap item.optional_attendees #returns Array of MailboxUser
  puts "RequiredAttendees:"
  ap item.required_attendees.map { |attendee| attendee.name } #returns Array of MailboxUser
  puts "Recurring:  #{item.recurring?}"
  puts "Recurrence: #{item.recurrence}"
  puts "ChangeKey:  #{item.change_key}"
end


def test_dump_folders
  folders = @client.folders
  folders.each { |f| puts f.name }
end

def test_recurrence
  calendar = @client.get_folder :calendar
  sd = Date.iso8601 '2015-09-15'
#  items = calendar.items_since sd
  items   = calendar.items
  items.each { |item|
    puts "."
    next if item.recurrence.nil?
    #   next if (item.ews_item[:calendar_item_type][:text] == 'Single')
    dump_item item
    puts '--------------------------------------'
  }
end

def test_dump_item
  calendar = @client.get_folder :calendar
  events   = calendar.items
  [events.first].each { |event|
    puts event.methods
    puts event.ews_item
    puts event.extended_properties
    return
  }
end

def test_lookup_name
  resp = @client.ews.resolve_names(:name => "Sharron", :full_contact_data => true)
  puts resp.response_message[:elems][:resolution_set][:elems][0][:resolution][:elems][0]
end

def test_sync_state
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

def test_count_sync
  calendar = @client.get_folder :calendar
  puts "got calendar"
  while not calendar.synced?
    result = calendar.sync_items!
    [:create, :update, :delete, :read_flag_change].each { |flag|
      puts "#{flag}\t#{result[flag].andand.count}" unless result[flag].nil?
    }
  end
end

test_count_sync
