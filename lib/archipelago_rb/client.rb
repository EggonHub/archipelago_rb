require_relative 'packets'
require_relative 'constants'
require_relative 'objects'
require_relative 'locations'
require_relative 'data'
require_relative 'items'
require_relative 'players'
require 'websocket-client-simple'
require 'json'

module Archipelago

    class Client
        attr_reader :data, :locations, :items, :players, :client_connect_status, :client_socket

        def initialize()
            @client_version = Objects::Version.new(0, 4, 6)
            @client_connect_status = ConnectStatus::DISCONNECTED
            @data = DataManager.new()
            @locations = LocationsManager.new(self)
            @items = ItemsManager.new(self)
            @players = PlayersManager.new(self)
            @listeners = Hash.new { |hash, key| hash[key] = []}

            add_default_listeners()
        end

        def connect(connect_info)
            return if @client_connect_status != ConnectStatus::DISCONNECTED
            Thread.new do
                @connect_info = connect_info
                url = "ws://#{@connect_info["hostname"]}:#{@connect_info["port"]}"
                @client_socket = WebSocket::Client::Simple.connect(url) # Assign to instance variable
            
                @client_socket.on :open do
                end
            
                # Get a reference to the instance method
                packet_handler = method(:notify_listeners)
            
                @client_socket.on :message do |msg|
                    packet_handler.call(msg)
                end
            
                @client_socket.on :error do |e|
                    puts "-- error (#{e.inspect})"
                end
            
                @client_socket.on :close do
                end
            
                loop do
                    STDIN.gets.strip
                end
            end
        end

        def disconnect()
            if @client_socket
                @client_socket.close
                @client_connect_status = ConnectStatus::DISCONNECTED
                puts "Client disconnected."
            end
        end

        def add_listener(packet_type, &block)
            @listeners[packet_type] << block
        end

        def say(text)
            if @client_connect_status == ConnectStatus::CONNECTED
                say_packet = Packets::Say.new(text)
                @client_socket.send(say_packet.to_json)
            else
                puts "[Client say] You need to have an active Archipelago connection to use this!"
            end
        end

        def update_status(status)
            if @client_connect_status == ConnectStatus::CONNECTED
                status_packet = Packets::StatusUpdate.new(status)
                @client_socket.send(status_packet.to_json)
            else
                puts "[Client update_status] You need to have an active Archipelago connection to use this!"
            end
        end

        private

        def notify_listeners(msg)
            if valid_json?(msg.data)
                datapackets = JSON.parse(msg.data)
                datapackets.each do |packet|
                    @listeners[packet["cmd"]].each { |listener| listener.call(packet)}
                end
            elsif msg.type == :ping
                @client_socket.send(msg.data, type: :pong)
            else
                puts msg
            end
        end

        def add_default_listeners

            add_listener("RoomInfo") do |msg|
                @data.import_game_data(msg)

                password = nil
                if @data.game_data["password"]
                    puts "Password:"
                    password = STDIN.gets.strip
                end

                connect_packet = Packets::Connect.new(
                    password, 
                    @connect_info["game"], 
                    @connect_info["name"], 
                    "99999", 
                    @client_version.to_hash, 
                    @connect_info["items_handling"], 
                    ["AP"], false
                )

                @client_socket.send(connect_packet.to_json)
            end

            add_listener("Connected") do |msg|
                @data.import_game_data(msg)

                @locations.import_checked_locations(@data.game_data["checked_locations"])
                @locations.import_missing_locations(@data.game_data["missing_locations"])

                datapackages_to_update = @data.import_datapackages
                if !datapackages_to_update.empty?
                    getDataPackagePacket = Packets::GetDataPackage.new(datapackages_to_update)
                    @client_socket.send(getDataPackagePacket.to_json)
                end

                @locations.import_datapackages(@data.datapackages)
                @items.import_datapackages(@data.datapackages)
                @client_connect_status = ConnectStatus::CONNECTED
                puts "Connection successful!"
            end

            add_listener("RoomUpdate") do |msg|
                @data.import_game_data(msg)
            end

            add_listener("ReceivedItems") do |msg|
                msg["items"].each do |item|
                    @items.received << item
                end
            end

            add_listener("ConnectionRefused") do |msg|
                puts connectionrefused_packet["errors"]
            end

            add_listener("PrintJSON") do |msg|
                puts msg
            end

            add_listener("DataPackage") do |msg|
                @data.update_datapackages(msg)
                @locations.import_datapackages(@data.datapackages)
                @items.import_datapackages(@data.datapackages)
            end
        end
    end
end
