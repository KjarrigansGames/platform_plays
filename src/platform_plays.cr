require "http/client"
require "json"
require "yaml"

require "./platform_plays/config"
require "./platform_plays/match"
require "./platform_plays/telegram"

class PlatformPlays
  class Error < Exception; end

  VERSION = "0.1.0"

  property channel : Int32|String
  property next_update_id : Int32 = 0
  property config : Array(GameConfig)

  def initialize(@channel, token : String, url = "https://api.telegram.org/bot")
    @url = url + token
    @matches = Hash(Int32, Match).new
    @config = Config.load
  end

  # There seems to be no actively maintained libgit2 binding yet, so using ShellExec for now
  def commit(game_id, matches)
    game = @config.find do |cfg| cfg.id == game_id end
    return if game.nil?

    repo = game.repo
    if repo.nil?
      send_message "No target repo configured for #{game.id}. Abort"
      return
    end

    Dir.cd(repo) do
      `git checkout -f master && git pull`
      File.open("match.log", "a+") do |log|
        matches.each do |match|
          log.puts match.to_s
        end
      end
      `git commit -am "Update match.log"`
      `git push origin #{game.branch}` if ENV["PP_PUSH"]?
    end
  end

  def run
    loop do
      get_updates(timeout: 600).each do |update|
        if update.message
          msg = update.message
          next if msg.nil?

          case msg.text
          when "/cache"
            list = @matches.values.select do |match|
              match.state == State::WaitForPublish
            end

            if list.empty?
              send_message "Nothing to commit"
              next
            end

            list.group_by do |match| match.game end.each do |game_id, matches|
              next if matches.empty?

              send_message("Uncommited #{game_id} matches:\n" + matches.map do |match| match.to_s end.join("\n"))
            end
          when "/commit"
            list = @matches.values.select do |match|
              match.state == State::WaitForPublish
            end

            if list.empty?
              send_message "Nothing to commit"
              next
            end

            list.group_by do |match| match.game end.each do |game, matches|
              commit game, matches
            end
          when /\/(\w+)/
            game = @config.find do |cfg| cfg.id == $1 end
            next if game.nil?

            msg = send_poll("Who played #{game.name} (Click 2 times, Winner first)?", game.players)
            @matches[msg.message_id] = Match.new(game: game.id, state: State::WaitForPlayers)
          end
        elsif update.callback_query
          resp = update.callback_query
          next if resp.nil?

          msg = resp.message
          next if msg.nil?

          match = @matches[msg.message_id]?
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

              game = @config.find do |cfg| cfg.id == match.game end
              next if game.nil?

              msg = send_poll("%s vs %s - How did it end?" % [match.player_1, match.player_2], game.scores)
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
              send_message("Match aborted")
              @matches.delete(msg.message_id)
            end
          end
        end
      end
    end
  end
end

pp = PlatformPlays.new(channel: ENV["PP_CHANNEL"], token: ENV["PP_TOKEN"])
pp.run
