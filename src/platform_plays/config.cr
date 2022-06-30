class PlatformPlays
  struct GameConfig
    include YAML::Serializable

    property id : String
    property name : String
    property players : Array(String)
    property scores : Array(String)
    property repo : String?
    property branch : String?
  end

  class Config
    DIR = File.expand_path("../../../config", __FILE__)

    def self.load
      Dir.cd(DIR) do
        Dir["*.yml"].map do |cfg|
          GameConfig.from_yaml(File.read(cfg))
        end
      end
    end
  end
end
