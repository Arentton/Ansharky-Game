extends Control

func on_server_clicked() -> void:
	print("server clicked")
	HighLevelNetworkHandler.start_server()
	
func on_client_clicked() -> void:
	print("client clicked")
	HighLevelNetworkHandler.start_server()
