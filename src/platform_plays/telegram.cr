class PlatformPlays
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

  private def request(path : String, body : String = "")
    resp = HTTP::Client.get(@url + path, body: body, headers: HTTP::Headers{"Content-Type" => "application/json" })
    raise Error.new("GET #{path} failed with #{resp.status_code}") unless resp.success?
    raise Error.new("GET #{path} failed: #{resp.body}") unless Result.from_json(resp.body).ok

    resp.body
  end
end
