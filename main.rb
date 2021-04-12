require "mongo"
require 'sinatra'
require "repltalk"
require "discordrb"

$rt_client = ReplTalk::Client.new
mongo_client = Mongo::Client.new(ENV["monogurl"], database: "rtbot")
$discord_client = Discordrb::Commands::CommandBot.new(
	token: ENV["bottoken"],
	prefix: "rt>",
	ignore_bots: true,
	spaces_allowed: true,
	command_doesnt_exist_message: "The command **`%command%`** does not exist"
)

$id_db = mongo_client[:id]
$servers_db = mongo_client[:servers]

def check_posts
	loop do
		begin
			posts = $rt_client.get_posts(order: "new", count: 10).select { |post| post.id > $id_db.find.first[:id] }
		rescue
			posts = []
		end
		posts.each do |post|
			embed = Discordrb::Webhooks::Embed.new(
				title: post.title,
				url: post.url,
				description: post.preview,
				colour: "0x#{post.board.color[1...post.board.color.length]}".to_i(16),
				timestamp: Time.new,
				author: Discordrb::Webhooks::EmbedAuthor.new(
					name: "#{post.author.username} (#{post.author.cycles})",
					url: "https://repl.it/@#{post.author}",
					icon_url: post.author.pfp
				),
				footer: Discordrb::Webhooks::EmbedFooter.new(text: "#{post.board.name} Board")
			)
			$servers_db.find.each do |server|
				begin
					$discord_client.send_message(
						server[:channel_id],
						nil,
						false,
						embed
					)
				rescue
					next
				end
			end
		end
		$id_db.update_one( { "id" => $id_db.find.first[:id] }, { "$set" => { "id" => posts[0].id } } ) unless posts.length == 0
		sleep 5
	end
end

$discord_client.ready do
	$discord_client.watching = "repl talk"
	Thread.new { check_posts }
end

$discord_client.command :config, description: "Set the channel to send repl talk posts to", usage: "Do `**`rt>config`**` in the channel that you want repl talk posts to be sent to" do |event|
	return "You need to be an admin to set a channel" unless event.author.defined_permission?(:administrator)
	channel_id = event.channel.id
	server_id = event.server.id
	if $servers_db.find( { "server_id" => server_id } ).first == nil
		$servers_db.insert_one( { "server_id" => server_id, "channel_id" => channel_id } )
	else
		$servers_db.update_one( { "server_id" => server_id }, { "$set" => { "channel_id" => channel_id } } )
	end
	"Repl Talk posts will be sent to this channel"
end

$discord_client.command :invite, description: "Sends my invite url so that you can add me to other servers" do |event|
	event.bot.invite_url
end

$discord_client.server_delete do |event|	
	server_id = event.server
	unless $servers_db.find( { "server_id" => server_id } ).first == nil
		$servers_db.delete_one( { "server_id" => server_id } )
	end
end

Thread.new { $discord_client.run }
set :bind, "0.0.0.0"
get "/" do
	"Online!"
end