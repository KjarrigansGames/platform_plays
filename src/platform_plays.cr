require "http/client"
require "json"

class PlatformPlays
  class Error < Exception; end

  VERSION = "0.1.0"

  struct User
    include JSON::Serializable

    property id : Int32
    property is_bot : Bool
    property first_name : String?
    property last_name : String?
    property username : String?
  end

  struct Message
    include JSON::Serializable

    property message_id : Int32
    property from : User
    property date : Int32
    property text : String?
  end

  struct CallbackQuery
    include JSON::Serializable

    property id : String
    property from : User
    property message : Message
    property data : String
  end

  struct Update
    include JSON::Serializable

    property update_id : Int32
    property message : Message?
    property callback_query : CallbackQuery?
  end

  class Result
    include JSON::Serializable

    property ok : Bool
  end

  class MessageResult < Result
    property result : Message
  end

  class UpdateResult < Result
    property result : Array(Update)
  end

  property channel : Int32|String
  property next_update_id : Int32 = 0

  def initialize(@channel, token : String, url = "https://api.telegram.org/bot")
    @url = url + token
    @matches = Hash(Int32, Match).new
  end

  def get_updates(timeout = 0)
    params = { allowed_updates: ["message", "callback_query"], offset: @next_update_id, timeout: timeout}
    updates = UpdateResult.from_json(request("/getUpdates", body: params.to_json)).result

    unless updates.empty?
      @next_update_id = updates.map { |upd| upd.update_id }.max + 1
    end
    updates
  end

  def send_poll(question : String, options : Array(String))
    params = {
      chat_id: channel,
      text: question,
      disable_notification: true,
      protect_content: true,
      reply_markup: {
        inline_keyboard: options.map { |opt| [{ text: opt, callback_data: opt }] }
      }
    }
    json = request("/sendMessage", body: params.to_json)
    MessageResult.from_json(json).result
  rescue err : JSON::SerializableError
    puts json
    raise err
  end

  def send_message(message : String)
    params = {
      chat_id: channel,
      text: message,
      disable_notification: true,
      protect_content: true
    }
    json = request("/sendMessage", body: params.to_json)
    MessageResult.from_json(json).result
  rescue err : JSON::SerializableError
    puts json
    raise err
  end

  enum State
    WaitForPlayers
    WaitForScore
    WaitForApprove
    WaitForPublish
    Publishing
    Done
  end

  struct Match
    include JSON::Serializable

    property game : String
    property player_1 : String|Nil
    property player_2 : String|Nil
    property score : String|Nil
    property state : State
    def initialize(@game, @state)
    end

    def to_s
      "| %10s | %-8s | %-8s | %3s |" % [Time.local.to_s("%d.%m.%Y"), player_1, player_2, score]
    end
  end

  # There seems to be no actively maintained libgit2 binding yet, so using ShellExec for now
  def commit_ur(matches)
    Dir.cd("ManUrEl") do
      `git checkout -f master && git pull`
      File.open("match.log", "a+") do |log|
        matches.each do |match|
          log.puts match.to_s
        end
      end
      `git commit -am "Update match.log"`
      `git push origin main`
    end
  end

  def run
    loop do
      get_updates(timeout: 600).each do |update|
        if update.message
          msg = update.message
          next if msg.nil?

          case msg.text
          when "/ur"
            msg = send_poll("Who played the Royal game of Ur (Click 2 times, Winner first)?", ["Holger", "Raphael", "Markus"])
            @matches[msg.message_id] = Match.new(game: "Ur", state: State::WaitForPlayers)
          when "/cache"
            report = { "Ur" => Array(String).new }
            @matches.each do |_id, match|
              next unless match.state == State::WaitForPublish

              report[match.game] << match.to_s
            end

            p @matches

            send_message("No games ready for commit!") if report.values.all? do |list| list.empty? end

            report.each do |game_name, list|
              next if list.empty?

              send_message("Uncommited #{game_name} matches:\n" + list.join("\n"))
            end
          when "/commit"
            list = @matches.values.select do |match|
              match.state == State::WaitForPublish
            end.group_by do |match| match.game end

            if list.empty?
              send_message "Nothing to commit"
              next
            end

            list.each do |game, matches|
              case game
              when "Ur"
                commit_ur matches
              else
                send_message "Unknown game: #{game}"
              end
            end
          end
        elsif update.callback_query
          resp = update.callback_query
          next if resp.nil?

          msg = resp.message
          next if msg.nil?

          match = @matches[msg.message_id]
          next if match.nil?

          case match.state
          when State::WaitForPlayers
            if match.player_1.nil?
              match.player_1 = resp.data
            elsif match.player_2.nil? && resp.data != match.player_1
              match.player_2 = resp.data
            else
              send_message "Error. Please try again and select only 2 different players!"
            end

            if match.player_1 && match.player_2
              match.state = State::WaitForScore
              @matches.delete(msg.message_id)
              msg = send_poll("%s vs %s - How did it end?" % [match.player_1, match.player_2], ["5-4", "5-3", "5-2", "5-1", "5-0"])
            end
            @matches[msg.message_id] = match
          when State::WaitForScore
            match.score = resp.data
            match.state = State::WaitForApprove
            @matches.delete(msg.message_id)
            msg = send_poll("Ok, So %s won against %s with %s?" % [match.player_1, match.player_2, match.score], ["Yes", "No"])
            @matches[msg.message_id] = match
          when State::WaitForApprove
            if resp.data == "Yes"
              send_message("Got it!")
              match.state = State::WaitForPublish
              @matches[msg.message_id] = match
            else
              send_message("Please start a new /ur session to correct your input!")
              @matches.delete(msg.message_id)
            end
          end
        end
      end
    end
  end

  private def request(path : String, body : String = "")
    resp = HTTP::Client.get(@url + path, body: body, headers: HTTP::Headers{"Content-Type" => "application/json" })
    raise Error.new("GET #{path} failed with #{resp.status_code}") unless resp.success?
    raise Error.new("GET #{path} failed: #{resp.body}") unless Result.from_json(resp.body).ok

    resp.body
  end
end

pp = PlatformPlays.new(channel: "CHANNEL_ID", token: "SECRET")
pp.run
