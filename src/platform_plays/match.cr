class PlatformPlays
  enum State
    WaitForPlayers
    WaitForScore
    WaitForApprove
    WaitForPublish
    Publishing
    Done
  end

  struct Match
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
end
