require "http/client"
require "json"

require "./platform_plays/match"
require "./platform_plays/telegram"
class PlatformPlays
  class Error < Exception; end

  VERSION = "0.1.0"

  property channel : Int32|String
  property next_update_id : Int32 = 0

  def initialize(@channel, token : String, url = "https://api.telegram.org/bot")
    @url = url + token
    @matches = Hash(Int32, Match).new
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
      # `git push origin master`
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
end

pp = PlatformPlays.new(channel: "CHANNEL_ID", token: "SECRET")
pp.run
