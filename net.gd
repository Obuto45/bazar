extends Node
## Ağ katmanı: Steam lobi + SteamMultiplayerPeer (Valve relay), tek PC testi için ENet yedeği.
## KartopuTest'teki sistemin aynısı (GodotSteam eklentisi).

signal status(msg: String)
signal lobby_changed
signal left
signal invited(from_name: String, lobby: int)

const APP_ID := 480 # Spacewar test App ID'si; kendi App ID'n olunca değiştir (steam_appid.txt ile birlikte).
const LOCAL_PORT := 7777
const MAX_PLAYERS := 8

var steam_ok := false
var lobby_id := 0
var names := {} # peer_id -> görünen ad


func _ready() -> void:
	var r: Dictionary = Steam.steamInitEx(APP_ID, true)
	steam_ok = r.get("status", 1) == 0
	if steam_ok:
		Steam.lobby_created.connect(_on_lobby_created)
		Steam.lobby_joined.connect(_on_lobby_joined)
		Steam.join_requested.connect(_on_join_requested)
		Steam.lobby_invite.connect(func(inviter, lobby, _game): invited.emit(Steam.getFriendPersonaName(inviter), lobby))
		Steam.lobby_chat_update.connect(func(_a, _b, _c, _d): lobby_changed.emit())
	else:
		push_warning("Steam başlatılamadı: %s" % r)
	multiplayer.peer_connected.connect(func(_id): lobby_changed.emit())
	multiplayer.peer_disconnected.connect(func(id): names.erase(id); lobby_changed.emit())
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): status.emit("Bağlantı başarısız."); leave())
	multiplayer.server_disconnected.connect(func(): status.emit("Host ayrıldı."); leave())


func my_name() -> String:
	return Steam.getPersonaName() if steam_ok else "Oyuncu"


func display_name(id: int) -> String:
	return names.get(id, "Oyuncu %d" % id)


func online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# --- Steam ---

func host_steam() -> void:
	if not steam_ok:
		status.emit("Steam açık değil / başlatılamadı.")
		return
	leave()
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, MAX_PLAYERS)
	status.emit("Lobi kuruluyor...")


## Çevrimiçi Steam arkadaşları: [[steam_id, ad, lobi_id (yoksa 0)], ...]
func online_friends() -> Array:
	var out := []
	if not steam_ok:
		return out
	for i in Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE):
		var id: int = Steam.getFriendByIndex(i, Steam.FRIEND_FLAG_IMMEDIATE)
		if Steam.getFriendPersonaState(id) != Steam.PERSONA_STATE_OFFLINE:
			var g: Dictionary = Steam.getFriendGamePlayed(id)
			var lobby: int = g.get("lobby", 0) if g.get("id", 0) == APP_ID else 0
			out.append([id, Steam.getFriendPersonaName(id), lobby])
	return out


func join_lobby(id: int) -> void:
	_on_join_requested(id, 0)


## Overlay gerektirmez: davet Steam sohbetine düşer, arkadaş "Katıl" der.
func invite_friend(id: int, friend_name: String) -> void:
	if lobby_id == 0:
		status.emit("Önce Steam lobisi kur.")
		return
	if Steam.inviteUserToLobby(lobby_id, id):
		status.emit("%s davet edildi. Oyunu açıkken Steam sohbetindeki daveti kabul etsin." % friend_name)
	else:
		status.emit("Davet gönderilemedi.")


func _new_steam_peer() -> SteamMultiplayerPeer:
	var peer := SteamMultiplayerPeer.new()
	peer.set_server_relay(true) # Valve relay: NAT sorunsuz
	peer.set_no_nagle(true) # paketleri bekletmeden gönder
	return peer


func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		status.emit("Lobi kurulamadı (kod %d)." % result)
		return
	lobby_id = id
	Steam.setLobbyData(id, "name", my_name() + " pazarı")
	var peer := _new_steam_peer()
	peer.host_with_lobby(id)
	multiplayer.multiplayer_peer = peer
	_register_self()
	status.emit("Lobi hazır. Arkadaşlarını davet et.")


func _on_join_requested(id: int, _friend: int) -> void:
	leave()
	Steam.joinLobby(id)
	status.emit("Lobiye katılınıyor...")


func _on_lobby_joined(id: int, _perm: int, _locked: bool, response: int) -> void:
	if response != 1:
		status.emit("Lobiye katılınamadı (kod %d)." % response)
		return
	if Steam.getLobbyOwner(id) == Steam.getSteamID():
		return # kendi lobimiz, host tarafı zaten kuruldu
	lobby_id = id
	var peer := _new_steam_peer()
	peer.connect_to_lobby(id)
	multiplayer.multiplayer_peer = peer
	status.emit("Hosta bağlanılıyor...")


# --- Tek PC testi (ENet) ---

func host_local() -> void:
	leave()
	var p := ENetMultiplayerPeer.new()
	if p.create_server(LOCAL_PORT, MAX_PLAYERS) != OK:
		status.emit("Port %d açılamadı." % LOCAL_PORT)
		return
	multiplayer.multiplayer_peer = p
	_register_self()
	status.emit("Yerel host açık (port %d)." % LOCAL_PORT)


func join_local() -> void:
	leave()
	var p := ENetMultiplayerPeer.new()
	if p.create_client("127.0.0.1", LOCAL_PORT) != OK:
		status.emit("İstemci oluşturulamadı.")
		return
	multiplayer.multiplayer_peer = p
	status.emit("Yerel hosta bağlanılıyor...")


# --- Ortak ---

func leave() -> void:
	if steam_ok and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	names.clear()
	left.emit()


func _on_connected() -> void:
	_register_self()
	status.emit("Bağlandı. Hostun pazarı açmasını bekle.")


func _register_self() -> void:
	var n := my_name()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		n += " #%d" % (multiplayer.get_unique_id() % 1000) # aynı PC'de iki pencere ayırt edilsin
	if multiplayer.is_server():
		names[1] = n
		lobby_changed.emit()
	else:
		register_name.rpc_id(1, n)


@rpc("any_peer", "reliable")
func register_name(n: String) -> void:
	names[multiplayer.get_remote_sender_id()] = n.left(32) # istemciden gelen ad: sınırla
	sync_names.rpc(names)
	lobby_changed.emit()


@rpc("authority", "reliable")
func sync_names(d: Dictionary) -> void:
	names = d
	lobby_changed.emit()
