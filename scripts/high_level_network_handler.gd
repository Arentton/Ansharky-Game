extends Node

const IP_ADDRESS : String = "localhost"
const PORT : int =42069
const MAX_CLIENTS: int = 4
var peer : ENetMultiplayerPeer


# Create client.
func start_client() -> void: 
	var peer = ENetMultiplayerPeer.new
	peer.create_client(IP_ADDRESS, PORT)
	multiplayer.multiplayer_peer = peer

# Create server.
func start_server() -> void: 
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_CLIENTS)
	multiplayer.multiplayer_peer = peer
