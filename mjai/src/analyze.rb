#!/usr/local/bin/ruby
require "pg"
require "json"

class Analyzer
  def initialize(connection, file_name)
    @connection = connection
    @file_name = file_name
    @game_id = nil
    @round_id = nil
    @player_id = Array.new(4)
  end

  def insert_game()
    file_name = File.basename(@file_name, ".mjson")
    @connection.exec("INSERT INTO games VALUES (default,'#{file_name}')")
    result = @connection.exec("SELECT LASTVAL()")
    @game_id = result[0]["lastval"]
  end

  def insert_name(name)
    result = @connection.exec("SELECT * FROM player_names WHERE player_name = '#{name}'")

    if result.ntuples == 0
      @connection.exec("INSERT INTO player_names VALUES (default,'#{name}')")
    end
  end

  def insert_player(seat, name)
    result = @connection.exec("SELECT * FROM player_names WHERE player_name = '#{name}'")
    player_name_id = result[0]["id"]
    @connection.exec("INSERT INTO players VALUES (default,#{seat},#{@game_id},'#{player_name_id}')")
    result = @connection.exec("SELECT LASTVAL()")
    @player_id[seat] = result[0]["lastval"]
  end

  def insert_round()
    @connection.exec("INSERT INTO rounds VALUES (default,#{@game_id})")
    result = @connection.exec("SELECT LASTVAL()")
    @round_id = result[0]["lastval"]
  end

  def insert_riichi(actor)
    @connection.exec("INSERT INTO riichis VALUES (default,#{@player_id[actor]},#{@round_id})")
  end

  def insert_naki(actor, target)
    @connection.exec("INSERT INTO nakis VALUES (default,#{@player_id[actor]},#{@player_id[target]},#{@round_id})")
  end

  def insert_winning(actor, target, delta)
    @connection.exec("INSERT INTO winnings VALUES (default,#{@player_id[actor]},#{@player_id[target]},#{delta},#{@round_id})")
  end

  def insert_ryukyoku(actor, tenpai)
    @connection.exec("INSERT INTO ryukyokus VALUES (default,#{@player_id[actor]},#{tenpai},#{@round_id})")
  end

  def insert_result(seat, score, position)
    @connection.exec("INSERT INTO results VALUES (default,#{@player_id[seat]},#{score},#{position})")
  end

  def start_game(message)
    insert_game()

    message["names"].each_with_index do |name, index|
      insert_name(name)
      insert_player(index, name)
    end
  end

  def start_kyoku(message)
    insert_round()
  end

  def reach(message)
    insert_riichi(message["actor"])
  end

  def pon(message)
    insert_naki(message["actor"], message["target"])
  end

  def chi(message)
    insert_naki(message["actor"], message["target"])
  end

  def daiminkan(message)
    insert_naki(message["actor"], message["target"])
  end

  def hora(message)
    insert_winning(message["actor"], message["target"], message['deltas'][message['actor']])
  end

  def ryukyoku(message)
    4.times do |i|
      insert_ryukyoku(i, message["tenpais"][i])
    end
  end

  def end_game(message)
    scores = message["scores"]
    i = 0
    positions = [*0..3].sort_by{|v| [-scores[v], i+=1]}

    4.times do |i|
      insert_result(positions[i], scores[positions[i]], i+1)
    end
  end

  def execute()
    File.open(@file_name) do |file|
      lines = file.readlines
      message = JSON.parse(lines.last)

      if message['type'] != 'end_game'
        return
      end

      lines.each do |line|
        message = JSON.parse(line)
    
        begin
          self.send("#{message['type']}", message)
        rescue NoMethodError
        end
      end
    end
  end
end

connection = PG::connect(host: 'db', user: 'user', password: 'password', dbname: 'mjai_db')
file_name = Dir.glob("/log_dir/*.mjson").max_by{|f| File.mtime(f)}
analyzer = Analyzer.new(connection, file_name)
analyzer.execute()
