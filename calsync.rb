#!/usr/bin/ruby

require 'viewpoint'
include Viewpoint::EWS

require 'json'

#CREDENTIALS_PATH = File.join(Dir.home, '.credentials', "calsync.json")
CREDENTIALS_PATH = File.join('.', '.credentials', "calsync.json")

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


def test0
  calendar = @client.get_folder :calendar
  events   = calendar.items
  [events.last].each { |event|
    puts event.subject
    # puts event.start_time
    # puts event.end_time
    puts event.required_attendees.map { |attendee| attendee.name }
    puts
  }
end

def test1
  folders = @client.folders
  folders.each { |f| puts f.name }
end

def test2
  calendar = @client.get_folder :calendar
  sd = Date.iso8601 '2015-09-15'
#  items = calendar.items_since sd
  items   = calendar.items
  items.each { |item|
    next if item.recurrence.nil?
 #   next if (item.ews_item[:calendar_item_type][:text] == 'Single')
    puts "Id:         #{item.id}"
    #puts "ItemId:     #{item.item_id}" # contains id and change_key
    puts "Subject:    #{item.subject}"
    puts "Type:       #{item.ews_item[:calendar_item_type][:text]}"  # Single or RecurringMaster
#    puts item.ews_item  # complete record
#    puts "Start:      #{item.start}"
#    puts "End:        #{item.end}"
#    puts "Location:   #{item.location}"
#    puts "Organizer:  #{item.organizer.name}"
#    puts "OptionalAttendees: #{item.optional_attendees}"
#    puts "RequiredAttendees: #{item.required_attendees}"
#    puts "Recurring:  #{item.recurring?}"
#    puts "Recurrence: #{item.recurrence}"
#    puts "ChangeKey:  #{item.change_key}"
    puts '--------------------------------------'
  }
end

def test3
  calendar = @client.get_folder :calendar
  events   = calendar.items
  [events.first].each { |event|
    puts event.methods
    puts event.ews_item
    puts event.extended_properties
    return
  }
end

def test4
  resp = @client.ews.resolve_names(:name => "Sharron", :full_contact_data => true)
  puts resp.response_message[:elems][:resolution_set][:elems][0][:resolution][:elems][0]
end

test4

# maxnum=512
# opts[:calendar_view] = {:max_entries_returned => maxnum, :start_date => start_date, :end_date => end_date}
# calfolder.find_items(#opts



# You can achieve this by 'required_attendees' & 'optional_attendees' methods on calendar_item
# @calendar = cli.get_folder :calendar:
#                              @all_events = @calendar.items
# first_item = @all_events.first

# required_attendees = first_item.required_attendees #returns Array of MailboxUser
# optional_attendees = first_item.optional_attendees #returns Array of MailboxUser

# Ref following commit patch which adds response type for each attendee #pramodshinde@c08113a
