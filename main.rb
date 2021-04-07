require "mongo"
require "repltalk"
require "discordrb"

$rt_client = Client.new
mongo_client = Mongo::Client.new(ENV["monogurl"], database: "rtbot")
$discord_client = Discordrb::Commands::CommandBot.new(token: ENV["bottoken"], prefix: "rt>", ignore_bots: true)

$id_db = mongo_client[:id]
$servers_db = mongo_client[:servers]

def check_posts
	loop do
		posts = $rt_client.get_posts(order: "new", count: 10).select { |post| post.id > $id_db.find.first[:id] }
		posts.each do |post|
			embed = Discordrb::Webhooks::Embed.new(
						title: post.title,
						url: post.url,
						description: post.preview,
						colour: "0x#{post.board.color[1...post.board.color.length]}".to_i(16),
						timestamp: Time.new,
						author: Discordrb::Webhooks::EmbedAuthor.new(
							name: post.author.username,
							url: "https://repl.it/@#{post.author}",
							icon_url: post.author.pfp
						)
					)
			$servers_db.find.each do |server|
				$discord_client.send_message(
					server[:channel_id],
					nil,
					false,
					embed
				)
			end
		end
		$id_db.update_one( { "id" => $id_db.find.first[:id] }, { "$set" => { "id" => posts[0].id } } ) unless posts.length == 0
		sleep 5
	end
end

$discord_client.ready do |_|
	$discord_client.watching= "repl talk"
	Thread.new { check_posts }
end

$discord_client.command :invite do |event|
	event.bot.invite_url
end

$discord_client.command :config do |event|
	channel_id = event.channel.id
	server_id = event.server.id
	if $servers_db.find( { "server_id" => server_id } ).first == nil
		$servers_db.insert_one( { "server_id" => server_id, "channel_id" => channel_id } )
	else
		$servers_db.update_one( { "server_id" => server_id }, { "$set" => { "channel_id" => channel_id } } )
	end
	"Repl Talk posts will be sent to this channel"
end

$discord_client.run